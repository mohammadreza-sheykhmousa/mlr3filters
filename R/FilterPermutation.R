#' @title Permutation Filter
#'
#' @name mlr_filters_permutation
#'
#' @description
#' The permutation filter randomly permutes the values of a single feature in a
#' [mlr3::Task] to break the association with the response. The permutated
#' feature, together with the unmodified features, is used to perform a
#' [mlr3::resample()]. The permutation filter score is the difference between
#' the aggregated performance of the [mlr3::Measure] and the performance
#' estimated on the unmodified [mlr3::Task].
#'
#' @section Parameters:
#' \describe{
#' \item{`standardize`}{`logical(1)`\cr
#' Standardize feature importance by maximum score.}
#' \item{`nmc`}{`integer(1)`}\cr
#' Number of Monte-Carlo iterations to use in computing the feature importance.
#' }
#'
#' @family Filter
#' @template seealso_filter
#' @export
FilterPermutation = R6Class("FilterPermutation",
  inherit = Filter,
  public = list(

    #' @field learner ([mlr3::Learner])\cr
    learner = NULL,
    #' @field resampling ([mlr3::Resampling])\cr
    resampling = NULL,
    #' @field measure ([mlr3::Measure])\cr
    measure = NULL,

    #' @description Create a FilterDISR object.
    #' @param learner ([mlr3::Learner])\cr
    #'   [mlr3::Learner] to use for model fitting.
    #' @param resampling ([mlr3::Resampling])\cr
    #'   [mlr3::Resampling] to be used within resampling.
    #' @param measure ([mlr3::Measure])\cr
    #'   [mlr3::Measure] to be used for evaluating the performance.
    initialize = function(learner = mlr3::lrn("classif.rpart"), resampling = mlr3::rsmp("holdout"),
      measure = NULL) {


      param_set = ParamSet$new(list(
        ParamLgl$new("standardize", default = FALSE),
        ParamInt$new("nmc", lower = 1L, default = 50L))
      )

      self$learner = learner = assert_learner(as_learner(learner, clone = TRUE))
      self$resampling = assert_resampling(as_resampling(resampling), instantiated = FALSE)
      self$measure = assert_measure(as_measure(measure,
        task_type = learner$task_type, clone = TRUE), learner = learner)
      packages = unique(c(self$learner$packages, self$measure$packages))

      super$initialize(
        id = "permutation",
        task_type = learner$task_type,
        feature_types = learner$feature_types,
        packages = packages,
        param_set = param_set,
        man = "mlr3filters::mlr_filters_performance"
      )
    }
  ),

  private = list(
    .calculate = function(task, nfeat) {
      task = task$clone()
      fn = task$feature_names
      nmc = self$param_set$values$nmc %??% 50L

      backend = task$backend
      rr = resample(task, self$learner, self$resampling)
      baseline = rr$aggregate(self$measure)

      perf = matrix(NA_real_, nrow = nmc, ncol = length(fn),
        dimnames = list(NULL, fn))

      for (j in seq_col(perf)) {
        data = task$data(cols = fn[j])

        for (i in seq_row(perf)) {
          data[[1L]] = shuffle(data[[1L]])
          task$cbind(data)
          rr = resample(task, self$learner, self$resampling)
          perf[i, j] = rr$aggregate(self$measure)

          # reset to previous backend
          # this is a bit of an ugly hack, but since we are only overwriting
          # a column with its own values during `task$cbind()`, this should pose
          # no problem.
          task$backend = backend
        }
      }

      delta = baseline - colMeans(perf)

      if (self$measure$minimize) {
        delta = -delta
      }

      if (!isTRUE(self$param_set$values$standardize)) {
        delta = delta / max(delta)
      }

      delta
    }
  )
)

#' @include mlr_filters.R
mlr_filters$add("permutation", FilterPermutation)
