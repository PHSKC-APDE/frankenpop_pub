library('data.table')
library('DBI')
library('rads')
library('glue')
library('sf')
library('spatagg')
library('tigris')
library('logger')
options(tigris_use_cache = TRUE)
version = 'v3'
dir2 = file.path('[OMITTED]/Frankenpop')
log_appender(appender_tee(file.path(dir2, version, 'additionalgeogs')))
b2z = readRDS('[OMITTED]/blk2zip.rds')

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
user = keyring::key_list('azure')[["username"]]
pass = keyring::key_get('azure', keyring::key_list('azure')[["username"]])

blk2sd = fread("[OMITTED]/Block20_SDUNI.csv")

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

log_info('Create block groups')
# create block groups
dbGetQuery(con,
           'drop table if exists ref.frankenpop_blkgrp;
            select * into ref.frankenpop_blkgrp
            from (
            	SELECT Hispanic, AgeGroup, Gender, RaceMars97, sum(Population) as Population, Year, CensusBlockGroupCode2020
            	FROM (
            		SELECT [Hispanic]
            			,[AgeGroup]
            			,[Gender]
            			,[RaceMars97]
            			,[Population]
            			,[Year]
            			,SUBSTRING(CensusBlockCode2020, 1, 12) AS CensusBlockGroupCode2020
            		FROM [ref].[frankenpop_blk]
            		) AS blkgrp
            		group by Hispanic, AgeGroup, Gender, RaceMars97, Year, CensusBlockGroupCode2020
            	  
             ) as bg')

# create school districts
log_info('Create school districts')

blk2sd[, CensusSchoolDistCode2020 := paste0(53, str_pad(SDUNI, 5, 'left', 0))]
blk2sd[, CensusBlockCode2020:=as.character(BLOCK20L)]
dbWriteTable(con, DBI::Id(schema = 'dcasey', table = 'blk2sd'), value = blk2sd[, .(CensusBlockCode2020, CensusSchoolDistCode2020)], overwrite = TRUE)

dbGetQuery(con,
           'drop table if exists ref.frankenpop_sdist;
            select * into ref.frankenpop_sdist
            from (
            	SELECT Hispanic, AgeGroup, Gender, RaceMars97, sum(Population) as Population, Year, CensusSchoolDistCode2020
            	FROM [ref].[frankenpop_blk] as blk
            	left join dcasey.blk2sd as sd on sd.CensusBlockCode2020 = blk.CensusBlockCode2020	
            	group by Hispanic, AgeGroup, Gender, RaceMars97, Year, CensusSchoolDistCode2020
             ) as schools')

# counties
log_info('Create counties')

dbGetQuery(con,
           'drop table if exists ref.frankenpop_county;
            select * into ref.frankenpop_county
            from (
            	SELECT Hispanic, AgeGroup, Gender, RaceMars97, sum(Population) as Population, Year, County
            	FROM (
            		SELECT [Hispanic]
            			,[AgeGroup]
            			,[Gender]
            			,[RaceMars97]
            			,[Population]
            			,[Year]
            			,SUBSTRING(CensusBlockCode2020, 1, 5) AS County
            		FROM [ref].[frankenpop_blk]
            		) AS blkgrp
            		group by Hispanic, AgeGroup, Gender, RaceMars97, Year, County
            	  
             ) as bg')

# legislative districts
log_info('Create leg dist')

blktoleg = fread("[OMITTED]/Block20LDist22.csv")
dbWriteTable(con, DBI::Id(schema = 'dcasey', table = 'blk2ld'), value = blktoleg[, .(CensusBlockCode2020= BLOCK20L, LEGDIST = LEGDIST22)], overwrite = TRUE)
dbGetQuery(con,
           'drop table if exists ref.frankenpop_ldist;
            select * into ref.frankenpop_ldist
            from (
            	SELECT Hispanic, AgeGroup, Gender, RaceMars97, sum(Population) as Population, Year, LEGDIST
            	FROM [ref].[frankenpop_blk] as blk
            	left join dcasey.blk2ld as ld on ld.CensusBlockCode2020 = blk.CensusBlockCode2020	
            	group by Hispanic, AgeGroup, Gender, RaceMars97, Year, LEGDIST
             ) as legdistz')

# KcCD
log_info('Create KCCD')
blktokccd = setDT(sf::st_read("[OMITTED]/Shapefiles/Political Districts/Districting_Plan_2021_Adopted_12082021.shp"))
dbWriteTable(con, DBI::Id(schema = 'dcasey', table = 'blk2kccd'), value = blktokccd[, .(CensusBlockCode2020= geoid20, KCCD = DM_PLAN, KCCD_old = CURR_DIST)], overwrite = TRUE)
dbGetQuery(con,
           'drop table if exists ref.frankenpop_kccd;
            select * into ref.frankenpop_kccd
            from (
            	SELECT Hispanic, AgeGroup, Gender, RaceMars97, sum(Population) as Population, Year, KCCD
            	FROM [ref].[frankenpop_blk] as blk
            	inner join dcasey.blk2kccd as kd on kd.CensusBlockCode2020 = blk.CensusBlockCode2020	
            	group by Hispanic, AgeGroup, Gender, RaceMars97, Year, KCCD
             ) as kcdistz')



# create ZIPs
# requires some stuff from OFM
# use an interim version
thetab = DBI::Id(schema = 'ref', table = 'frankenpop_zip')
dbGetQuery(con, glue_sql('drop table if exists {`thetab`}', .con = con))
dbGetQuery(con, glue_sql('create table {`thetab`}(
                          Hispanic int ,
                          AgeGroup varchar(7),
                          Gender varchar(1),
                          RaceMars97 int,
                          Population float,
                          Year int,
                          ZipCode2020 varchar(5))', .con = con))

for(yyy in 2000:2022){
  log_info('ZIP {yyy}')
  blk = dbGetQuery(con, glue_sql('select * from ref.frankenpop_blk where year = {yyy}', .con = con))
  setDT(blk)
  # merge on b2z
  blk = crosswalk(source = blk, source_id = 'CensusBlockCode2020',
                  est = 'Population', by = c('Hispanic', 'AgeGroup', 'Gender', "RaceMars97"),
                  xwalk_df = b2z, 
                  rescale = FALSE # any <1 coverage is due to small geometry errors
                  )
  setDT(blk)
  # blk[, target_id := as.integer(target_id)]
  setnames(blk, 'target_id', 'ZipCode2020')
  setnames(blk, 'est', 'Population')
  blk[, Population := round(Population, 15)]
  blk[, Year := yyy]
  setcolorder(blk, c('Hispanic', 'AgeGroup', 'Gender', "RaceMars97", 'Population', 'Year'))
  
  #fix the age group stuff
  blk[, AgeGroup := stringr::str_pad(AgeGroup, width = 3, side = 'left', pad = '0')]
  blk[AgeGroup == '100', AgeGroup := '100-104']
  blk[AgeGroup == '105', AgeGroup := '105-109']
  blk[AgeGroup == '110', AgeGroup := '110-UP']
  
  # save to disk
  fwrite(blk, file = file.path(dir2,version, 'todoh', paste0('ZipCode','_', yyy,'.csv.gz')))

  
  # save to DB
  # would probably be better with bcp
  # dbWriteTable(con, name = thetab, value = blk, append = TRUE)
  load_via_bcp(blk, thetab@name['table'],user = user, pass = pass)
  
}


# export stuff from various audiences
user = keyring::key_list('azure')[["username"]]
pass = keyring::key_get('azure', keyring::key_list('azure')[["username"]])
field_term = "-t ,"
row_term = paste0("-r \\n")
for(geog in c('blk', 'blkgrp', 'sdist')){
  dltab = paste0('frankenpop_', geog)
  dltabid = DBI::Id(schema = 'ref', table = dltab)
  colnamez = dbGetQuery(con, glue_sql('Select top(0) * from {`dltabid`}', .con = con))
  
  for(yyy in 2000:2022){
    log_info('{dltab} {yyy}')
    
    filepath = file.path(dir2,version, 'todoh', paste0(geog,'_', yyy,'.csv'))
    
    dbGetQuery(con, 'drop table if exists dcasey.holdfpop')
    dbGetQuery(con, glue::glue_sql('select * into dcasey.holdfpop from {`dltabid`} where year = {yyy}', .con= con))
    
    bcp_args = glue('hhs_analytics_workspace.dcasey.holdfpop out "{filepath}"',
                    ' -b 100000 -G -U {user} -S HHSAW -P {pass} -D -c ',
                    '{field_term} {row_term} ')
    
    
    # Load
    system2(command = "bcp", args = c(bcp_args),stdout = FALSE)
    dbGetQuery(con, 'drop table if exists dcasey.holdfpop')
    
    #save as gz
    r = fread(filepath)
    setnames(r, names(colnamez))
    
    # organize column order
    setcolorder(r, c('Hispanic', 'AgeGroup', 'Gender', "RaceMars97", 'Population', 'Year'))
    
    if(geog == 'blk') setcolorder(r, 'CensusBlockCode2020')
    
    #fix the age group stuff
    r[, AgeGroup := stringr::str_pad(AgeGroup, width = 3, side = 'left', pad = '0')]
    r[AgeGroup == '100', AgeGroup := '100-104']
    r[AgeGroup == '105', AgeGroup := '105-109']
    r[AgeGroup == '110', AgeGroup := '110-UP']
    
    fwrite(r, paste0(filepath, '.gz'))
    
  }
  
}

