#' @title Find templates more similar to other signals in a reference table
#'
#' @description \code{get_templates} find the signals that are closer to the acoustic space  centroid (i.e. close to the average acoustic structure) in a reference table.
#' @usage get_templates(reference, acoustic.space = NULL, path = ".",
#' n.sub.spaces = 1, plot = TRUE, color = "#21908C4D", ...)
#' @param reference Selection table (using the warbleR package's format, see \code{\link[warbleR]{selection_table}}) or data frame with columns
#' for sound file name (sound.files), selection number (selec), and start and end time of signal
#' (start and end).
#' @param acoustic.space Numeric matrix or data frame with the two dimensions of a custom acoustic space to be used for finding templates. if not supplied the acoustic space is calculated internally (default). Optional. Note that the function assumes that 'reference' and 'acoustic.space' refer to the same signals and similarly ordered.
#' @param path Character string containing the directory path where the sound files are located.
#'The current working directory is used as default.
#'@param n.sub.spaces Integer vector of length 1 with the number of sub-spaces to split the total acoustic space. If 1 only the signal closer to the centroid is returned. If higher than 1 the function returns additional signals that those closer to the centroids of the sub-spaces. To do this, the function defines sub-spaces as equal-size slices of a circle centered at the centroid of the acoustic space.
#' @param plot Logical to control if the plot is created. Default is \code{TRUE}.
#' @param color Character string with the point color. Default is '#21908C4D'.
#' @param ... Additional arguments to be passed to \code{\link[warbleR]{spectro_analysis}} for further customization when measuring parameters to calculate the acoustic space.
#' @return The function returns a 'selection_table' (warbleR package's formats, see \code{\link[warbleR]{selection_table}}) or data frame (if sound files can't be found) containing the start and end of each signal by
#'   sound file. If no signal was detected for a sound file it is not included in the output data frame.
#' @export
#' @name get_templates
#' @details This function finds signals from a reference table that are representative of the acoustic variation. This is done by finding the signals closer to the centroid of the acoustic space. If the acoustic space is not supplied ('acoustic.space' argument) then the function will estimate it by measuring several acoustic parameters using the function \code{\link[warbleR]{spectro_analysis}} and summarizing it with Principal Component Analysis (after z-transforming parameters) using the function \code{\link[stats]{prcomp}}. The rationale is that a signal closest to the average signal structure is more likely to share structural features with most signals across the acoustic space than a signal in the periphery of the space.
#' If only 1 template is required the function returns that closest to the acoustic space centroid. If more than 1 templated is required additional signals are returned that are representative of the acoustic space. To do this, the function defines sub-spaces as equal-size slices of a circle centered at the centroid of the acoustic space. A column 'template' is included in the output selection table that identifies each template. Custom acoustic spaces can be supplied with argument 'acoustic.space'.
#'
#' @examples {
#' # Save example files into temporary working directory
#' data("lbh1", "lbh2", "lbh_reference")
#' writeWave(lbh1, file.path(tempdir(), "lbh1.wav"))
#' writeWave(lbh2, file.path(tempdir(), "lbh2.wav"))
#'
#' # get a single mean template
#' template <- get_templates(reference = lbh_reference, path = tempdir())
#'
#' # get 3 templates
#' template <- get_templates(reference = lbh_reference, n.sub.spaces = 3, path = tempdir())
#' }
#'
#' @references {
#' Araya-Salas, M. (2021), ohun: automatic detection of acoustic signals. R package version 0.1.0.
#' }
#' @seealso \code{\link{template_detector}}
#' @author Marcelo Araya-Salas (\email{marcelo.araya@@ucr.ac.cr}). Implements a
#' modified version of the timer function from seewave.
#last modification on feb-2022 (MAS)

get_templates <-
  function(reference,
           acoustic.space = NULL,
           path = ".",
           n.sub.spaces = 1,
           plot = TRUE,
           color = "#21908C4D",
           ...) {

     if (!is.null(acoustic.space))
      if (nrow(reference) != nrow(acoustic.space))
        stop("'reference' and 'acoustic.space' must have the same number of columns")

    if (is.null(acoustic.space)) {
      spectral_parameters <- spectro_analysis(reference, path = path, ...)

      # remove columns with NAs
      spectral_parameters <-
        spectral_parameters[, !sapply(spectral_parameters, anyNA)]

      # get PCA
      pca <-
        stats::prcomp(spectral_parameters[, 2:27], scale. = TRUE)

      # get variance by PC
      variance_pca <- summary(pca)$importance

      # print info
      cat(crayon::silver(
        paste0(
          "The first 2 principal components explained ",
          round(variance_pca[3, 2], 2),
          " of the variance"
        )
      ))

      # keep those as acoustic space
      acoustic.space <- pca$x[, 1:2]

      plot_labs <- c("PC1", "PC2")
    } else {

      if (length(dim(acoustic.space)) != 2)
        stop("Acoustic space must be either a data frame or a matrix with 2 column")

      if (ncol(acoustic.space) != 2)
        stop("Acoustic space must have 2 columns")

      plot_labs <- if (!is.null(colnames(acoustic.space))) colnames(acoustic.space) else
c("Dimension 1", "Dimension 2")
      }

    template_indx <- find_templates(reference = reference, n.sub.spaces = n.sub.spaces, space = acoustic.space, plot = plot, color = color, xlab = plot_labs[1], ylab = plot_labs[2])

    template_indx <- template_indx[!is.na(template_indx)]

      # extract those selections
    templates <- reference[template_indx, ]
    templates$template <- names(template_indx)

    # save as a selection table
    # templates <-
    #   warbleR::selection_table(templates, path = path, pb = FALSE)

    return(templates)
  }


# internal function to find (and plot) templates in the acoustic space
find_templates <- function(reference = NULL, n.sub.spaces, space = NULL, plot = TRUE, color = "#21908C4D", xlab = "Dimension 1", ylab = "Dimension 2")
{
  x <- rep(1, n.sub.spaces)
  space <- space[, 1:2]
  space <- data.frame(space)
  space$...NROW <- 1:nrow(space)

  # mean center
  mean_dim1 <- mean(space[, 1])
  mean_dim2 <- mean(space[, 2])

  # center at 0
  space[, 1] <-  space[, 1] - mean_dim1
  space[, 2] <-  space[, 2] - mean_dim2

  x <- c(0, cumsum(x)/sum(x))
  dx <- diff(x)
  nx <- length(dx)
  radius <- 100

  t2xy <- function(t) {
    t2p <- 2 * pi * t + 0 * pi/180
    list(x = radius * cos(t2p), y = radius * sin(t2p))
  }

  if (plot)
  plot(space[, 1] + mean_dim1, space[, 2] + mean_dim2, pch = 20, cex = 2, col = color, xlab = xlab, ylab = ylab)

  # get polygon for each sub space
  if (n.sub.spaces > 1)
  polys <- lapply(1:nx, function(i){
    n <- max(2, floor(100 * dx[i])) # 100 equivalent to edges in pie()
    P <- t2xy(seq.int(x[i], x[i + 1], length.out = n))

    if (plot)
    lines(c(P$x[1], 0) + mean_dim1, c(P$y[1], 0) + mean_dim2, lty = 3, col = "gray", lwd = 3)

    pol_df <- data.frame(x = c(P$x, 0), y = c(P$y, 0))
    poly <- sp::Polygons(list(sp::Polygon(pol_df)), ID = 1)

    spp <- sp::SpatialPolygons(list(poly))

    return(spp)
  }) else polys <- vector()

  # get  centroids, the first one is the centroid of the enitre space
  centroids <- vector(length = length(polys) + 1)

  for (i in 0:length(polys)){

    if (i > 0)
      whch_within  <- which(!is.na(sp::over(x = sp::SpatialPoints(space[, 1:2]),  y = sp::SpatialPolygons(polys[[i]]@polygons), returnList = FALSE))) else whch_within <- 1:nrow(space)

      if (length(whch_within) > 0){
        if (length(whch_within) > 1) {

          sub_space <- space[whch_within, ]

          # get centroid
          centroid_coors <- colMeans(sub_space[, 1:2])

          # and distance to centroid
          dists_to_centroid <-
            unlist(lapply(1:nrow(sub_space), function(x)
              stats::dist(
                rbind(sub_space[x, 1:2], centroid_coors)
              )))

          centroid <- sub_space$...NROW[which.min(dists_to_centroid)]
        } else
          centroid <- sub_space$...NROW[whch_within]
      } else
        centroid <- NA

      centroids[i + 1] <- centroid
  }


  if (length(centroids) > 1)
    if (any(centroids[-1] == centroids[1])){
      cat(crayon::silver(sum(centroids[-1] == centroids[1]),
                         "sub-space centroid(s) coincide with the overall centroid and was (were) removed"
      ))
      centroids <- c(centroids[1], centroids[-1][centroids[-1] != centroids[1]])

    }

  names(centroids) <-  if (length(centroids) > 1) c("centroid", paste0("templ-", 1:(length(centroids) - 1))) else "centroid"




  # plot
  if (plot){
  points(x = space[centroids, 1] + mean_dim1, y = space[centroids, 2] + mean_dim2, col = "#FDE725FF", pch = 1, cex = 1.8, lwd = 4)

  text(x = space[centroids, 1] + mean_dim1, y = space[centroids, 2] + mean_dim2, labels = names(centroids), pos = 4)
  }

  return(centroids)
}

