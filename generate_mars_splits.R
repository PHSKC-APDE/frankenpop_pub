# Idea: compare 2010 PL redistricting data with the results of the MARS algorithm.
# see if its possible to infer how they were distributed.
library('data.table')
library('censusapi')

# 2010 MARS
mars = fread("C:/Users/dcasey/OneDrive - King County/frankenpop/2010/stco-mr2010_mt_wy.csv")

# Get the 2010 PL data from the census
# all age pop by hispanic with other category P002001
# age 18+ pop by hispanic with other category P004001
# plmeta = listCensusMetadata('dec/pl',2010)
v = c(paste0('P00', 2001:2011), #all age
      paste0('P00', 4001:4011), #18+
      'COUNTY', 'TRACT', 'BLKGRP', 'BLOCK')
pl = getCensus('dec/pl',vars = v, vintage = 2010,
              region = "county:*", regionin = "state:53" )
setDT(pl)
setnames(pl, paste0('P00', 2001:2011), c('total', 'hispanic', 'nothispanic', 'onerace', 'white', 'black', 'aian', 'asian', 'nhpi', 'other', 'multiple'))
setnames(pl, paste0('P00', 4001:4011), c('total_18', 'hispanic_18', 'nothispanic_18', 'onerace_18', 'white_18', 'black_18', 'aian_18', 'asian_18', 'nhpi_18', 'other_18', 'multiple_18'))

# convert to numeric
vvv = c('total', 'hispanic', 'white', 'black', 'aian', 'asian', 'nhpi', 'other', 'multiple')
vvv18 = paste0(vvv, '_18')
pl[, (vvv) := lapply(.SD, as.numeric), .SDcols = vvv]
pl[, (vvv18) := lapply(.SD, as.numeric), .SDcols = vvv18]
pl = melt(pl[, .SD, .SDcols = c('county', vvv)], id.vars ='county' )
pl = pl[variable != 'total']
pl[, county := as.numeric(county)]

# Prep the MARS data
mars[IMPRACE>=6, IMPRACE := 6]
mars[, variable := factor(IMPRACE, 1:6, c('white', 'black', 'aian', 'asian', 'nhpi', 'multiple'))]
mars[ORIGIN == 2, variable := 'hispanic']
mars = mars[STATE == 53, .(marspop = sum(RESPOP)), .(county = COUNTY, variable)]
mars[, county := as.numeric(county)]

# combine them
combo = merge(pl[variable != 'other'], mars, by = c('county', 'variable'), all.x =T)
combo[is.na(marspop), marspop := 0]
combo[, dif := marspop - value]

#compute the relative fraction of the multiple category decrease
multi = combo[variable == 'multiple',]
multi[, rat_chg := marspop/value]

combo = combo[variable != 'multiple']
combo[, frac := dif/sum(dif), county]

saveRDS(combo, 'C:/Users/dcasey/OneDrive - King County/frankenpop/othersplit.rds')
saveRDS(multi, 'C:/Users/dcasey/OneDrive - King County/frankenpop/multi_adj.rds')
