# Rake things to race/eth and age/sex by county
# A one way raker
# borrow from https://github.com/ihmeuw/USHD/blob/life_expectancy_race_ethnicity_2022/sae.shared/R/rake.r
# This will modify by reference
rake <- function(data, value_var, agg_var, constant_vars, replace_value = F) {
  
  # sum over weighted mortality rates to get a crude total mx
  data[, sum_weighted_value := sum(get(value_var)), by = c(constant_vars)] #,agg_var
  
  # generate raking weights
  data[, raking_weight := get(agg_var) / sum_weighted_value]
  
  # if all counts are zero raking_weight will be NA. Convert to zeros.
  data[is.na(raking_weight), raking_weight := 0]
  
  # generate raked estimates by multiplying the original by the raking weights
  data[, raked_value := get(value_var) * raking_weight]
  
  if (nrow(data[is.na(raked_value)]) > 0) {
    print(head(data[is.na(raked_value)]))
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