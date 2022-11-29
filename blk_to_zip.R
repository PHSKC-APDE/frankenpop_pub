library('sf')
library('tigris')
library('spatagg') # an APDE package
library('future')
library('future.apply')
library('data.table')
options(tigris_use_cache = TRUE)
nwork = 4

wa = st_read("[OMITTED]/WA_State_Boundary/WA_State_Boundary.shp")

zip = st_read("[OMITTED]")
ctys = tigris::counties('WA')
blk = tigris::blocks(state = 'WA')
# waparcel = st_read("C:/Users/dcasey/OneDrive - King County/Downloads/Current_Parcels.geojson")
blk = st_transform(blk, st_crs(zip))
ctys = st_transform(ctys, st_crs(zip))

# split zip into bits
zip = split(zip, ceiling(seq_len(nrow(zip)) / (nrow(zip)/nwork)))

plan(strategy = multisession, workers = nwork)
blk_2_zip = future_lapply(zip, function(z){
  z = split(z, z$POSTCODE)
  res = lapply(z, function(x){
    print(x$POSTCODE)
    # find the counties that a ZIP intersects with
    cty_zip = ctys[st_intersects(ctys, x, sparse = FALSE)[,1], ]
    src = subset(blk, COUNTYFP20 %in% cty_zip$COUNTYFP)
    src = src[st_intersects(src, x, sparse = FALSE)[,1],]
    r = spatagg::create_xwalk(source = src, source_id = 'GEOID20', target = x, target_id = 'POSTCODE', min_overlap = .001)

    
  })
  rbindlist(res)
  
})
blk_2_zip = rbindlist(blk_2_zip)
saveRDS(blk_2_zip, '[OMITTED]/blk2zip.rds')

