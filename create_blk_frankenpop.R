library('data.table')
library('rads')
library('stringr')
library('DBI')
library('sf')
library('logger')
library('glue')
# Load data and set parameters ----
indir = '[OMITTED]/frankenpop'
out = '[OMITTED]'
version = 'v3'
dir.create(file.path(out, version))
log_appender(appender_tee(file.path(out, version, 'create_blk_frankenpop')))

# redist = readRDS(file.path(out, '2020_redist_pop.rds'))
redist = readRDS(file.path(indir, 'blk_2020_census.rds'))
fracs = fread(file.path(indir, "tab2010_tab2020_st53_wa.txt"))
marsadj = readRDS(file.path(indir, 'mars_adjustment.rds'))
raceeths = c('White', 'Black', 'AIAN', 'Asian', 'NHPI', 'Hispanic')
log_info('Load shared data')

mykey = 'azure'
con <- pool::dbPool(odbc::odbc(),
                      driver = getOption('rads.odbc_version'),
                      server = keyring::key_list(service = 'azure_server')$username[1],
                      database = keyring::key_get('azure_server', keyring::key_list(service = 'azure_server')$username[1]),
                      uid = keyring::key_list(mykey)[["username"]],
                      pwd = keyring::key_get(mykey, keyring::key_list(mykey)[["username"]]),
                      Encrypt = 'yes',
                      TrustServerCertificate = 'yes',
                      Authentication = 'ActiveDirectoryPassword')

log_info('Start MARS')
# Adjust the redistricting data by 2010 MARS to remove other category ----
redist[, GEOID := gsub('7500000US', '', GEOID, fixed = T)]
redist[, county := as.factor(as.numeric(substr(GEOID, 3,5)))]
redist[, age_grp := as.factor(age_grp)]
hold = redist[, .(tpop = sum(pop)), c('county', 'age_grp')]

## add on adj factors ----
redist = merge(redist[Other == 0], 
               marsadj[, .SD, .SDcols = c('county', 'age_grp', raceeths, 'marsadj')],
               all.x = TRUE, by = c('county', 'age_grp', raceeths))
redist[is.na(marsadj), marsadj := 1]
redist[, mapop := pop * marsadj]
redist = merge(redist, hold, all.x = T, by = c('county', 'age_grp'))

## match county/age_grp marginals ----
# we can't also do by race, since the other category is annoying
redist[, mapop2 := mapop * tpop/sum(mapop), by = .(county, age_grp)]

## clean up ----
redist[, c('Other', 'pop', 'marsadj', 'mapop', 'tpop', 'cmapop') := NULL]
setnames(redist, 'GEOID', 'geo_id20')
setnames(redist, 'mapop2', 'cpop')
log_info('End MARS')

log_info('Prep OFM pop')
# OFM SADE Pop ----
## Fetch blk x gender x single year age x race/eth population and standardize the columns ----
pop = dbGetQuery(con, 'Select * from ref.pop_blk where year = 2020')
setDT(pop)
pop[, gender := factor(gender, levels = c(2, 1), labels = c("Female", "Male"))]
pop = pop[, .(pop, geo_type, geo_id, year, age, gender,
              Hispanic = race_hisp, raw_racemars)]
for(rrr in seq_along(raceeths[1:5])){
  pop[, (raceeths[rrr]) := as.numeric(substr(raw_racemars,rrr,rrr))]
}

pop[, (raceeths) := lapply(.SD, as.numeric), .SDcols = raceeths]
pop[, raw_racemars := NULL]
pop[, age_grp := as.character(factor(age>=18, c(T,F), c('18', 'lte17')))]

log_info('Prep fractions')
# Prep the 2010 block to 2020 block conversion ----
## make fractions for the blocks ----
fracs[, frac10 := AREALAND_INT/AREALAND_2010]
fracs[, frac20 := AREALAND_INT/AREALAND_2020]
fracs[AREALAND_INT == 0, frac10 := AREAWATER_INT/AREAWATER_2010] #try to capture household type folks
fracs[AREALAND_INT == 0, frac20 := AREAWATER_INT/AREAWATER_2020]

# drop rows outside of Washington since we don't know how to deal with them
fracs = fracs[ STATE_2010 == STATE_2020]

## clean up ----
fracs[, geo_id := paste0(STATE_2010, 
                         str_pad(COUNTY_2010,width = 3,side = 'left', pad = '0'),
                         str_pad(TRACT_2010,width = 6,side = 'left', pad = '0'),
                         str_pad(BLK_2010,width = 4,side = 'left', pad = '0'))]
fracs[, geo_id20 := paste0(STATE_2020, 
                         str_pad(COUNTY_2020,width = 3,side = 'left', pad = '0'),
                         str_pad(TRACT_2020,width = 6,side = 'left', pad = '0'),
                         str_pad(BLK_2020,width = 4,side = 'left', pad = '0'))]
fracs = fracs[, .(geo_id, geo_id20, frac10, frac20, 
                  AREALAND_2010, AREALAND_2020, AREALAND_INT,
                  AREAWATER_2010, AREAWATER_2020, AREAWATER_INT)]

# compute 2020 block level OFM population numbers from 2010 block definitions ----
b20 = merge(fracs, pop, all.x = T, by = 'geo_id', allow.cartesian = TRUE)

b20 = b20[, 
          .(pop = sum(pop * frac10, na.rm = T)), # a 2010 block contributes pop * fraction overlap with the 2020 block to that block
          by = c('geo_id20', 'age', 'gender', 'age_grp', raceeths)]
b20 = na.omit(b20)
rm(pop)

## by race ----
loops = unique(redist[, .SD, .SDcols = raceeths])

redist[, county := paste0('53', stringr::str_pad(county, width = 3,side = 'left', pad = '0'))]
blks = unique(redist$geo_id20)

# set up output DB structure
table_name_inner = 'frankenpop_step1'
thetab = DBI::Id(schema = 'dcasey', table = table_name_inner)
# create the table
dbGetQuery(con, glue_sql('drop table if exists {`thetab`}', .con = con))
dbGetQuery(con, glue_sql('create table {`thetab`}(
                          county varchar(5),
                          tract varchar(11),
                          geo_id20 varchar(15),
                          Hispanic tinyint,
                          White tinyint,
                          Black tinyint,
                          AIAN tinyint,
                          Asian tinyint,
                          NHPI tinyint,
                          gender varchar(6),
                          age int,
                          pop float,
                          fpop float)', .con = con))



## For loop ----
for(i in 1:nrow(loops)){
  log_info(paste(i, "|", do.call(paste, (loops[i,]))))
  
  ### init subgrid ----
  grid = CJ(age = b20[, unique(age)],
            geo_id20 = blks,
            gender = c('Female', 'Male')
  )
  
  ### create age_grp ----
  grid[, age_grp := as.character(factor(age<=17, c(T,F), c('lte17', '18')))]
  grid = na.omit(grid)
  grid = cbind(grid, loops[i])
  
  ### add pop numbers ----
  grid = merge(grid, b20, all.x = T, by = names(grid))

  ### for each blk X age_grp X race_eth combo, compute total pop and the relative fraction ----
  grid[is.na(pop), pop := 0]
  grid[, pop_age_grp := sum(pop, na.rm = T), by = c('geo_id20', raceeths, 'age_grp')]
  grid[, popfrac_ag := pop/pop_age_grp]
  grid[is.na(popfrac_ag), popfrac_ag := 0]
  
  ### merge on districting results ----
  grid = merge(grid, redist, all.x = T, by = c('geo_id20', raceeths, 'age_grp'))
  
  ### To save space, drop places where there is no pop ----
  grid = grid[!is.na(cpop), ]
  grid = grid[cpop>0]
  
  ### compute patterns for fill in ----
  #### for block X age_grp X race_eth combos that have pop in the redistricting data, but not OFM, use the tract pattern ----
  grid[, tract := substr(geo_id20, 1, nchar(geo_id20) - 4)]
  tractpat = grid[, .(pop = sum(pop)), c('tract', raceeths, 'gender', 'age', 'age_grp')]
  tractpat[, pop_age_grp_trt := sum(pop, na.rm = T), by = c('tract', raceeths, 'age_grp')]
  tractpat[, popfrac_ag_trt := pop/pop_age_grp_trt]
  setnames(tractpat, 'pop', 'pop_trt')
  tractpat[, age_grp := NULL]
  
  ### make a county pattern just in case----
  grid[, county := substr(geo_id20,1,5)]
  ctypat = grid[, .(pop = sum(pop)), c('county', raceeths, 'gender', 'age', 'age_grp')]
  ctypat[, pop_age_grp_cty := sum(pop, na.rm = T), by = c('county', raceeths, 'age_grp')]
  ctypat[, popfrac_ag_cty := pop/pop_age_grp_cty]
  setnames(ctypat, 'pop', 'pop_cty')
  ctypat[, age_grp := NULL]
  
  ### A few counties might not have a given race/age combo. Use state pattern instead---
  stpat = grid[, .(pop = sum(pop)), c(raceeths, 'gender', 'age', 'age_grp')]
  stpat[, pop_age_grp_st := sum(pop, na.rm = T), by = c(raceeths, 'age_grp')]
  stpat[, popfrac_ag_st := pop/pop_age_grp_st]
  setnames(stpat, 'pop', 'pop_st')
  stpat[, age_grp := NULL]
  
  ### add the patterns to the grid ----
  grid = merge(grid, tractpat, all.x = TRUE, by = c('tract', 'gender', 'age', raceeths))
  grid = merge(grid, ctypat, all.x = TRUE, by = c('county', 'gender', 'age', raceeths))
  grid = merge(grid, stpat, all.x = TRUE, by = c('gender', 'age', raceeths))
  
  ### clean up a bit ----
  rm(ctypat); rm(tractpat);
  
  ### compute the pops ----
  grid[, fpop := cpop * popfrac_ag] # block level
  grid[cpop>0 & pop_age_grp == 0, fpop := cpop * popfrac_ag_trt] # tract level
  grid[cpop>0 & pop_age_grp_trt == 0, fpop := cpop * popfrac_ag_cty] # county
  grid[cpop>0 & pop_age_grp_cty == 0, fpop := cpop * popfrac_ag_st] # state
  # if the cpop group is totally new (e.g. OFM doesn't have ANYTHING)
  # distribute equally by age within a block/gender/race
  grid[cpop>0 & pop_age_grp_st == 0, fpop := cpop/.N, by = c('geo_id20', 'age_grp', 'gender', raceeths)]

    
  ### compute leftovers by race_eth and age_grp and county ----
  left = grid[, .(fpop = sum(fpop)), by = c('county', 'age_grp', raceeths)]
  left = merge(left, 
               redist[, .(tpop= sum(cpop)), c('age_grp', raceeths, 'county')], 
               all.x = T, by = c('county', 'age_grp', raceeths))
  left[, scalar := tpop/fpop]
  
  if(any(left[, is.na(scalar)])) stop('weird scalar')
  left[, c('fpop', 'tpop') := NULL]
  ### apply leftovers scaling ----
  grid = merge(grid, left, all.x = T, by = c('county', 'age_grp', raceeths))
  grid[, fpop := fpop * scalar]
  
  ### confirm it worked ----
  stopifnot(all.equal(grid[, sum(fpop)], merge(redist, loops[i], by = setdiff(names(loops), 'gender'))[, sum(cpop)]))
  
  ### check the marginals ----
  mrgn = grid[, .(fpop = sum(fpop)), by = c('age_grp', raceeths, 'geo_id20')]
  mrgn = merge(merge(redist, loops[i], by = setdiff(names(loops), 'gender')),
               mrgn,
               all.x = T, by = c('age_grp', raceeths, 'geo_id20'))
  mrgn[is.na(fpop), fpop := 0]
  
  stopifnot(all(abs(mrgn[, cpop - fpop]) <= 1e-10))
  
  ### clean up and save results ----
  grid = grid[fpop>0 | pop >0]
  grid = grid[, .SD, .SDcols = c('county', 'tract', 'geo_id20', raceeths, 'gender', 'age', 'pop', 'fpop')]
  
  #write to the database
  # bcp everything ----
  field_term = "-t ,"
  row_term = paste0("-r \\n")
  load_rows_inner = ""
  user = keyring::key_list('azure')[["username"]]
  pass = keyring::key_get('azure', keyring::key_list('azure')[["username"]])
  filepath = tempfile(fileext = '.csv')
  fwrite(grid, filepath)
  bcp_args <- c(glue('dcasey.{table_name_inner} IN ', 
                     '"{filepath}" ',
                     '{field_term} {row_term} -C 65001 -F 2 ',
                     '-S "HHSAW" -d hhs_analytics_workspace ', #
                     '-b 100000 {load_rows_inner} -c ',
                     '-G -U {user} -P {pass} -D')) # 
  
  # Load
  system2(command = "bcp", args = c(bcp_args))
  file.remove(filepath)
  # saveRDS(grid, file.path(out,version, paste0('fpop_', loops[i, paste(.SD, collapse = '')], '.rds')))
  
}


log_info('Create index')
dbGetQuery(con, glue_sql('drop index if exists  idx_fpop1 on {`thetab`}', .con = con))
dbGetQuery(con, glue_sql('create clustered columnstore index idx_fpop1 on {`thetab`}', .con = con))
log_info('All done')



