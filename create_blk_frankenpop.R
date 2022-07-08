library('data.table')
library('rads')
library('stringr')
library('DBI')
library('sf')
out = 'C:/Users/dcasey/OneDrive - King County/frankenpop'
redist = readRDS(file.path(out, '2020_redist_pop.rds'))
fracs = fread(file.path(out, "tab2010_tab2020_st53_wa.txt"))
othersplit = readRDS('C:/Users/dcasey/OneDrive - King County/frankenpop/othersplit.rds')
multi = readRDS('C:/Users/dcasey/OneDrive - King County/frankenpop/multi_adj.rds')
# pop_kc = rads::get_population(geo_type = 'blk', group_by = c('race_eth', 'ages', 'genders'), round = FALSE)



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

# Fetch blk x gender x single year age x race/eth population and standardize the columns
pop = dbGetQuery(con, 'Select * from ref.pop_blk')
setDT(pop)
pop[, gender := factor(gender, levels = c(2, 1), labels = c("Female", "Male"))]

ref.table <- data.table::copy(rads.data::population_wapop_codebook_values)
ref.table <- ref.table[varname %in% c("r1r3", "r2r4")]
ref.table[varname == "r1r3", name := "race"]
ref.table[varname == "r2r4", name := "race_eth"]
ref.table <- ref.table[, .(name, r_type = varname, value = code, label, short)]

pop = merge(pop, ref.table[r_type == 'r2r4', .(value = as.integer(value), label, short)], by.x = 'r2r4', by.y = 'value', all.x = T)
setnames(pop, 'label', 'race_eth')
pop = pop[, .SD, .SDcols = c("pop", "geo_type", "geo_id", "year", "age", "gender", "race_eth")]

# Clean up the redistricting data and melt it long
pc = c('hispanic', 'white', 'black', 'aian', 'asian', 'nhpi', 'other', 'multiple')
pc18 = paste0(pc, '_18')
idz = c('COUNTY', 'SUMLEV', 'TRACT', 'BLKGRP', 'BLOCK', 'level')
redist = redist[level == 'block', .SD, .SDcols = c(pc, pc18, idz)]
redist[, paste0(pc, '_lte17') := lapply(pc, function(x) get(x) - get(paste0(x, '_18')))]

# Find the fraction of pop that is "other"
other = copy(redist)[, total := rowSums(.SD), .SDcols = pc]
other[, frac_other := other/total]

# clean up and reshape redist
redist = redist[, (pc) := NULL]
redist = melt(redist[SUMLEV == 750], id.vars = idz)
redist = redist[, c('raceeth', 'age_grp') := tstrsplit(variable, split = '_')]

# scale down the "multiple" race/eth category per 2010 MARS
multi[, county := stringr::str_pad(county, width = 3, pad = '0')]
redist = merge(redist, multi[, .(COUNTY = county, rat_chg)], all.x = T, by = 'COUNTY')
redist[, og := value]
redist[raceeth == 'multiple', value := rat_chg * value]
redist[, dif := og - value]

# redistribute the `other` category (and the multiple category) proportional to how MARS does it in 2010 (approx)
reother = redist[raceeth %in% c('multiple', 'other')]
reother[raceeth == 'multiple', value := dif]
bys = c(idz, 'other', 'age_grp')
reother = reother[, .(value  = sum(value)), by = intersect(bys, names(reother))]
setnames(othersplit, 'variable', 'raceeth')
othersplit[, COUNTY := str_pad(county, 3, 'left', '0')]
setnames(reother, 'value', 'other')

reother = merge(reother[, .SD, .SDcols = c(idz, 'other', 'age_grp')], 
                othersplit[,.(COUNTY, raceeth, frac)], 
                all.x = T, by = c('COUNTY'), allow.cartesian = TRUE)

st = redist[, sum(og)]
redist = redist[raceeth != 'other']
redist = merge(redist, reother[, .SD, .SDcols = c(idz, 'age_grp', 'other', 'frac', 'raceeth')], 
               all.x = T, by = c(idz, 'age_grp', 'raceeth'))
redist[raceeth == 'multiple', frac := 0]
redist[raceeth == 'multiple', other := 0]

# rescale the fraction to account for instances where a race group doesn't exist
redist[, scalar := frac/sum(frac), by = c(idz, 'age_grp')]

# compute the population adjusted for reassignment of the "other" race/eth category
redist[, pop := value + (other * scalar)]
end = sum(redist[, pop])

# add race categories from pop
re = data.table(race_eth = c("White", "Black", "AIAN", "Asian", "NHPI", "Multiple race", "Hispanic"),
                raceeth = c( "white", "black", "aian", "asian", "nhpi", "multiple", "hispanic"))

redist = merge(redist, re, all.x = T, by = 'raceeth')

# Make geoid
redist[, GEOID20 := paste0('53', COUNTY, TRACT,BLOCK)]

# make age group for pop
pop[, age_grp := as.character(factor(age<=17, c(T,F), c('lte17', '18')))]

# make fractions for the blocks
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
b20 = merge(fracs, pop, all.x = T, by = 'geo_id', allow.cartesian = TRUE)

# compute 2020 block level OFM population numbers from 2010 block definitions
b20 = b20[, 
          .(pop = sum(pop * frac10, na.rm = T)), # a 2010 block contributes pop * fraction overlap with the 2020 block to that block
          by = c('geo_id20', 'age', 'gender', 'race_eth', 'age_grp')]

# Make a full grid of results
grid = CJ(geo_id20 = unique(redist$GEOID20),
          age = pop[, unique(age)],
          gender = pop[, unique(gender)],
          race_eth = pop[, unique(race_eth)])
grid = na.omit(grid)

grid[, age_grp := as.character(factor(age<=17, c(T,F), c('lte17', '18')))]
grid = merge(grid, b20, all.x = T, by = names(grid))

rm(b20);

# for each blk X age_grp X race_eth combo, compute total pop and the relative fraction
grid[is.na(pop), pop := 0]
grid[, pop_age_grp := sum(pop, na.rm = T), by = .(geo_id20, race_eth, age_grp)]
grid[, popfrac_ag := pop/pop_age_grp]
grid[is.na(popfrac_ag), popfrac_ag := 0]

# merge on districting results
grid = merge(grid, redist[, .(geo_id20 = GEOID20, race_eth, age_grp, cpop = pop)], all.x = T, by = c('geo_id20', 'race_eth', 'age_grp'))

# To save space, drop places where there is no pop
grid = grid[!is.na(cpop), ]
grid = grid[cpop>0]

# for block X age_grp X race_eth combos that have pop in the redistricting data, but not OFM, use the tract pattern
grid[, tract := substr(geo_id20, 1, nchar(geo_id20) - 4)]
tractpat = grid[, .(pop = sum(pop)), .(tract, race_eth, gender, age, age_grp)]
tractpat[, pop_age_grp_trt := sum(pop, na.rm = T), by = .(tract, race_eth, age_grp)]
tractpat[, popfrac_ag_trt := pop/pop_age_grp_trt]
setnames(tractpat, 'pop', 'pop_trt')
tractpat[, age_grp := NULL]

# make a county pattern just in case
grid[, county := substr(geo_id20,1,5)]
ctypat = grid[, .(pop = sum(pop)), .(county, race_eth, gender, age, age_grp)]
ctypat[, pop_age_grp_cty := sum(pop, na.rm = T), by = .(county, race_eth, age_grp)]
ctypat[, popfrac_ag_cty := pop/pop_age_grp_cty]
setnames(ctypat, 'pop', 'pop_cty')
ctypat[, age_grp := NULL]

# A few counties might not have a given race/age combo. Use state pattern instead
stpat = grid[, .(pop = sum(pop)), .(race_eth, gender, age, age_grp)]
stpat[, pop_age_grp_st := sum(pop, na.rm = T), by = .(race_eth, age_grp)]
stpat[, popfrac_ag_st := pop/pop_age_grp_st]
setnames(stpat, 'pop', 'pop_st')
stpat[, age_grp := NULL]

# add the patterns to the grid
grid = merge(grid, tractpat, all.x = TRUE, by = c('tract', 'gender', 'age', 'race_eth'))
grid = merge(grid, ctypat, all.x = TRUE, by = c('county', 'gender', 'age', 'race_eth'))
grid = merge(grid, stpat, all.x = TRUE, by = c('gender', 'age', 'race_eth'))

# clean up a bit
rm(ctypat); rm(tractpat);
rm(reother); rm(re);
rm(pop);
gc()

# compute the pops
grid[, fpop := cpop * popfrac_ag]
grid[cpop>0 & pop_age_grp == 0, fpop := cpop * popfrac_ag_trt]
grid[cpop>0 & pop_age_grp_trt == 0, fpop := cpop * popfrac_ag_cty]
grid[cpop>0 & pop_age_grp_cty == 0, fpop := cpop * popfrac_ag_st]

# compute leftovers by race_eth and age_grp
left = grid[, .(fpop = sum(fpop)), by = .(county, age_grp, race_eth)]
left = merge(left, redist[, .(tpop= sum(pop)), .(age_grp, race_eth, county = paste0('53', COUNTY))], all = T, by = c('county', 'age_grp', 'race_eth'))
left[, scalar := tpop/fpop]

# get the last few people squeezed out
grid = merge(grid, left[, .(county, age_grp, race_eth, scalar)], all.x = T, by = c('county', 'age_grp', 'race_eth'))
grid[, fpop := fpop * scalar]

# confirm it worked 
grid[, sum(fpop)] - redist[, sum(pop)]

# check the marginals
mrgn = grid[, .(fpop = sum(fpop)), by = c('age_grp', 'race_eth', 'geo_id20')]
mrgn = merge(redist[, .(geo_id20 = GEOID20, age_grp, race_eth, pop)], mrgn, all.x = T, by = c('age_grp', 'race_eth', 'geo_id20'))
mrgn[is.na(fpop), fpop := 0]

summary(mrgn[pop!=0, pop-fpop])

grid = grid[fpop>0]
grid[, sum(fpop)] - redist[, sum(pop)]
grid = grid[, .(county, tract, geo_id20, race_eth, gender, age, pop, fpop)]
saveRDS(grid, file.path(out, 'frankenblkpop_wa.rds'))


