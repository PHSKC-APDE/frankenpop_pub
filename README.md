
# Frankenpop

## About

This project combines 2010 census block X race/eth X gender x age
population estimates from OFM’s SADE program with Census 2020 PL 94-171
redistricting data to create population estimates by 2020 census block X
race/eth X gender X age for Washington state while OFM is able to adapt
their process to utilize Census 2020 results more extensively.

This project/analysis was designed and implemented by Daniel Casey at
PHSKC-APDE.

## Inputs

### [OFM SADE Population Estimates](https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/estimates-april-1-population-age-sex-race-and-hispanic-origin)

2020 population estimates for Washington state for 2010 census block X
race/eth X gender X age.

### [Census 2020 PL 94-171](https://www.census.gov/data/datasets/2020/dec/2020-census-redistricting-summary-file-dataset.html)

Population results for Washington state for 2020 census block X race/eth
X age group (over/under 18).

### [Census 2020 block relationship file](https://www.census.gov/geographies/reference-files/time-series/geo/relationship-files.html#t10t20)

Calculation of geographic relationship between 2010 census blocks and
2020 census blocks

### [Census 2010 Pl 94-171](https://www.census.gov/data/datasets/2010/dec/redistricting-file-pl-94-171.html)

Population results for 2010 County X race/eth. Finer details are
available, but not used in Frankenpop.

### [Census 2010 MARS population estimates](https://www.census.gov/programs-surveys/popest/technical-documentation/research/modified-race-data.html)

Population results for 2010 County X race/eth. Similar to the Pl 94-171
data, but with the “other” race/eth category redistributed to the main
OMB race/eth categories.

### [2020 and 2021 OFM County X Age X Sex Population Estimates](https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/estimates-april-1-population-age-sex-race-and-hispanic-origin)

Population results from OFM based off of Census 2020 for each county by
5ish year age groups and sex. These estimates potentially feature
additional bits of adjustment (relative to the Census 2020 results) and
improvement– beyond the additional age fidelity.

### [2020 and 2021 OFM County X Race/Eth Estimates](https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/estimates-april-1-population-age-sex-race-and-hispanic-origin)

Population results from OFM based off of Census 2020 for each county by
the 7 main OMB race/ethnicity groups. These estimates are corrected to
remove the “other” race category and potentially feature additional bits
of adjustment (relative to the Census 2020 results) and improvement.

## Process

### 1. Compile 2020 PL 94-171 data

[pl_all_4\_2020_dar.R](pl_all_4_2020_dar.R) is a modified version of a
Census prepared R script that loads, standardizes, and cleans Census
2020 Pl 94-171 data products. Specifically, this script creates a
dataset that provides geography X race/eth X age group (over/under 18)
population counts for the main race/eth categories used by APDE/OFM–
AIAN, NHPI, White, Hispanic, Black, Asian, Multiple. The process also
carries forward the “other” race/eth category to be redistributed later.
The population counts for each race/eth group are mutually exclusive,
and as such, Hispanic is considered as a race (that is, all other races
are not hispanic).

### 2. Generate MARS splits from 2010 data

Pl 94-171 data products include an “other” race/eth category that
doesn’t translate well to the standard OMB set of race/eth categories.
The MARS approach uses a multiple stage algorithm to redistribute the
“other” population to the more sensible race/eth categories. The 2020
MARS estimates have not been released, as such, Frankenpop, via
[generate_mars_splits.R](generate_mars_splits.R), derives adjustment
scalars by comparing the 2010 MARS data with the 2010 Pl 94-171 data at
the county level.

The scalars are race/eth X county specific and generally serve as an
inflationary factor to scale up a given race/eth category to account for
the counts originally in the “other” category that get reassigned to the
target category. For the “multiple race” category, the scalar is usually
deflationary– in effect, adding more population to the “other” category
to be reassigned.

Census 2020 race/ethnicity ascertainment meaningfully changed relative
to Census 2010 as did (at least via ancedote) cultural awareness of
multi-race individual, and the effect of these factors on the validity
on carrying forward the MARS assignments from 2010 is unknown, However,
it is still probably better to use the 2010 scalars rather than other
assignment approaches (e.g. relative to category size).

Note: This method could probably be improved by taking into account the
age categories MARS reports as well as aging folks through. Maybe fit a
model to impute the people who have been born since the last census.
Compare reassignment percentages by age group

### 3. Create Frankenpop

#### Convert from 2010 blocks to 2020 blocks

OFM SADE population estimates for 2020 use geographies from the 2010
census while the Census 2020 PL 94-171 use 2020 census geographies. The
block relationship file computed by the Census provides details on how
2010 blocks intersect with the 2020 blocks. The conversion from
population situated in 2010 blocks to 2020 blocks is determined by:

$$
Population\ of\ 2020\ block = 
\sum^n_{i=1} intersection\ proportion_i \times population_i
$$

Where $i$ indexes a specific 2010 - 2020 block overlap and $n$
represents the universe of 2010 blocks that intersect with a given 2020
block.

Land area intersection is used when available with water area
intersection as a fallback. The existence of population counts within
blocks that are entirely water is a little mystifying to me, but I
imagine it largely deals with houseboats and/or weirdness from the
Census’ disclosure avoidance algorithm.

The conversion of population from 2010 to 2020 blocks in not necessarily
lossless, but because a future step rakes these intermediate steps to
the 2020 PL 94-171 results, no effort is made to ensure no loss in
population (since the goal is relative population distribution).

#### Apply MARS scalars

The previously calculated county-specific 2010 MARS scalars are applied
to the 2020 PL 94-171 results to redistribute the “other” race/eth
population to the remaining race/eth categories via
$adjusted\ population_{b,r,a} = pop\ to\ redistribute_b \times scalar_r$
where $b$ is the block, $r$ is the race/eth category, and $a$ is the age
group.

No block level information besides the number of people to redistribute
is used in the calculation. As such, race/eth X age group combinations
within a block that did not exist prior to the redistribution may be
created. This is most notable in small population blocks where the
entire population is reported as “other.”

#### Rake OFM estimates to Census 2020 results (e.g. Frankenpop)

With the OFM estimates transferred to 2020 geographies and the Census
data adjusted to redistribute the “other” race/eth category to the
remaining groups, the single year age X gender from OFM is applied to
the broad age group X race/ethnicity X census block pattern from the
Census data.

The raking of OFM data to Census marginals is conducted iteratively up
the geographic hierarchy from census block, to census tract, to county
and finally to the state. Tract and larger level patterns are used when
the Census data suggests the presence of given race/eth X age group but
the OFM data does not have any corresponding age X gender results for
the given race/eth X age group.

#### Rake to County level OFM estimates

Once the age/sex patterns from OFM’s SADE estimates have been raked to
match (as best as possible) the 2020 Census results, these results are
[multidimensionally raked](rake_and_output.R) to match the Age X Sex X
County and Race/Eth X County estimates. The raking is further stratified
by year and year Y+1 is dependent on the results from year Y (e.g. 2021
starts with the 2020 raked results). However, I’m not actually sure that
dependency is necessary (although it doesn’t really hurt anything) since
the within group patterns being raked to the targets are stable by
year.

## Output

Population estimates for every 2020 census block X single year age X
gender X race/eth in Washington state for 2020 and 2021. OFM data
provides the block level age/sex pattern as well as County level age,
sex, and race/eth controls while the geographic patterns (most notably
race/eth) derive from Census 2020 PL 94-171 results.

The output datasets are unique by Census block, race/eth, gender, and
age.

| Column Name | Description                                                                                                                                             |
|-------------|---------------------------------------------------------------------------------------------------------------------------------------------------------|
| geo_id20    | FIPS code for the census block                                                                                                                          |
| race_eth    | Race/ethnicity in 7 groups. Hispanic is treated as a race and therefore all other groups should be considered “non-Hispanic”                            |
| gender      | Gender/sex at birth. Defer to OFM’s description/depiction of sex/gender for the correct interpretation.                                                 |
| age         | Single year age                                                                                                                                         |
| county      | FIPS code for county                                                                                                                                    |
| tract       | FIPS code for tract                                                                                                                                     |
| ofmpop20    | Population from OFM for 2020 (based on SADE estimates using 2010 census results)                                                                        |
| fpop20      | Frankenpop estimates where ofmpop20 is raked to Census 2020 data.                                                                                       |
| rpop2020    | Raked Frankenpop estimates to match updated County X age X sex and race/eth X County breakdowns provided by OFM. Use this column as population for 2020 |
| rpop2021    | Raked Frankenpop estimates for 2021 using the same method as rpop2020 (just a different year).                                                          |
