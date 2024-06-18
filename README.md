
- <a href="#frankenpoppopulation-interim-estimates-pie"
  id="toc-frankenpoppopulation-interim-estimates-pie">Frankenpop/Population
  Interim Estimates (PIE)</a>
  - <a href="#about" id="toc-about">About</a>
    - <a href="#dimensions" id="toc-dimensions">Dimensions</a>
    - <a href="#about-using-pie" id="toc-about-using-pie">About using PIE</a>
    - <a href="#citation" id="toc-citation">Citation</a>
    - <a href="#contact" id="toc-contact">Contact</a>
  - <a href="#code-run-order" id="toc-code-run-order">Code Run Order:</a>
  - <a href="#inputs" id="toc-inputs">Inputs</a>
    - <a href="#ofm-sade-population-estimates"
      id="toc-ofm-sade-population-estimates">OFM SADE Population Estimates</a>
    - <a href="#census-2020-pl-94-171" id="toc-census-2020-pl-94-171">Census
      2020 PL 94-171</a>
    - <a href="#census-2020-block-relationship-file"
      id="toc-census-2020-block-relationship-file">Census 2020 block
      relationship file</a>
    - <a href="#census-2010-pl-94-171" id="toc-census-2010-pl-94-171">Census
      2010 Pl 94-171</a>
    - <a href="#census-2010-mars-population-estimates"
      id="toc-census-2010-mars-population-estimates">Census 2010 MARS
      population estimates</a>
    - <a href="#and-2021-ofm-county-x-age-x-sex-population-estimates"
      id="toc-and-2021-ofm-county-x-age-x-sex-population-estimates">2020 and
      2021 OFM County X Age X Sex Population Estimates</a>
    - <a href="#and-2021-ofm-county-x-raceeth-estimates"
      id="toc-and-2021-ofm-county-x-raceeth-estimates">2020 and 2021 OFM
      County X Race/Eth Estimates</a>
    - <a href="#ofm-saep-estimates-for-2020-census-blocks"
      id="toc-ofm-saep-estimates-for-2020-census-blocks">2020 - 2022 OFM SAEP
      estimates for 2020 census blocks</a>
  - <a href="#process" id="toc-process">Process</a>
    - <a href="#compile-2020-pl-94-171-data"
      id="toc-compile-2020-pl-94-171-data">1. Compile 2020 PL 94-171 data</a>
    - <a href="#generate-mars-splits-from-2010-data"
      id="toc-generate-mars-splits-from-2010-data">2. Generate MARS splits
      from 2010 data</a>
    - <a href="#create-frankenpop" id="toc-create-frankenpop">3. Create
      Frankenpop</a>
    - <a href="#compile" id="toc-compile">4. Compile</a>
  - <a href="#output" id="toc-output">Output</a>

# Frankenpop/Population Interim Estimates (PIE)

## Note
This repo exists for documentation purposes only. The results are available upon request.

## About

Population Interim Estimates (PIE) is the combination of the race/eth
and geography pattern from Census 2020 redistricting data with the age
and sex pattern from Census 2010 based SADE estimates from OFM. Once
combined, the resulting estimates are calibrated to available Census
2020 based population estimates at the county level.

As an interim product, PIE will eventually be replaced by an updated set
of Small Area Demographic Estimates (SADE) from OFM-- probably in 2024.

Note: Frankenpop was the original (cheekier) name for PIE. References to
Frankenpop in legacy documentation apply/refer to PIE.

### Dimensions

\- Single year age

\- 2020 census blocks and aggregates (e.g. tracts, County, ZIP codes)

\- Race/ethnicity

\- Sex

\- 2000 - 2022+

### About using PIE

PIE does two things - it replaces existing Census 2010-based population
estimates from OFM and it provides new Census 2020-bases population
estimates . As such, estimates using a Census 2010 based estimate (even
if projected forward) should be replaced/recalculated using PIE. That
is, all estimates for years between 2000 - 2022 should be updated (or
computed) to use a PIE denominator. Do not mix and match denominator
sources.

PIE replaces existing Census 2010 based estimates from OFM. Please use
PIE going forward and all metrics that used the previous Census 2010
based estimates. Do not mix and match denominators.

Updating rates and other metrics to use PIE as the denominator may
change results. This is to be expected and communicated clearly. In
general, the change can be attributed to PIE and the improved
denominators.

### Citation

Washington State Population Interim Estimates (PIE), December 2022.

### Contact

Please contact rads@kingcounty.gov with any questions on PIE. Please
also use this email if you would like access to the underlying data (in
CSV form).

Other questions (e.g. how to use the PopPIE app, community health
assessment, CHAT, age adjustment, etc.) should be directed to the DOH
Center for Epidemiology Practice, Equity, and Assessment (CEPEA) at
cepea@doh.wa.gov.

## Code Run Order:

1.  [pl_all_4\_2020_dar.R](pl_all_4_2020_dar.R): Process Census data
2.  [generate_mars_splits.R](generate_mars_splits.R): Generate
    adjustment factors to clean up Census race data
3.  [create_blk_frankenpop.R](create_blk_frankenpop.R): Create estimates
    for 2020
4.  [rake_and_output.R](rake_and_output.R): Rake initial estimates to
    OFM margins and create additional years
5.  [backcast_pop.R](backcast_pop.R): Create adjusted pop estimates for
    2011 - 2019
6.  [compile_results.R](compile_results.R): Create adjusted pop
    estimates for 2000 - 2010 and combine with 2011 -2019 and 2020+
7.  [blk_to_zip.R](blk_to_zip.R): Find the relationship between 2020
    blocks and ZIPs
8.  [create_additional_geographies.R](create_additional_geographies.R):
    Convert from 2020 blocks to other geographies.

## Inputs

### [OFM SADE Population Estimates](https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/estimates-april-1-population-age-sex-race-and-hispanic-origin)

2000 - 2020 population estimates for Washington at 2010 census block X
race/eth X gender X age level.

### [Census 2020 PL 94-171](https://www.census.gov/data/datasets/2020/dec/2020-census-redistricting-summary-file-dataset.html)

2020 population results for Washington for 2020 census block X race/eth
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

### [2020 - 2022 OFM SAEP estimates for 2020 census blocks](https://ofm.wa.gov/washington-data-research/population-demographics/population-estimates/small-area-estimates-program)

OFM SAEP estimates for 2020 - 2022 based on Census 2020 at the 2020
block level.

## Process

### 1. Compile 2020 PL 94-171 data

[pl_all_4\_2020_dar.R](pl_all_4_2020_dar.R) is a modified version of a
Census prepared R script that loads, standardizes, and cleans Census
2020 Pl 94-171 data products. Specifically, this script creates a
dataset that provides geography X race/eth X age group (over/under 18)
population counts for the detailed list of race/eth groups (all 62 of
them). The process also carries forward the “other” race/eth category to
be redistributed later. The population counts for each race/eth groups
are mutually exclusive.

### 2. Generate MARS splits from 2010 data

Pl 94-171 data products include an “other” race/eth category which is
redistributed to the main collection of race/eth groups. The MARS
approach uses a multiple stage algorithm to redistribute the “other”
population to the more sensible race/eth categories. The 2020 MARS
estimates have not been released, as such, Frankenpop, via
[generate_mars_splits.R](generate_mars_splits.R), derives adjustment
scalars by comparing the 2010 MARS data with the 2010 Pl 94-171 data at
the county level.

The scalars are race/eth X county specific and usually scale up the
population of a race/eth category to account for population originally
in the “other” category. For race/eth groups that are “multiple race”,
the scalar is usually deflationary as the MARS adjustment overrules the
previous assignment and assigns population elsewhere..

Census 2020 race/ethnicity ascertainment meaningfully changed relative
to Census 2010 as did (at least via anecdote) cultural awareness of
multi-race people. The effect of these factors on the validity on
carrying forward the MARS assignments from 2010 is unknown. However, it
is still probably better to use the 2010 scalars rather than other
assignment approaches (e.g. relative to category size).

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

All SADE estimates (2000 - 2020 by age, sex, race/eth, and 2010 block)
are converted from 2010 blocks to 2020 blocks via this approach.

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

#### Rake 2020 SADE estimates to Census 2020 results (e.g. Frankenpop)

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

#### Rake to SAEP 2020+ Block estimates

The results from the previous step are raked to match OFM SAEP 2020
populations estimates (all age, race/eth, gender) at the block level.

Additionally, when SAEP estimates are available without corresponding
County level breakdowns by race/eth or age X sex (e.g. SAEP 2022 exists,
but the other estimates stop in 2021) , the demographic breakdowns
implied by the latter set of estimates are applied to the SAEP results
to create raking targets for the missing years. In short, the
demographic patterns are carried forward proportionally unchanged.

#### Rake to County level OFM estimates

Once the age/sex patterns from OFM’s SADE estimates have been raked to
match (as best as possible) the 2020 Census results, these results are
[multidimensionally raked](rake_and_output.R) to match the Age X Sex X
County and Race/Eth X County estimates. The raking is further stratified
by year and year Y+1 is dependent on the results from year Y (e.g. 2021
starts with the 2020 raked results).

#### Backcast 2011 - 2019

After the SADE estimates for 2011 - 2019 are converted from 2010 blocks
to 2020 they are adjusted such that they coherently flow into the 2020
Frankenpop estimate. [The method is described in greater detail
here.](fpop_bcast_simple_walkthrough.md) [The implementation can be
found here.](backcast_pop.R)

### 4. Compile

Note: links in this section may be restricted to users with access to
repositories on ADPE’s github. Email Daniel if you’d like access.

#### Combine 2000 - 2010, 2011 - 2019, and 2022+

Each inter/post-censal period requires a different amount of adjustment
to create the coherent 2020 census block based population time series.
[Once each stage is processed, the file structures are harmonized and
compiled into sets based on geographic type.](compile_results.R)

#### Create aggregate geographics

[Aggregate geographies like ZIP code, school district, legislative
district, 2020 block group, and 2020 census tract are constructed from
the block level results](create_additional_geographies.R).

Unlike the other geographies, ZIP codes are not directly aggregated from
blocks. Instead, ZIP codes populations are created proportionally to the
geographic overlap with census blocks. The ratios/overlaps were
generated by DOH and cleaned by OFM. The 2021 block to ZIP code mapping
was applied for 2022.

## Output

Population estimates for every 2020 census block X single year age X
gender X race/eth in Washington state for 2000 - 2020. Aggregate
geographies such as ZIP code, school district, legislative district,
2020 block group, and 2020 census tract are also available.

Data dictionary for the block level results:

| Column Name         | Description                                                                                                                                                                                      |
|---------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| CensusBlockCode2020 | FIPS code for the census block, 2020 edition                                                                                                                                                     |
| Hispanic            | Binary flag. Indicates Hispanic ethnicity.                                                                                                                                                       |
| Gender              | Gender/sex at birth. Refer to OFM’s description/depiction of sex/gender for the correct interpretation.                                                                                          |
| RaceMars97          | Up to 5 digit code indicating race. Structured as \[White\]\[Black\]\[AIAN\]\[Asian\]\[NHPI\]. For example: 10000 indicates White, 10100 indicates White and AIAN, and \[000\]10 indicates NHPI. |
| Population          | Number of people                                                                                                                                                                                 |
| Year                | FIPS code for tract                                                                                                                                                                              |
| AgeGroup            | 0-99 single year of age, 100 for 100-104, 105 for 105 - 109, 110 for 100+                                                                                                                        |
