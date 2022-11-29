# This script is largely borrowed from the Census
library('data.table')

out = '[OMITTED]/frankenpop'
colnames = read.csv(file.path(out, 'wa2020.pl', 'colnames.csv'), header = FALSE)
setDT(colnames)


# -----------------------------
# Specify location of the files
# -----------------------------
header_file_path <- "[OMITTED]/frankenpop/wa2020.pl/wageo2020.pl"
part1_file_path  <- "[OMITTED]/frankenpop/wa2020.pl/wa000012020.pl"
part2_file_path  <- "[OMITTED]/frankenpop/wa2020.pl/wa000022020.pl"
part3_file_path  <- "[OMITTED]/frankenpop/wa2020.pl/wa000032020.pl"

# -----------------------------
# Import the data
# -----------------------------
header <- read.delim(header_file_path, header=FALSE, colClasses="character", sep="|")
part1  <- read.delim(part1_file_path,  header=FALSE, colClasses="character", sep="|")
part2  <- read.delim(part2_file_path,  header=FALSE, colClasses="character", sep="|")
part3  <- read.delim(part3_file_path,  header=FALSE, colClasses="character", sep="|")

# address the column names

colnames[, varname := substr(V1, 1, nchar('P0040070'))]
# take out some of the intermediate stuff
colnames[, group := trimws(substr(V1, nchar('P0040070')+1, nchar(V1)))]
colnames[substr(group,1,2) %in% c('P3', 'P4'), group := trimws(substr(group, 6, nchar(group)))]
colnames[substr(group,1,1) %in% c(':'), group := trimws(substr(group, 2, nchar(group)))]

# add eth and age flags
colnames[, hispanic := as.numeric(substr(varname,1,4) %in% c('P001', 'P003'))]
colnames[, age_grp:= factor(substr(varname,1,4) %in% c('P003', 'P004'), c(T,F), c('18', 'All'))]

# race flags
rgs = data.table(race = c('White', 'Black', "AIAN", 'Asian', 'NHPI', 'Other'),
                 census_race = c('White', 'Black or African American', 'American Indian and Alaska Native',
                                 'Asian', 'Native Hawaiian and Other Pacific Islander', 'Some Other Race'))

for(rrr in seq_len(nrow(rgs))){
  colnames[, (rgs[rrr, race]) := as.numeric(grepl(tolower(rgs[rrr, census_race]), tolower(group), fixed = TRUE))]
}

#keep only the columns that provide some information
colnames[, val := rowSums(.SD), .SDcols = c(rgs[, race])]
colnames = colnames[val >0][, val := NULL]
colnames[, V1 := NULL]
# -----------------------------
colnames(header) <- c("FILEID", "STUSAB", "SUMLEV", "GEOVAR", "GEOCOMP", "CHARITER", "CIFSN", "LOGRECNO", "GEOID", 
  "GEOCODE", "REGION", "DIVISION", "STATE", "STATENS", "COUNTY", "COUNTYCC", "COUNTYNS", "COUSUB",
  "COUSUBCC", "COUSUBNS", "SUBMCD", "SUBMCDCC", "SUBMCDNS", "ESTATE", "ESTATECC", "ESTATENS", 
  "CONCIT", "CONCITCC", "CONCITNS", "PLACE", "PLACECC", "PLACENS", "TRACT", "BLKGRP", "BLOCK", 
  "AIANHH", "AIHHTLI", "AIANHHFP", "AIANHHCC", "AIANHHNS", "AITS", "AITSFP", "AITSCC", "AITSNS",
  "TTRACT", "TBLKGRP", "ANRC", "ANRCCC", "ANRCNS", "CBSA", "MEMI", "CSA", "METDIV", "NECTA",
  "NMEMI", "CNECTA", "NECTADIV", "CBSAPCI", "NECTAPCI", "UA", "UATYPE", "UR", "CD116", "CD118",
  "CD119", "CD120", "CD121", "SLDU18", "SLDU22", "SLDU24", "SLDU26", "SLDU28", "SLDL18", "SLDL22",
  "SLDL24", "SLDL26", "SLDL28", "VTD", "VTDI", "ZCTA", "SDELM", "SDSEC", "SDUNI", "PUMA", "AREALAND",
  "AREAWATR", "BASENAME", "NAME", "FUNCSTAT", "GCUNI", "POP100", "HU100", "INTPTLAT", "INTPTLON", 
  "LSADC", "PARTFLAG", "UGA")
colnames(part1) <- c("FILEID", "STUSAB", "CHARITER", "CIFSN", "LOGRECNO", 
                     paste0("P00", c(10001:10071, 20001:20073)))
colnames(part2) <- c("FILEID", "STUSAB", "CHARITER", "CIFSN", "LOGRECNO", 
                     paste0("P00", c(30001:30071, 40001:40073)), 
                     paste0("H00", 10001:10003))
colnames(part3) <- c("FILEID", "STUSAB", "CHARITER", "CIFSN", "LOGRECNO",
                     paste0("P00", 50001:50010))

# -----------------------------
# Merge the data
# -----------------------------
combine <- Reduce(function(x,y) {merge(x, y, by=c("LOGRECNO", "STUSAB", "FILEID", "CHARITER"))}, list(header[,-7], part1[,-4], part2[,-4], part3))

# -----------------------------
# Order the data
# -----------------------------
combine <- combine[order(combine$LOGRECNO), c("FILEID", "STUSAB", "SUMLEV", "GEOVAR", "GEOCOMP", "CHARITER", "CIFSN", "LOGRECNO", "GEOID", 
                                              "GEOCODE", "REGION", "DIVISION", "STATE", "STATENS", "COUNTY", "COUNTYCC", "COUNTYNS", "COUSUB",
                                              "COUSUBCC", "COUSUBNS", "SUBMCD", "SUBMCDCC", "SUBMCDNS", "ESTATE", "ESTATECC", "ESTATENS", 
                                              "CONCIT", "CONCITCC", "CONCITNS", "PLACE", "PLACECC", "PLACENS", "TRACT", "BLKGRP", "BLOCK", 
                                              "AIANHH", "AIHHTLI", "AIANHHFP", "AIANHHCC", "AIANHHNS", "AITS", "AITSFP", "AITSCC", "AITSNS",
                                              "TTRACT", "TBLKGRP", "ANRC", "ANRCCC", "ANRCNS", "CBSA", "MEMI", "CSA", "METDIV", "NECTA",
                                              "NMEMI", "CNECTA", "NECTADIV", "CBSAPCI", "NECTAPCI", "UA", "UATYPE", "UR", "CD116", "CD118",
                                              "CD119", "CD120", "CD121", "SLDU18", "SLDU22", "SLDU24", "SLDU26", "SLDU28", "SLDL18", "SLDL22",
                                              "SLDL24", "SLDL26", "SLDL28", "VTD", "VTDI", "ZCTA", "SDELM", "SDSEC", "SDUNI", "PUMA", "AREALAND",
                                              "AREAWATR", "BASENAME", "NAME", "FUNCSTAT", "GCUNI", "POP100", "HU100", "INTPTLAT", "INTPTLON", 
                                              "LSADC", "PARTFLAG", "UGA", paste0("P00", c(10001:10071, 20001:20073)), paste0("P00", c(30001:30071, 40001:40073)), 
                                              paste0("H00", 10001:10003), paste0("P00", 50001:50010))]
rownames(combine) <- 1:nrow(combine)
setDT(combine)

wapop = combine[STATE == 53]

# keep only block level population
blkpop = wapop[SUMLEV == '750']
blkpop = melt(blkpop, id.vars = names(header))
blkpop = merge(blkpop, colnames, by.x = 'variable', by.y = 'varname')

# subset columns
# note: At this stage hispanic = 1 means the value includes hispanics, but is not "all" hispanics
blkpop = blkpop[, .(GEOID, variable, pop = as.numeric(value), age_grp, White, Black, AIAN, Asian, NHPI, Other, Hispanic = hispanic)]

# compute NH race groups
blkpop = merge(blkpop[Hispanic == 0, .SD, .SDcols = c('GEOID', 'age_grp', rgs[, race], 'pop')],
               blkpop[Hispanic == 1, .SD, .SDcols = c('GEOID', 'age_grp', rgs[, race], 'pop')],
               all = T, by = c('GEOID', 'age_grp', rgs[,race]))

stopifnot(all(blkpop[, pop.y>=pop.x]))

setnames(blkpop, c('pop.x', 'pop.y'), c('nh', 'all'))
blkpop[, his := all - nh]
blkpop[, all := NULL]
blkpop = melt(blkpop, c('GEOID', 'age_grp', rgs[, race]))
blkpop[, Hispanic := as.numeric(variable == 'his')] # now its mutually exclusive
blkpop[, variable := NULL]
setnames(blkpop, 'value', 'pop')

# compute over/under 18
blkpop = merge(blkpop[age_grp == 'All', .SD, .SDcols = c('GEOID', rgs[, race], 'Hispanic', 'pop')],
               blkpop[age_grp == '18', .SD, .SDcols = c('GEOID', rgs[, race], 'Hispanic', 'pop')],
               all = T,
               by = c('GEOID', rgs[, race], 'Hispanic'))
stopifnot(all(blkpop[, pop.y<=pop.x]))
setnames(blkpop, c('pop.x', 'pop.y'), c('all', '18'))
blkpop[, lte17 := all - `18`]
blkpop[, all := NULL]
blkpop = melt(blkpop, c('GEOID', rgs[, race], 'Hispanic'), value.name = 'pop', variable.name = 'age_grp', variable.factor = FALSE)


# save
saveRDS(blkpop, file.path(out, 'blk_2020_census.rds'))

