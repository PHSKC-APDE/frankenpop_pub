library('data.table')
library('rads')
library('odbc')
library('DBI')
library('glue')
library('stringr')
library('logger')

# Set up variables and DB ----
overwrite = TRUE
recompute_pre2010 = FALSE
version = 'v3'
dir1 = '[OMITTED]/frankenpop'
dir2 = file.path('[OMITTED]/Frankenpop')
user = keyring::key_list('azure')[["username"]]
pass = keyring::key_get('azure', keyring::key_list('azure')[["username"]])

log_appender(appender_tee(file.path(dir2, version, 'compilelog')))


for(sd in c('forupload', 'todoh')){
  dir.create(file.path(dir2, version,sd))
}
mykey = 'azure'
con <- DBI::dbConnect(odbc::odbc(),
                      driver = getOption('rads.odbc_version'),
                      server = keyring::key_list(service = 'azure_server')$username[1],
                      database = keyring::key_get('azure_server', keyring::key_list(service = 'azure_server')$username[1]),
                      uid = keyring::key_list(mykey)[["username"]],
                      pwd = keyring::key_get(mykey, keyring::key_list(mykey)[["username"]]),
                      Encrypt = 'yes',
                      TrustServerCertificate = 'yes',
                      Authentication = 'ActiveDirectoryPassword')

fpop = rbindlist(lapply(2020:2022, function(x) readRDS(file.path(dir1, version, paste0('raked_', x,'.rds')))[, year:=x]))
#  fpop[, race_eth := paste0(White,Black, AIAN, Asian, NHPI, Hispanic)]

counties = unique(fpop[, county])

blk2sd = fread("C:/Users/dcasey/OneDrive - King County/frankenpop/Block20_SDUNI.csv")

# 2010 to 2020 blocks ----
fracs = fread(file.path(dir1, "tab2010_tab2020_st53_wa.txt"))
fracs[, frac10 := AREALAND_INT/AREALAND_2010]
fracs[, frac20 := AREALAND_INT/AREALAND_2020]
fracs[AREALAND_INT == 0, frac10 := AREAWATER_INT/AREAWATER_2010] #try to capture household type folks
fracs[AREALAND_INT == 0, frac20 := AREAWATER_INT/AREAWATER_2020]
# drop rows outside of Washington since we don't know how to deal with them
fracs = fracs[ STATE_2010 == STATE_2020]
fracs[, geo_id := paste0(STATE_2010, 
                         str_pad(COUNTY_2010,width = 3,side = 'left', pad = '0'),
                         str_pad(TRACT_2010,width = 6,side = 'left', pad = '0'),
                         str_pad(BLK_2010,width = 4,side = 'left', pad = '0'))]
fracs[, geo_id20 := paste0(STATE_2020, 
                           str_pad(COUNTY_2020,width = 3,side = 'left', pad = '0'),
                           str_pad(TRACT_2020,width = 6,side = 'left', pad = '0'),
                           str_pad(BLK_2020,width = 4,side = 'left', pad = '0'))]
fracs = fracs[, .(geo_id10 = geo_id, geo_id20, frac10, frac20, 
                  AREALAND_2010, AREALAND_2020, AREALAND_INT,
                  AREAWATER_2010, AREAWATER_2020, AREAWATER_INT)]


# Race grid ----
raceeths = c('White', 'Black', 'AIAN', 'Asian', 'NHPI', 'Hispanic')
re_grid = lapply(raceeths, function(x) c(0,1))
re_grid = do.call(CJ, re_grid)
setnames(re_grid, raceeths)
re_grid = re_grid[3:nrow(re_grid)]
re_grid[, id := do.call(paste0, lapply(.SD, function(x) x))]
re_grid[, multi := rowSums(.SD)>1, .SDcols = setdiff(raceeths, 'Hispanic')]



# create the table ----
## specify tables ----
thetab = DBI::Id(schema = 'ref', table = 'frankenpop_blk')
backtab =  DBI::Id(schema = 'ref', table = 'frankenpop_blk_backup')
## populate backup ----
dbGetQuery(con, glue_sql('drop table if exists {`backtab`}', .con = con))
dbGetQuery(con, glue_sql("EXEC sp_rename {paste(thetab@name, collapse = '.')}, {backtab@name['table']};", .con = con))

## recreate main table ----
dbGetQuery(con, glue_sql('drop table if exists {`thetab`}', .con = con))
dbGetQuery(con, glue_sql('create table {`thetab`}(
                          Hispanic tinyint ,
                          AgeGroup varchar(3),
                          Gender varchar(1),
                          RaceMars97 smallint,
                          Population float,
                          Year smallint,
                          CensusBlockCode2020 varchar(15))', .con = con))





load_via_bcp = function(dataset, table_name_inner = 'frankenpop_blk', field_term = "-t ,", row_term = paste0("-r \\n"), load_rows_inner= "", user, pass){
  filepath = tempfile(fileext = '.csv')
  fwrite(dataset, filepath)
  
  # Set up BCP arguments and run BCP
  bcp_args <- c(glue('ref.{table_name_inner} IN ', 
                     '"{filepath}" ',
                     '{field_term} {row_term} -C 65001 -F 2 ',
                     '-S "HHSAW" -d hhs_analytics_workspace ', #
                     '-b 100000 {load_rows_inner} -c ',
                     '-G -U {user} -P {pass} -D')) # 
  
  # Load
  a = system2(command = "bcp", args = c(bcp_args), stdout = TRUE, stderr = TRUE)
  
  file.remove(filepath)
}


# # subset ones that have already been run ----
# re_grid[, fileout := file.path(dir2,version,'forupload', paste0('block_', substr(id, 1,5),Hispanic,'.csv.gz'))]
# if(!overwrite) re_grid = re_grid[!file.exists(fileout)]

# OFM usually delivers the data with different files by year and geographic level
# at this stage, frankenpop is by race/eth.
# through R and SQL we'll compute the various derivatives.
# for now, we need to get the bcasts and fpop into a DB
# And also the past data adjusted for 2020 blocks
for(i in seq_len(re_grid[, .N])){
  log_info(paste(i, re_grid[i, id]))
  
  ## load backcasted data (2010 - 2020) ---
  fff = file.path(dir2, version, 'bcast', paste0('bcast_blk_',counties,'_',re_grid[i, id],'.rds'))
  bcasts = rbindlist(lapply(fff , readRDS))
  bcasts = bcasts[, .(race_eth, age, gender, year, geo_id, pop = backcast)]
  bcasts[, (raceeths) := lapply(seq_len(length(raceeths)), function(x) substr(race_eth, x,x))]
  bcasts = bcasts[year<2020]
  log_info(paste(i, 'Loaded bcast'))
  
  ## load the data from 2020 onwards ----
  onwards = merge(fpop, re_grid[i, .(White, Black, AIAN, Asian, NHPI, Hispanic)], by = raceeths)
  onwards[, c('pop', 'Age.Group', 'race_eth', 'fpopstart') := NULL]
  setnames(onwards, c('geo_id20', 'fpop'), c('geo_id', 'pop'))
  rmars = re_grid[i, substr(id, 1,5)]
  hlog = re_grid[i, Hispanic]
  log_info(paste(re_grid[i, id], 'Onwards!'))
  
  
  ## compile ----
  keepy = c('age', 'gender', 'year', 'geo_id', 'pop', raceeths)
  smashy = rbind(bcasts[pop>0, .SD, .SDcols = keepy],
                 #thepast[pop>0, .SD, .SDcols = keepy],
                 onwards[pop>0, .SD, .SDcols = keepy])
  rm(onwards); rm(bcasts);
  
  # Format block data
  smashy = smashy[, .(Hispanic, 
                      AgeGroup = str_pad(age, 3, side = 'left', 0),
                      Gender = substr(gender,1,1),
                      RaceMars97 = as.numeric(paste0(White, Black,AIAN, Asian,NHPI)), # change this to a set or addition operations
                      Population = pop,
                      Year = year,
                      CensusBlockCode2020 = geo_id)]
  log_info(paste(re_grid[i, id], 'Start write smashy'))
  load_via_bcp(smashy, user = user, pass = pass)
  rm(smashy);

  
  
}
rm(fpop)

# assuming the step below hasn't changed, just move data from back up into the updated thing


if(!recompute_pre2010){
  dbGetQuery(con, glue_sql('insert into {`thetab`} Select * from {`backtab`} where year <= 2009', .con = con))
}else{
  
  # process the pre 2010 data
  theseq = seq_len(re_grid[, .N])
  for(i in theseq){
    log_info(paste(i, re_grid[i, id], 'Process past data'))
    
    rmars = re_grid[i, substr(id, 1,5)]
    hlog = re_grid[i, Hispanic]
    
    ## load the data from 2009 and before ----
    # do it per year so that white poeple can work
    for(y in 2000:2009){
      log_info(paste(i, re_grid[i, id], 'start', y))
      thepast = glue::glue_sql('select year, geo_id, age, gender, raw_racemars, race_hisp, pop
                               from ref.pop_blk
                               where raw_racemars = {rmars} and race_hisp = {hlog} and year = {y}', .con = con)
      thepast = dbGetQuery(con, thepast)
      log_info(paste(re_grid[i, id], y, 'fetched'))
      
      setDT(thepast)
      thepast[, gender := factor(gender, levels = c(2, 1), labels = c("Female", "Male"))]
      setnames(thepast,
               'race_hisp',
               'Hispanic')
      thepast[, c('Hispanic') := as.numeric(Hispanic)]
      thepast[, (setdiff(raceeths, 'Hispanic')) := lapply(seq_len(length(raceeths)-1), function(x) substr(raw_racemars, x,x))]
      
      ### add the conversion ratios ----
      thepast = merge(fracs, thepast, all.x = T, by.x = 'geo_id10', by.y = 'geo_id', allow.cartesian = TRUE)
      
      thepast = thepast[!is.na(pop),
                        .(pop = sum(pop * frac10, na.rm = T)), # a 2010 block contributes pop * fraction overlap with the 2020 block to that block
                        by = c('geo_id20', 'age', 'gender', 'year', raceeths)]
      setnames(thepast, 'geo_id20', 'geo_id')
      keepy = c('age', 'gender', 'year', 'geo_id', 'pop', raceeths)
      log_info(paste(re_grid[i, id], y, 'converted to 2020 blocks'))
      thepast = thepast[pop>0, .SD, .SDcols = keepy]
      thepast = thepast[, .(Hispanic, 
                          AgeGroup = str_pad(age, 3, side = 'left', 0),
                          Gender = substr(gender,1,1),
                          RaceMars97 = as.numeric(paste0(White, Black,AIAN, Asian,NHPI)),
                          Population = pop,
                          Year = year,
                          CensusBlockCode2020 = geo_id)]
    
      log_info(paste(re_grid[i, id], y, 'Write the past'))
      load_via_bcp(thepast, user = user, pass = pass)
      
    }
  }
}

# create an index ----
log_info('Create index')
dbGetQuery(con, 'drop index if exists idx_fpopblk on ref.frankenpop_blk')
dbGetQuery(con, 'create clustered columnstore index idx_fpopblk on ref.frankenpop_blk')
log_info('All done')




