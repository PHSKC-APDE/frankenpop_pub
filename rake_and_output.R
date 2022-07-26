library('data.table')
library('rads')
library('stringr')
library('DBI')
library('sf')
version = 'v2'
out = 'C:/Users/dcasey/OneDrive - King County/frankenpop'
grid = readRDS(file.path(out, 'frankenblkpop_wa.rds'))
dir.create(file.path(out, version))

# OFM SAEP: https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/estimates-april-1-population-age-sex-race-and-hispanic-origin
# Updates to cty_race require some manual adjustment
# cty_age is also sex
cty_race = openxlsx::read.xlsx("C:/Users/dcasey/OneDrive - King County/frankenpop/2021_saep/county_race_2021.xlsx")
cty_age = openxlsx::read.xlsx("C:/Users/dcasey/OneDrive - King County/frankenpop/2021_saep/ofm_pop_age_sex_postcensal_2010_2020_to_2021.xlsx", sheet = 'Population')
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

# clean up cty_race
cty_race = melt(cty_race, id.vars = c('geog', 'year'), variable.factor = FALSE, variable.name = 'raceeth')
cty_race = cty_race[geog != 'Washington' & raceeth != 'Total']
cty_race[, raceeth := as.character(factor(raceeth, 
                                          c("White", "Black", "AIAN", "Asian", "NHOPI", "More.Races", "Hispanic"),
                                          c("White", "Black", "AIAN", "Asian", "NHPI", "Multiple race", "Hispanic")))]
cty_race = cty_race[,.(county_name = geog, year, race_eth = raceeth, repop = value)]
cty_race = merge(cty_race, unique(cty_age[, .(county_name, county)]), by = 'county_name', all.x = T)

# add age groups to frankenpop
ags = unique(cty_age[, .(Age.Group)])
ags[, ag := Age.Group]
ags[ag == '85 +', ag := '85-Inf']
ags[, c('lower','upper') := tstrsplit(ag, split = '-', fixed = TRUE)]
ags[, lower := as.numeric(lower)]
ags[, upper := as.numeric(upper)]
ags[Age.Group != 'Total']
for(i in seq_len(nrow(ags))){
  print(ags[i,])
  grid[age >= ags[i, lower] & age <= ags[i, upper], Age.Group := ags[i, Age.Group]]
}

grid[, .N, keyby = .(age, Age.Group)]

# Rake things to race/eth and age/sex by county
# A one way raker
# borrow from https://github.com/ihmeuw/USHD/blob/life_expectancy_race_ethnicity_2022/sae.shared/R/rake.r
# This will modify by reference
rake <- function(data, value_var, agg_var, constant_vars, replace_value = F) {

  # sum over weighted mortality rates to get a crude total mx
  data[, sum_weighted_value := sum(get(value_var)), by = c(constant_vars, agg_var)]
  
  # generate raking weights
  data[, raking_weight := get(agg_var) / sum_weighted_value]
  
  # if all counts are zero raking_weight will be NA. Convert to zeros.
  data[is.na(raking_weight), raking_weight := 0]
  
  # generate raked estimates by multiplying the original by the raking weights
  data[, raked_value := get(value_var) * raking_weight]
  
  if (nrow(data[is.na(raked_value)]) > 0) {
    stop("Rake function produced NAs.")
  }
  
  if (replace_value) {
    data[, value := raked_value]
    data[, raked_value := NULL]
  }
  
  data[, intersect(names(data), c("weighted_value", "sum_weighted_value", "raking_weight")) := NULL]
  
  return(data)
}

rake_nway = function(dat, value_var, agg_vars, constant_vars, max_iter = 500, tol = 1e-10){
  
  # init
  dat = copy(dat)
  dat[, start := get(value_var)]
  dat[, chg := 1]
  iter = 1
  
  stopifnot(is.list(constant_vars))
  stopifnot(length(agg_vars) == length(constant_vars))
  
  while(iter<max_iter & max(dat[, chg])>tol){
    
    # for each margin
    for(i in seq_along(agg_vars)){
     
      # rake
      dat = rake(dat, value_var, agg_var = agg_vars[i], constant_vars[[i]])
      
      # update
      dat[, (value_var) := raked_value]
      dat[, raked_value := NULL]
      
    }
    
    # compute change
    dat[, chg := abs(get(value_var) - start)]
    
    #update beginning value
    dat[, start := get(value_var)]
    
    iter = iter + 1
    
  }
  
  converge = iter<max_iter & max(dat[, chg])<=tol
  
  if(!converge){
    stop('Did not converge')
  }
  
  return(dat)
  
}



# Rake 2020 to 2020, and then move on by year
# this will not deal with aging up (e.g. cohorting) or add groups implied by the marginals
og_grid = names(grid)
res = grid
for(yyy in 2020:2021){
  # Add the marginals
  # race/eth
  res = merge(res, cty_race[year == yyy, .(race_eth, repop, county)], all.x = T, by = c('county', 'race_eth'))
  
  # age/sex
  res = merge(res, cty_age[year == yyy, .(county, Age.Group, gender, aspop)], all.x = T, by = c('county', 'Age.Group', 'gender'))
  
  # rake
  res = rake_nway(res, 'fpop', c('repop', 'aspop'), list(c('county', 'race_eth'), c('county', 'Age.Group', 'gender')))
  
  res = res[, .SD, .SDcols = og_grid]
  
  assign(paste0('raked_', yyy), res)
  
}
rm(res)

# compile
res = merge(grid, raked_2020[, .(geo_id20, race_eth, gender, age, rpop2020 = fpop)], 
            by = c('geo_id20', 'race_eth', 'gender', 'age'))
res = merge(res, raked_2021[, .(geo_id20, race_eth, gender, age, rpop2021 = fpop)], 
            by = c('geo_id20', 'race_eth', 'gender', 'age'))

# Summary sheets
as_sum = res[, .(ofm = sum(pop), fpop = sum(fpop), rpop20 = sum(rpop2020), rpop21 = sum(rpop2021)),
             keyby = .(county, Age.Group, gender)]
cty_age = dcast(cty_age[year %in% c(2020:2021),.(county, Age.Group, aspop, gender, year)],
                county + Age.Group + gender ~ year, value.var = 'aspop')
setnames(cty_age, c('2020', '2021'), c('as2020', 'as2021'))
as_sum = merge(as_sum, cty_age, all.x = T, by = c('county', 'Age.Group', 'gender'))

re_sum = res[, .(ofm = sum(pop), fpop = sum(fpop), rpop20 = sum(rpop2020), rpop21 = sum(rpop2021)),
             keyby = .(county, race_eth)]
cty_race = dcast(cty_race[year %in% c(2020:2021),.(county, repop, race_eth, year)],
                county + race_eth ~ year, value.var = 'repop')
setnames(cty_race, c('2020', '2021'), c('re2020', 're2021'))
re_sum = merge(re_sum, cty_race, all.x = T, by = c('county', 'race_eth'))


# Save results
saveRDS(res, file.path(out, version, 'frankenpop_wa_raked.rds'))

res[, Age.Group:=NULL]
setnames(res, c('pop', 'fpop'), c('ofmpop20', 'fpop20'))
setorder(res, geo_id20, race_eth, gender, age)
#save CSVs by county
for(ct in unique(grid[, county])){
  g = grid[county == ct]
  
  fwrite(g, file.path(out, version, paste0('frankenpop_blk_', ct, '.gz')))
  
}
fwrite(grid, file.path(out, version, paste0('frankenpop_blk_', 'WA', '.gz')))
