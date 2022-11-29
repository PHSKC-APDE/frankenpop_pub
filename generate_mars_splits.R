# Idea: compare 2010 PL redistricting data with the results of the MARS algorithm.
# see if its possible to infer how they were distributed.
library('data.table')
library('censusapi')

# 2010 MARS
mars = fread("[OMITTED]/frankenpop/2010/stco-mr2010_mt_wy.csv")
mrace = fread("[OMITTED]/frankenpop/2010/mars_race_cats.csv")

# Get the 2010 PL data from the census
# all age pop by hispanic with other category P002001
# age 18+ pop by hispanic with other category P004001
plmeta = listCensusMetadata('dec/pl',2010)

# find the columns that have relevant data
rgs = data.table(race = c('White', 'Black', "AIAN", 'Asian', 'NHPI', 'Other'),
                 census_race = c('White', 'Black or African American', 'American Indian and Alaska Native',
                                 'Asian', 'Native Hawaiian and Other Pacific Islander', 'Some Other Race'))
setDT(plmeta)
plmeta[, keep := 0]

for(r in rgs[, census_race]){
  plmeta[grepl(tolower(r), tolower(label)), keep := 1]
  plmeta[, (rgs[census_race == r, race]) := as.numeric(grepl(tolower(r), tolower(label)))]
  mrace[, (rgs[census_race == r, race]) := as.numeric(grepl(tolower(r), tolower(census_race)))]
}
plmeta = plmeta[keep == TRUE, ]
v = plmeta[, name]

# v = c(paste0('P00', 2001:2011), #all age
#       paste0('P00', 4001:4011), #18+
#       'COUNTY', 'TRACT', 'BLKGRP', 'BLOCK')
pl = getCensus('dec/pl',vars = v, vintage = 2010,
              region = "county:*", regionin = "state:53")
setDT(pl)


pl = melt(pl, id.vars = c('state', 'county'), variable.name = 'name', value.name = 'pop')

pl = merge(pl, plmeta[, .SD, .SDcols = c('name', rgs[, race])], all.x = T, by = 'name')

pl[, h := as.numeric(substr(name, 1,4) %in% c('P001', 'P003'))]
pl[, aa := as.numeric(!substr(name, 1,4) %in% c('P004', 'P003'))]
pl[, name := NULL]

# separate out Hispanic and Non hispanic
pl = dcast(pl, state + county + White + Black + AIAN + Asian + NHPI + Other + aa ~ h, value.var = 'pop')
pl[, h := `1`-`0`]
setnames(pl, '0', 'nh')
pl[, `1` := NULL]
pl = melt(pl, id.vars = c('state', 'county', rgs[, race], 'aa'), variable.name = 'Hispanic', value.name = 'pop')
pl[, Hispanic := as.numeric(Hispanic == 'h')]

# separate out over/under 18
pl = dcast(pl, state + county + White + Black + AIAN + Asian + NHPI + Other + Hispanic ~ aa, value.var = 'pop')
pl[, lte17 := `1` - `0`]
setnames(pl, '0', '18')
pl[, `1` := NULL]
pl = melt(pl, id.vars = c('state', 'county', rgs[, race], 'Hispanic'), variable.name = 'age_grp', value.name = 'pop', variable.factor = FALSE)
pl[, county := as.numeric(county)]

# Prep the MARS data
mars = merge(mars[STATE == 53], mrace, all.x = TRUE, by.x = 'IMPRACE', by.y = 'id')
mars[, census_race := NULL]
mars[, Hispanic := as.numeric(ORIGIN == 2)]
mars[AGEGRP>=5, age_grp := '18']
mars[is.na(age_grp), age_grp := 'lte17']
mars = mars[, .(marspop = sum(RESPOP)), .(county = COUNTY, age_grp, White, Black, AIAN, Asian, NHPI, Other, Hispanic)]
mars[, county := as.numeric(county)]
mars[, Other := NULL]

# combine them
combo = merge(pl[Other == 0], mars, by = c('county', 'age_grp', setdiff(rgs[,race], 'Other'), 'Hispanic'), all.x =T)
combo[is.na(marspop), marspop := 0]
combo[, singlerace := rowSums(.SD)==1, .SDcols = c('White', 'Black', 'AIAN', 'Asian', 'NHPI')]
combo[, dif := marspop - pop]
combo[, marsadj := marspop/pop] # relatively how pop changed after mars
combo[is.na(marsadj), marsadj := 1] # when marspop/pop is 0/0
combo[marsadj == Inf, marsadj := 1] # when marspop >0 and pop is 0. Not ideal, but should be a small enough number. And also get fixed during raking

# There needs to be a way to allocate counts since the mars reassignment doesn't always work
# some single race groups get dropped
# maybe split between combos that gain and those that lose
# or return to the strategy that splits Others and Multi
# try a model that predicts the relative adjustment based on group characteristics

# do some cleaning up of combo
raceeths = c('White', 'Black', 'AIAN', 'Asian', 'NHPI', 'Hispanic')
cmod = copy(combo)
cmod[, marsadj := marspop/pop] # relatively how pop changed after mars
cmod[is.na(marsadj), marsadj := 1] # when marspop/pop is 0/0
cmod = cmod[marsadj != Inf]
cmod[, c('state', 'Other', 'marspop', 'singlerace') := NULL]
cmod[, county := as.factor(county)]
cmod[, age_grp := as.factor(age_grp)]

saveRDS(cmod, '[OMITTED]/frankenpop/mars_adjustment.rds')


