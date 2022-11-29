library('data.table')
library('rads')
library('stringr')
library('DBI')
library('sf')
version = 'v3'
out = '[OMITTED]/frankenpop'
dir.create(file.path(out, version))
source('rake.R')
raceeths = c('White', 'Black', 'AIAN', 'Asian', 'NHPI', 'Hispanic')
re_grid = lapply(raceeths, function(x) c(0,1))
re_grid = do.call(CJ, re_grid)
setnames(re_grid, raceeths)

# drop the first two columns with are no race and only hispanic
re_grid = re_grid[3:nrow(re_grid)]
re_grid[, id := do.call(paste0, lapply(.SD, function(x) x))]
re_grid[, multi := rowSums(.SD)>1, .SDcols = setdiff(raceeths, 'Hispanic')]

# OFM SAEP: https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/estimates-april-1-population-age-sex-race-and-hispanic-origin
# Updates to cty_race require some manual adjustment
# cty_age is also sex
cty_race = openxlsx::read.xlsx("[OMITTED]/frankenpop/2021_saep/county_race_2021.xlsx")
cty_age = openxlsx::read.xlsx("[OMITTED]/frankenpop/2021_saep/ofm_pop_age_sex_postcensal_2010_2020_to_2021.xlsx", sheet = 'Population')
blk_pop = fread("[OMITTED]/frankenpop/saep_block20/saep_block20.csv")
setDT(cty_race)
setDT(cty_age)

# clean up cty_age
cty_age = cty_age[Area.Name != '.']
cty_age = melt(cty_age, id.vars = c('Area.Name', 'Area.ID', 'Age.Group'))
cty_age[, c('year', 'sex') := tstrsplit(variable, split ='.', fixed = T)]
cty_age = cty_age[Area.ID != 53 & sex != 'Total' & Age.Group != 'Total', .(county_name = Area.Name, 
                                          county = Area.ID, Age.Group, 
                                          aspop = as.numeric(value), 
                                          year = as.numeric(year), 
                                          gender = sex)]
cty_age = cty_age[year>=2020]

# clean up cty_race
cty_race = melt(cty_race, id.vars = c('geog', 'year'), variable.factor = FALSE, variable.name = 'raceeth')
cty_race = cty_race[geog != 'Washington' & raceeth != 'Total']
cty_race[, raceeth := as.character(factor(raceeth, 
                                          c("White", "Black", "AIAN", "Asian", "NHOPI", "More.Races", "Hispanic"),
                                          c("White", "Black", "AIAN", "Asian", "NHPI", "Multiple race", "Hispanic")))]
cty_race = cty_race[,.(county_name = geog, year, race_eth = raceeth, repop = value)]
cty_race = merge(cty_race, unique(cty_age[, .(county_name, county)]), by = 'county_name', all.x = T)

# clean up ofm block pop
blk_pop = blk_pop[, .(geo_id20 = as.character(GEOID20), POP2020,POP2021, POP2022)]

# rake the race/eth and age/sex stuff to match the 2022 pop estimates
cty_pop = blk_pop[, .(POP2022 = sum(POP2022)), by = .(county = substr(geo_id20, 1,5))]
## race/eth
cty_race = merge(cty_race, cty_pop, all.x = T, by ='county')
cty_race_22 = rake_nway(cty_race[year == 2021], 'repop', 'POP2022', list('county'))
cty_race = rbind(cty_race[, POP2022:=NULL], cty_race_22[, .(county, county_name, year = 2022, race_eth, repop)])

## age/sex
cty_age = merge(cty_age, cty_pop, all.x = T, by ='county')
cty_age_22 = rake_nway(cty_age[year == 2021], 'aspop', 'POP2022', list('county'))
cty_age = rbind(cty_age[, POP2022:=NULL], cty_age_22[, .(county, county_name, year = 2022, gender, Age.Group, aspop)])

## make block pop long
blk_pop = melt(blk_pop, id.vars = 'geo_id20', value.name = 'blkpop')
blk_pop[, year := as.numeric(gsub('POP', '', variable))]
blk_pop[, variable := NULL]

# Load frankenpop
fps = file.path(out, version, paste0('fpop_', re_grid[, id], '.rds'))
grid = lapply(fps, readRDS)
grid = rbindlist(grid)

ags = unique(cty_age[, .(Age.Group)])
ags[, ag := Age.Group]
ags[ag == '85 +', ag := '85-Inf']
ags[, c('lower','upper') := tstrsplit(ag, split = '-', fixed = TRUE)]
ags[, lower := as.numeric(lower)]
ags[, upper := as.numeric(upper)]
ags = ags[Age.Group != 'Total']
for(i in seq_len(nrow(ags))){
  #print(ags[i,])
  grid[age >= ags[i, lower] & age <= ags[i, upper], Age.Group := ags[i, Age.Group]]
}

# create a race_eth column for grid
grid[, nrace := rowSums(.SD), .SDcols = raceeths]
grid[nrace == 1 & White == 1, race_eth := 'White']
grid[nrace == 1 & Black == 1, race_eth := 'Black']
grid[nrace == 1 & AIAN == 1, race_eth := 'AIAN']
grid[nrace == 1 & Asian == 1, race_eth := 'Asian']
grid[nrace == 1 & NHPI == 1, race_eth := 'NHPI']
grid[nrace >1, race_eth := 'Multiple race']
grid[Hispanic == 1, race_eth := 'Hispanic']
grid[, nrace := NULL]

# Rake 2020 to 2020, and then move on by year
# this will not deal with aging up (e.g. cohorting) or add groups implied by the marginals
grid[, fpopstart := fpop]
og_grid = names(grid)
# split the grid by year
for(yyy in 2020:2022){
  print(yyy)
  # Add the marginals
  # race/eth
  st = nrow(grid)
  grid = merge(grid, cty_race[year == yyy, .SD, .SDcols = c('county', 'repop', 'race_eth')], all.x = T, by = c('county', 'race_eth'))
  
  # age/sex
  grid = merge(grid, cty_age[year == yyy, .(county, Age.Group, gender, aspop)], all.x = T, by = c('county', 'Age.Group', 'gender'))
  
  grid = merge(grid, blk_pop[year == yyy], all.x = T, by = c('geo_id20'))
  stopifnot(nrow(grid) == st)

  # if blkpop is 0, then if its ever not 0 later on, things get wonky
  # set blkpop to .001 as a placeholder
  grid[, zeroblock := blkpop == 0]
  grid[blkpop == 0, blkpop := .0001]  
  
  # rake to the block stuff first
  grid = rake_nway(grid, 'fpop',
                   c('blkpop'),
                   list('geo_id20'))
  
  # rake
  grid = rake_nway(grid, 'fpop', 
                   c('repop', 'aspop'), 
                   list(c('county', 'race_eth'), 
                        c('county', 'Age.Group', 'gender')))
  
  # when block pop is 0, save as 0, but keep nominal value for raking
  grid[, hold := fpop]
  grid[zeroblock == TRUE, fpop := 0]
  saveRDS(grid[ ,.SD, .SDcols = og_grid], file.path(out, version, paste0('raked_', yyy, '.rds')))
  grid[, fpop := hold]
  
  grid = grid[, .SD, .SDcols = og_grid]
  grid[, fpopstart := fpop]
  
}

#check that things more or less make sense
blkchk = merge(grid[, .(rpop = sum(fpop)), by = geo_id20], blk_pop[year == yyy], all.x = T, by = 'geo_id20')
racechk = merge(grid[, .(rpop = sum(fpop)), by = .(county, race_eth)], cty_race[year == yyy,], all.x = T, by = c('county', 'race_eth'))
aschk = merge(grid[, .(rpop = sum(fpop)), by = .(county, Age.Group, gender)], cty_age[year == yyy], all.x = T, by = c('county', 'Age.Group', 'gender'))

