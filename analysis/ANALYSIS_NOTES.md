# Analysis notes

The public analysis is split into two scripts.

`01_prepare_review_and_box_office_data.R` shows the parts of the data preparation that can still be traced from the retained source files: cleaning IMDb and Rotten Tomatoes reviews, running VADER sentiment analysis, building the credibility measures, matching movie IDs, preparing budgets and aggregating daily box office to movie-week level.

`02_run_thesis_models.R` starts from the archived final thesis dataset and reproduces the model specifications, interaction plots, robustness checks and diagnostics used in the thesis.

I no longer have a reliable record of how the separate review-volume source file was collected. I therefore do not include or recreate that collection step. The final thesis dataset is kept as a private input so the original model variables can still be reproduced without inventing a new provenance for them.

The raw review files also contain some duplicate rows. The preparation script reports those counts but does not silently remove them, because deduplication was not part of the retained thesis script.

The analysis is observational. Review measures were aggregated at movie level and then used alongside weekly box-office observations, so the results should be described as associations rather than causal effects.
