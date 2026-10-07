# Thesis models and robustness checks
# Run this script from the repository root.
# I use the archived final analysis dataset here so I do not have to recreate
# the separate review-volume collection step that is no longer documented.

library(dplyr)
library(tidyr)
library(lubridate)
library(ggplot2)
library(lmtest)
library(sandwich)
library(interactions)
library(car)

analysis <- read.csv(file.path("data", "private", "final_analysis_data.csv"))
dir.create("visuals", showWarnings = FALSE)

# Format variables used in the models
analysis <- analysis %>%
  mutate(
    imdb_id = as.character(imdb_id),
    release_date = as.Date(release_date),
    genre_category = factor(genre_category),
    release_month = month(release_date),
    release_season = case_when(
      release_month %in% c(12, 1, 2) ~ "Winter",
      release_month %in% c(3, 4, 5) ~ "Spring",
      release_month %in% c(6, 7, 8) ~ "Summer",
      release_month %in% c(9, 10, 11) ~ "Fall"
    )
  )

analysis$release_season <- factor(
  analysis$release_season,
  levels = c("Winter", "Spring", "Summer", "Fall")
)

analysis <- analysis %>%
  mutate(
    log_volume_IMDB = log(imdb_total_reviews),
    log_volume_RT = log(rt_total_audience_ratings),
    c_valence_IMDB = as.numeric(scale(valence_mean_IMDB, scale = FALSE)),
    c_var_IMDB = as.numeric(scale(valence_var_IMDB, scale = FALSE)),
    c_logvol_IMDB = as.numeric(scale(log_volume_IMDB, scale = FALSE)),
    c_cred_IMDB = as.numeric(scale(credibility_IMDB, scale = FALSE)),
    c_valence_RT = as.numeric(scale(valence_mean_RT, scale = FALSE)),
    c_var_RT = as.numeric(scale(valence_var_RT, scale = FALSE)),
    c_logvol_RT = as.numeric(scale(log_volume_RT, scale = FALSE)),
    c_cred_RT = as.numeric(scale(credibility_RT, scale = FALSE))
  )

cat("Movies:", n_distinct(analysis$imdb_id), "\n")
cat("Movie-week observations:", nrow(analysis), "\n")

# Descriptive checks
summary(analysis$log_box_office_weekly)
summary(analysis$week_since_release)

movie_level <- analysis %>%
  distinct(imdb_id, .keep_all = TRUE)

desc_vars <- movie_level %>%
  select(
    valence_mean_IMDB,
    valence_var_IMDB,
    credibility_IMDB,
    log_volume_IMDB,
    valence_mean_RT,
    valence_var_RT,
    credibility_RT,
    log_volume_RT,
    log_budget
  )

summary(desc_vars)

imdb_corr <- movie_level %>%
  select(
    valence_mean_IMDB,
    valence_var_IMDB,
    credibility_IMDB,
    log_volume_IMDB,
    log_budget
  )

rt_corr <- movie_level %>%
  select(
    valence_mean_RT,
    valence_var_RT,
    credibility_RT,
    log_volume_RT,
    log_budget
  )

cor(imdb_corr, use = "pairwise.complete.obs")
cor(rt_corr, use = "pairwise.complete.obs")

# Baseline model
m0 <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season,
  data = analysis
)

coeftest(m0, vcov = vcovCL(m0, cluster = ~ imdb_id))

# IMDb models
m1_imdb <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_valence_IMDB + c_logvol_IMDB + c_cred_IMDB,
  data = analysis
)

coeftest(m1_imdb, vcov = vcovCL(m1_imdb, cluster = ~ imdb_id))

m2_imdb <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_valence_IMDB * c_cred_IMDB +
    c_logvol_IMDB * c_cred_IMDB,
  data = analysis
)

coeftest(m2_imdb, vcov = vcovCL(m2_imdb, cluster = ~ imdb_id))

# Rotten Tomatoes models
m1_rt <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_valence_RT + c_logvol_RT + c_cred_RT,
  data = analysis
)

coeftest(m1_rt, vcov = vcovCL(m1_rt, cluster = ~ imdb_id))

m2_rt <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_valence_RT * c_cred_RT +
    c_logvol_RT * c_cred_RT,
  data = analysis
)

coeftest(m2_rt, vcov = vcovCL(m2_rt, cluster = ~ imdb_id))

# Interaction plots used in the thesis
p_imdb <- interact_plot(
  m2_imdb,
  pred = c_valence_IMDB,
  modx = c_cred_IMDB,
  plot.points = FALSE,
  interval = TRUE,
  x.label = "Review Valence (IMDb, centered)",
  y.label = "Log Weekly Box Office",
  modx.labels = c("-1 SD credibility", "Mean credibility", "+1 SD credibility"),
  legend.main = "Credibility (IMDb Helpfulness)",
  data = analysis
)

ggsave(
  file.path("visuals", "imdb_valence_credibility_interaction.png"),
  p_imdb,
  width = 7,
  height = 5,
  dpi = 300
)

p_rt <- interact_plot(
  m2_rt,
  pred = c_logvol_RT,
  modx = c_cred_RT,
  plot.points = FALSE,
  interval = TRUE,
  x.label = "Review Volume (RT, log and centered)",
  y.label = "Log Weekly Box Office",
  modx.labels = c("-1 SD credibility", "Mean credibility", "+1 SD credibility"),
  legend.main = "Credibility (Verified Users Share)",
  data = analysis
)

ggsave(
  file.path("visuals", "rt_volume_credibility_interaction.png"),
  p_rt,
  width = 7,
  height = 5,
  dpi = 300
)

# Models using sentiment variance instead of mean valence
m1_imdb_var <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_var_IMDB + c_logvol_IMDB + c_cred_IMDB,
  data = analysis
)

coeftest(m1_imdb_var, vcov = vcovCL(m1_imdb_var, cluster = ~ imdb_id))

m2_imdb_var <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_var_IMDB +
    c_logvol_IMDB * c_cred_IMDB,
  data = analysis
)

coeftest(m2_imdb_var, vcov = vcovCL(m2_imdb_var, cluster = ~ imdb_id))

m1_rt_var <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_var_RT + c_logvol_RT + c_cred_RT,
  data = analysis
)

coeftest(m1_rt_var, vcov = vcovCL(m1_rt_var, cluster = ~ imdb_id))

m2_rt_var <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_var_RT +
    c_logvol_RT * c_cred_RT,
  data = analysis
)

coeftest(m2_rt_var, vcov = vcovCL(m2_rt_var, cluster = ~ imdb_id))

# Robustness checks from the thesis
m2_imdb_levels <- lm(
  box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_valence_IMDB * c_cred_IMDB +
    c_logvol_IMDB * c_cred_IMDB,
  data = analysis
)

coeftest(m2_imdb_levels, vcov = vcovCL(m2_imdb_levels, cluster = ~ imdb_id))

m2_imdb_early <- lm(
  log_box_office_weekly ~ log(week_since_release) + log_budget +
    genre_category + release_season + c_valence_IMDB * c_cred_IMDB +
    c_logvol_IMDB * c_cred_IMDB,
  data = analysis %>% filter(week_since_release <= 6)
)

coeftest(m2_imdb_early, vcov = vcovCL(m2_imdb_early, cluster = ~ imdb_id))

m2_imdb_quad <- lm(
  log_box_office_weekly ~ week_since_release + I(week_since_release^2) +
    log_budget + genre_category + release_season +
    c_valence_IMDB * c_cred_IMDB + c_logvol_IMDB * c_cred_IMDB,
  data = analysis
)

coeftest(m2_imdb_quad, vcov = vcovCL(m2_imdb_quad, cluster = ~ imdb_id))

m2_rt_quad <- lm(
  log_box_office_weekly ~ week_since_release + I(week_since_release^2) +
    log_budget + genre_category + release_season +
    c_valence_RT * c_cred_RT + c_logvol_RT * c_cred_RT,
  data = analysis
)

coeftest(m2_rt_quad, vcov = vcovCL(m2_rt_quad, cluster = ~ imdb_id))

# Multicollinearity checks
vif_results <- list(
  m1_imdb = vif(m1_imdb, type = "predictor"),
  m2_imdb = vif(m2_imdb, type = "predictor"),
  m1_rt = vif(m1_rt, type = "predictor"),
  m2_rt = vif(m2_rt, type = "predictor"),
  m1_imdb_var = vif(m1_imdb_var, type = "predictor"),
  m2_imdb_var = vif(m2_imdb_var, type = "predictor"),
  m1_rt_var = vif(m1_rt_var, type = "predictor"),
  m2_rt_var = vif(m2_rt_var, type = "predictor"),
  m2_imdb_levels = vif(m2_imdb_levels, type = "predictor"),
  m2_imdb_early = vif(m2_imdb_early)
)

vif_results

# Diagnostics for the two main interaction models
resettest(m2_imdb, power = 2:3, type = "fitted")
bptest(m2_imdb)

cooks_imdb <- cooks.distance(m2_imdb)
leverage_imdb <- hatvalues(m2_imdb)
rstud_imdb <- rstudent(m2_imdb)
dfbet_imdb <- dfbetas(m2_imdb)

which(cooks_imdb > 4 / nobs(m2_imdb))
which(leverage_imdb > 2 * length(coef(m2_imdb)) / nobs(m2_imdb))
which(abs(rstud_imdb) > 3)
apply(abs(dfbet_imdb) > 2 / sqrt(nobs(m2_imdb)), 2, which)

resettest(m2_rt, power = 2:3, type = "fitted")
bptest(m2_rt)

cooks_rt <- cooks.distance(m2_rt)
leverage_rt <- hatvalues(m2_rt)
rstud_rt <- rstudent(m2_rt)
dfbet_rt <- dfbetas(m2_rt)

which(cooks_rt > 4 / nobs(m2_rt))
which(leverage_rt > 2 * length(coef(m2_rt)) / nobs(m2_rt))
which(abs(rstud_rt) > 3)
apply(abs(dfbet_rt) > 2 / sqrt(nobs(m2_rt)), 2, which)

# Save the residual and Q-Q plots used in the diagnostics
png(file.path("visuals", "imdb_residuals_vs_fitted.png"), width = 1200, height = 900, res = 150)
plot(m2_imdb, which = 1)
dev.off()

png(file.path("visuals", "imdb_qq_plot.png"), width = 1200, height = 900, res = 150)
plot(m2_imdb, which = 2)
dev.off()

png(file.path("visuals", "rt_residuals_vs_fitted.png"), width = 1200, height = 900, res = 150)
plot(m2_rt, which = 1)
dev.off()

png(file.path("visuals", "rt_qq_plot.png"), width = 1200, height = 900, res = 150)
plot(m2_rt, which = 2)
dev.off()
