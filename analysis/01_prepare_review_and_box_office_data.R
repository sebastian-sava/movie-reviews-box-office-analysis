# Data preparation for the thesis project
# Run this script from the repository root.

library(tidyr)
library(dplyr)
library(lubridate)
library(stringr)
library(readr)
library(stringi)
library(vader)
library(future)
library(furrr)

data_dir <- file.path("data", "private")
processed_dir <- file.path("data", "processed")
dir.create(processed_dir, recursive = TRUE, showWarnings = FALSE)

imdb_raw <- read_csv(file.path(data_dir, "raw_imdb_reviews.csv"), show_col_types = FALSE)
rt_raw <- read_csv(file.path(data_dir, "raw_rt_reviews.csv"), show_col_types = FALSE)
bo_raw <- read_csv(file.path(data_dir, "daily_box_office.csv"), show_col_types = FALSE)
budget <- read_csv(file.path(data_dir, "movie_budgets.csv"), show_col_types = FALSE)
movies <- read_csv(file.path(data_dir, "movie_lookup.csv"), show_col_types = FALSE)

# I kept duplicate rows as they were in the thesis data, but I print the counts here
# so they are visible when the script is run.
cat("Duplicate IMDb rows:", sum(duplicated(imdb_raw)), "\n")
cat("Duplicate RT rows:", sum(duplicated(rt_raw)), "\n")

# Clean IMDb reviews
imdb_clean <- imdb_raw %>%
  mutate(
    release_date = mdy(release_date),
    helpful_votes = replace_na(as.numeric(helpful_votes), 0),
    not_helpful_votes = replace_na(as.numeric(not_helpful_votes), 0),
    total_votes = helpful_votes + not_helpful_votes,
    help_ratio = if_else(
      total_votes >= 2,
      helpful_votes / total_votes,
      NA_real_
    ),
    review_stars = as.numeric(review_stars),
    review_text = review_text %>%
      str_replace_all("[\u00A0]", " ") %>%
      str_squish()
  ) %>%
  filter(!is.na(imdb_id), !is.na(review_text), review_text != "")

# Run VADER on the IMDb review text
plan(multisession)

imdb_sent <- imdb_clean %>%
  mutate(vader_output = future_map(review_text, get_vader, .progress = TRUE)) %>%
  unnest_wider(vader_output) %>%
  mutate(
    compound = as.numeric(compound),
    pos = as.numeric(pos),
    neu = as.numeric(neu),
    neg = as.numeric(neg),
    but_count = as.integer(but_count)
  )

imdb_movie <- imdb_sent %>%
  group_by(imdb_id) %>%
  summarise(
    csv_title = first(csv_title),
    csv_year = first(csv_year),
    primary_genre = first(primary_genre),
    category = first(category),
    release_date = first(release_date),
    n_imdb_reviews = n(),
    avg_imdb_stars = mean(review_stars, na.rm = TRUE),
    valence_mean_IMDB = mean(compound, na.rm = TRUE),
    valence_var_IMDB = if_else(
      sum(!is.na(compound)) >= 3,
      var(compound, na.rm = TRUE),
      NA_real_
    ),
    credibility_IMDB = mean(help_ratio, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(imdb_movie, file.path(processed_dir, "imdb_movie_features.csv"))

# Clean Rotten Tomatoes reviews
rt_clean <- rt_raw %>%
  mutate(
    star_rating = as.numeric(star_rating),
    is_verified = as.numeric(is_verified),
    review_text = review_text %>%
      str_replace_all("[\u00A0]", " ") %>%
      str_squish()
  ) %>%
  filter(!is.na(imdb_id), !is.na(review_text), review_text != "")

# Run VADER on the RT review text
rt_sent <- rt_clean %>%
  mutate(vader_output = future_map(review_text, get_vader, .progress = TRUE)) %>%
  unnest_wider(vader_output) %>%
  mutate(
    compound = as.numeric(compound),
    pos = as.numeric(pos),
    neu = as.numeric(neu),
    neg = as.numeric(neg),
    but_count = as.integer(but_count)
  ) %>%
  rename(vader_compound = compound)

rt_movie <- rt_sent %>%
  group_by(imdb_id) %>%
  summarise(
    movie_title = first(movie_title),
    csv_year = first(csv_year),
    n_rt_reviews = n(),
    avg_rt_stars = mean(star_rating, na.rm = TRUE),
    valence_mean_RT = mean(vader_compound, na.rm = TRUE),
    valence_var_RT = if_else(
      sum(!is.na(vader_compound)) >= 3,
      var(vader_compound, na.rm = TRUE),
      NA_real_
    ),
    credibility_RT = mean(is_verified, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(rt_movie, file.path(processed_dir, "rt_movie_features.csv"))

# Clean daily box office data
bo_clean <- bo_raw %>%
  mutate(
    Date = dmy(Date),
    Gross = parse_number(as.character(Gross)),
    Movie = as.character(Movie),
    Movie = str_replace_all(
      Movie,
      c(
        "â€“" = "–",
        "â€™" = "’",
        "T‡r" = "Tár",
        "T�r" = "Tár"
      )
    )
  ) %>%
  filter(!is.na(Date), !is.na(Gross), !is.na(Movie))

# Match box office titles to IMDb IDs
normalize_title <- function(x) {
  x %>%
    str_replace("\\(\\d{4}\\)", "") %>%
    stri_trans_general("Latin-ASCII") %>%
    str_to_lower() %>%
    str_replace_all("[^a-z0-9]", "")
}

bo_titles <- bo_clean %>%
  distinct(Movie) %>%
  mutate(norm_title = normalize_title(Movie))

imdb_titles <- imdb_movie %>%
  mutate(
    imdb_label = paste0(csv_title, " (", csv_year, ")"),
    norm_title = normalize_title(imdb_label)
  ) %>%
  select(imdb_id, imdb_label, norm_title)

title_map <- bo_titles %>%
  left_join(imdb_titles, by = "norm_title")

# These were the few titles that needed a manual match in my thesis script.
manual_map <- tribble(
  ~Movie, ~imdb_id,
  "Tár (2022)", "tt14444726",
  "Five Nights at Freddy’s (2023)", "tt4589218",
  "Mission: Impossible – Dead Reckoning Part One (2023)", "tt9603212"
)

title_map <- title_map %>%
  left_join(manual_map, by = "Movie", suffix = c("", "_manual")) %>%
  mutate(imdb_id = coalesce(imdb_id, imdb_id_manual)) %>%
  select(Movie, imdb_id)

print(title_map %>% filter(is.na(imdb_id)))

# Convert daily revenue into weeks since release
bo_weekly <- bo_clean %>%
  left_join(title_map, by = "Movie") %>%
  left_join(imdb_movie %>% select(imdb_id, release_date), by = "imdb_id") %>%
  mutate(
    days_since_release = as.numeric(Date - release_date),
    week_since_release = floor(days_since_release / 7) + 1
  ) %>%
  filter(week_since_release >= 1) %>%
  group_by(imdb_id, week_since_release) %>%
  summarise(
    box_office_weekly = sum(Gross, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(log_box_office_weekly = log(box_office_weekly))

write_csv(bo_weekly, file.path(processed_dir, "box_office_weekly.csv"))

# The retained budget file already has IMDb IDs, so I use those directly here.
budgets_unique <- budget %>%
  transmute(
    imdb_id = as.character(IMDb_ID),
    production_budget = parse_number(Budget_USD)
  ) %>%
  group_by(imdb_id) %>%
  summarise(
    production_budget = max(production_budget, na.rm = TRUE),
    log_budget = log(production_budget),
    .groups = "drop"
  )

write_csv(budgets_unique, file.path(processed_dir, "budget_features.csv"))

# Keep the genre category used in the thesis models
movie_metadata <- movies %>%
  select(imdb_id, genre_category = category) %>%
  distinct()

write_csv(movie_metadata, file.path(processed_dir, "movie_metadata.csv"))

cat("Finished preparing the retained data sources.\n")
