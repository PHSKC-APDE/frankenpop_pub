library('data.table')
library('DBI')
library('rads')
library('glue')
library('stringr')
library('logger')

version = 'v3'
indir = '[OMITTED]/frankenpop'
outdir = file.path('[OMITTED]/Frankenpop')
dir.create(file.path(file.path('[OMITTED]/Frankenpop', version)))
dir.create(file.path(file.path('[OMITTED]/Frankenpop', version, 'bcast')))

update_blocks = FALSE

# set up logging ----
log_appender(appender_tee(file.path(outdir, version, 'bcastlog')))

# load fpop ----
fpop = readRDS(file.path(indir, version, 'raked_2020.rds'))
fpop[, race_eth_8cat := race_eth]
fpop[, race_eth := paste0(White,Black, AIAN, Asian, NHPI, Hispanic)]
fracs = fread(file.path(indir, "tab2010_tab2020_st53_wa.txt"))
raceeths = c('White', 'Black', 'AIAN', 'Asian', 'NHPI', 'Hispanic')
source('rake.R')

# Declare important objects ----
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

# Define functions ----
load_raw_ofm = function(con, type = c('state_agg', 'county_agg', 'block'), county = '53033', btable = NULL, racemars = '10000', hispanic = 0){
  
  type = match.arg(type, c('state_agg', 'county_agg', 'block'))
  
  subrace = glue::glue_sql('raw_racemars = {racemars} AND race_hisp = {hispanic}', .con = con)
  
  if(type == 'state_agg'){
    q = glue::glue_sql('select year, age, gender, raw_racemars, race_hisp, sum(pop) as pop
                       from ref.pop_blk
                       where {subrace} and year >= 2010
                       group by year, age, gender, raw_racemars, race_hisp',
                       .con = con)
  }else if (type == 'county_agg'){
    if(!is.null(county)){
      csub = glue::glue_sql('county_code = {county} AND', .con = con)
    }else{
      csub = SQL('')
    }
    
    q = glue::glue_sql('select year, county_code, age, gender, race_hisp, raw_racemars, sum(pop) as pop
                       from ref.pop_blk
                       where {csub} {subrace} AND year >= 2010
                       group by year, age, gender, raw_racemars, race_hisp, county_code
                   ', .con = con) 
    
  }else{
    # stopifnot(!is.null(county))
    if(!is.null(county)){
      county_sub = glue_sql('AND bt.county = {x}', .con = con)
    }else{
      county_sub = SQL('')
    }
    stopifnot(!is.null(btable))
    q = glue::glue_sql('select year, pb.geo_id, age, gender, raw_racemars, race_hisp, pop
                       from ref.pop_blk as pb 
                       inner join {`btable`} as bt on pb.geo_id = bt.geo_id
                       where {subrace} AND year >= 2010 {county_sub}', .con = con) 
  }
  
  pop = dbGetQuery(con, q)
  setDT(pop)
  
  if(type == 'state_agg'){
    pop[, geo_id := '53']
    pop[, level := 'state']
  }else if(type == 'county_agg'){
    setnames(pop, 'county_code', 'geo_id')
    pop[, level := 'county']
  }else(
    pop[, level := 'block']
  )
  
  pop[, gender := factor(gender, levels = c(2, 1), labels = c("Female", "Male"))]
  
  setnames(pop, 
           'race_hisp',
           'Hispanic')
           
  
  pop[, c('Hispanic') := as.numeric(Hispanic)]
  
  pop[, race_eth := paste0(raw_racemars, Hispanic)]
  
  pop
  
  
}

#agg_cols-- the columns with the obs_devi for higher levels. Named list. smalled item at the front of the list
backcast = function(start, target, agg_cols = NULL){
  
  if(!is.integer(start[, year])) start[, year := as.integer(year)]
  
  # make a grid
  # any population group that shows up in start or target
  grid = unique(rbind(start[, .(geo_id, age, gender, race_eth)],
                      target[,.(geo_id, race_eth, gender, age)]))
  
  # add year
  grid = rbindlist(lapply(2010:2020, function(x) copy(grid)[, year := x]))
  
  # confirm that start is unique by the factors we expect
  setorderv(start, c('geo_id', 'race_eth', 'age', 'gender', 'year'))
  stopifnot(all(start[, .N, by = .(geo_id, race_eth, age, gender, year)][, N==1]))
  
  grid = merge(grid, start, all.x = T, by = c('geo_id', 'race_eth', 'age', 'gender', 'year'))
  grid[is.na(pop), pop := 0]
  rm(start)
  
  grid = merge(grid, target, all.x = T, by= c('geo_id', 'race_eth', 'age', 'gender'))
  grid[, level := NULL]
  
  grid[is.na(fpop), fpop := 0]
  
  # range
  nyr = range(grid[, year])
  nyr = nyr[2]-nyr[1]
  
  # observed slope
  grid[, obs_slope := (pop[which.max(year)] - pop[which.min(year)])/nyr, 
       by = c('geo_id', 'race_eth', 'age', 'gender')]
  
  # target
  grid[, tgt_slope := (fpop[which.max(year)] - pop[which.min(year)])/nyr, 
       by = c('geo_id', 'race_eth', 'age', 'gender')]
  
  # compute deviation from observed line
  grid[, obs_line := pop[which.min(year)] + obs_slope * (year-2010), .(geo_id, race_eth, age, gender)]
  grid[, obs_devi := pop/obs_line]
  
  if(!is.null(agg_cols)){
    stopifnot(is.list(agg_cols))
    stopifnot(!is.null(names(agg_cols)))
    
    ag_nm = names(agg_cols)
    
    # rename things
    agg_cols = lapply(names(agg_cols), function(x){
      ag = agg_cols[[x]]
      ag = ag[, .(race_eth, age, gender, year, obs_devi)]
      stopifnot(all(ag[, .N, .(race_eth, age,gender,year)][, N==1]))
      setnames(ag, 'obs_devi', x)
      
      return(ag)
    })
    names(agg_cols) <- ag_nm
    
    # split the grid
    grid_na = grid[is.na(obs_devi) | obs_devi == Inf]
    if(nrow(grid_na)>0){
      for(col in ag_nm){
        grid_na = merge(grid_na, agg_cols[[col]], all.x = T, by = c('race_eth', 'age', 'gender', 'year'))
        grid_na[is.na(obs_devi), obs_devi := get(col)]
      }
      grid_na[, (ag_nm) := NULL]
      
      grid = rbind(grid[!(is.na(obs_devi) | obs_devi == Inf)], grid_na)
    }

    
  }
  # if still NA, just assume no deviation (e.g. a value of 1)
  grid[is.na(obs_devi) | obs_devi == Inf, obs_devi := 1]
  
  # compute new values
  grid[, target_line := pop[which.min(year)] + tgt_slope * (year -2010),.(geo_id, race_eth, age, gender)]
  grid[, backcast := target_line * obs_devi]
  
  # a bit of clean up
  grid[, c('obs_slope', 'tgt_slope', 'obs_line', 'target_line') := NULL]
  
  # return the grid
  return(grid)
  
}

# make fractions for the blocks ----
### borrowed from create_blk_frankenpop.R
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
fracs = fracs[, .(geo_id, geo_id20, frac10, frac20, 
                  AREALAND_2010, AREALAND_2020, AREALAND_INT,
                  AREAWATER_2010, AREAWATER_2020, AREAWATER_INT)]

# add the fractions to DB ----
# identify which blocks in 2010 contribute to 2020 blocks in a given county ---
bt =  DBI::Id(schema = 'dcasey', table = 'blks_2020')
if(update_blocks){
  dbGetQuery(con, glue::glue_sql('drop table if exists {`bt`}', .con = con))
  source_blks = fracs[, .(geo_id = unique(geo_id))]
  source_blks = source_blks[, county := as.integer(substring(geo_id, 1, 5))]
  # write those to the db ---
  dbWriteTable(con, bt,  source_blks, overwrite = TRUE)
}


# Clean up fpop ----
setnames(fpop, 'geo_id20', 'geo_id')
fpop = fpop[, .SD, .SDcols = c("geo_id", "race_eth", "gender", "age", "fpop", 'county')]

# Make a re_grid ----
re_grid = lapply(raceeths, function(x) c(0,1))
re_grid = do.call(CJ, re_grid)
setnames(re_grid, raceeths)
re_grid = re_grid[3:nrow(re_grid)]
re_grid[, id := do.call(paste0, lapply(.SD, function(x) x))]
re_grid[, multi := rowSums(.SD)>1, .SDcols = setdiff(raceeths, 'Hispanic')]

# For each race/eth
raceseq = seq_len(re_grid[, .N])
for(i in raceseq){
  log_info(paste(i, re_grid[i, id]))
  rmars = re_grid[i, substr(id, 1,5)]
  hlog = re_grid[i, Hispanic]
  
  # Process the whole state ----
  ## Load raw OFM data for the state ----
  ofm_state = load_raw_ofm(con, type = 'state_agg',
                           racemars = rmars, 
                           hispanic = hlog)
  
  ## Load 2020 frankenpop for the state ----
  fpop_state = fpop[race_eth == re_grid[i, id], .(fpop = sum(fpop), geo_id = '53'), c('race_eth', 'gender', 'age')]
  
  
  ## compute backcasts ----
  bcast_state = backcast(ofm_state, fpop_state)
  bcast_state[(backcast<0 | abs(backcast) <1e-10) & year == 2020 & fpop ==0, backcast := 0]
  
  saveRDS(bcast_state[backcast>0], file.path(outdir,version,'bcast',paste0('bcast_state_', re_grid[i, id],'.rds')))
  
  # Process by county ----
  counties = fpop[, unique(county)]
  ofm_county = load_raw_ofm(con, 'county_agg', NULL, racemars = rmars, hispanic = hlog)
  fpop_county = fpop[race_eth == re_grid[i, id], .(fpop = sum(fpop)), by = .(geo_id = county, race_eth, gender, age)]

  # compute back cast
  bcast_county = backcast(ofm_county, fpop_county, agg_cols = list(state = bcast_state))
  
  # some weird negative numbers that should be 0
  # looks like its random
  bcast_county[(backcast<0 | abs(backcast) <1e-10) & year == 2020 & fpop ==0, backcast := 0]
  stopifnot(all(bcast_county[, backcast>=0]))
  
  ## rake to state level ----
  rt_state = bcast_state[, .(race_eth, age, gender, year, target = backcast)]
  bcast_county = merge(bcast_county, rt_state, all.x = T, 
                       by = intersect(names(bcast_county), names(rt_state)))
  
  # This might not be required since OFM is already internally consistent
  raked_county = rake_nway(bcast_county, 'backcast', 'target', list(c('year', 'race_eth', 'age', 'gender')))
  raked_county[, c('start', 'chg') := NULL]
  saveRDS(raked_county[backcast>0], file.path(outdir,version,'bcast', paste0('bcast_counties_',re_grid[i, id],'.rds')))

  # Process by block ----
  ## For each set of blocks in a county ----
  # bcast_block = lapply(counties, function(x){
    
  # load the block level data for the county ----
  blk = load_raw_ofm(con, type = 'block', county = NULL,bt,
                     racemars = rmars, hispanic = hlog)
  

  # add the conversion ratios ----
  blk = merge(fracs, blk, all.x = T, by = 'geo_id', allow.cartesian = TRUE)
  
  blk = blk[!is.na(pop),
            .(pop = sum(pop * frac10, na.rm = T)), # a 2010 block contributes pop * fraction overlap with the 2020 block to that block
            by = c('geo_id20', 'age', 'gender', 'race_eth', 'year')]
  setnames(blk, 'geo_id20', 'geo_id')


  # compute backcast ----
  blk[, year:=as.integer(year)]
  blk[, county := substr(geo_id, 1,5)]  
  for(x in counties){
    log_info(paste('Blk, county',x))
    fpop_c = fpop[county == x & race_eth == paste0(rmars, hlog), .(geo_id, race_eth, gender, age, fpop)]
    blk_c = blk[county == x][, county := NULL]
    bcast_blk = backcast(blk_c, fpop_c, agg_cols =list(county = raked_county[geo_id == x & race_eth == rmars], state = bcast_state[race_eth == rmars]))
    
    rm(blk_c); rm(fpop_c);
    
    # to save space, drop 0 columns and remove rando objects
    bcast_blk = bcast_blk[backcast>0] # | pop>0

    
    # rake to county ----
    ## rake to state level ----
    rt_county = raked_county[geo_id == x, .(race_eth, age, gender, year, target = backcast)]
    bcast_blk = merge(bcast_blk, rt_county, all.x = T, 
                      by = intersect(names(bcast_blk), names(rt_county)))
    rm(rt_county)
    bcast_blk = rake_nway(bcast_blk, 'backcast', 'target', list(c('year', 'race_eth', 'age', 'gender')))
    bcast_blk[, c('start', 'chg') := NULL]
    
    # write the results to disk
    saveRDS(bcast_blk, file.path(outdir, version, 'bcast', paste0('bcast_blk_',x,'_',re_grid[i, id],'.rds')))
    
    rm(bcast_blk)

  }
}
  
# })


