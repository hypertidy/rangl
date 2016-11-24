#' Generate primitive-based spatial structures
#'
#' Create primitive-based "mesh" structures from various inputs.
#'
#' #' Methods exist for SpatialPolygons, SpatialLines, rgl mesh3d(triangle) ...
#' @param x input data
#' @param ... arguments passed to methods
#' @param max_area maximum area in coordinate system of x, passed to \code{\link[RTriangle]{triangulate}} 'a' argument
#' @return a list of tibble data frames, using the gris-map_table model
#' @export
#' @examples
#' ## -----------------------------------------------
#' ## POLYGONS
#' library(maptools)
#' data(wrld_simpl)
#' b <- rangl(wrld_simpl)
#' plot(b)
#' #if (require(rworldxtra)) {
#'
#' #data(countriesHigh)
#' #sv <- c("New Zealand", "Antarctica", "Papua New Guinea",
#' #  "Indonesia", "Malaysia", "Fiji", "Australia")
#' #a <- subset(countriesHigh, SOVEREIGNT %in% sv)
#' #b7 <- rangl(a, max_area = 0.5)
#' #plot(globe(b7))
#' #}
#' ## -----------------------------------------------
#' ## LINES
#' #l1 <- rangl(as(a, "SpatialLinesDataFrame") )
#' #plot(l1)
#' #plot(globe(l1))
rangl <- function(x, ...) {
  UseMethod("rangl")
}

line_mesh_map_table1 <- function(tabs) {
  tabs$v$countingIndex <- seq(nrow(tabs$v))
  nonuq <- dplyr::inner_join(tabs$bXv, tabs$v, "vertex_")
  
  pl <- list(P = as.matrix(tabs$v[, c("x_", "y_")]),
                        S = do.call(rbind, lapply(split(nonuq, nonuq$branch_),
                                                  function(x) path2seg(x$countingIndex))))
  
  tabs$v <- tibble::tibble(x_ = pl$P[,1], y_ = pl$P[,2], vertex_ = spbabel:::id_n(nrow(pl$P)))
  tabs$b <- tabs$bXv <- NULL
  tabs$l <- tibble::tibble(segment_ = spbabel:::id_n(nrow(pl$S)), object_ = tabs$o$object_[1])
  tabs$lXv <- tibble::tibble(segment_ = rep(tabs$l$segment_, each = 2), 
                             vertex_ = tabs$v$vertex_[as.vector(t(pl$S))])
  
  tabs
}
#' @rdname rangl
#' @importFrom dplyr %>%  arrange distinct mutate
#' @export
rangl.SpatialLines <- function(x, ...) {
  pr4 <- proj4string(x)
  if (! "data" %in% slotNames(x)) {
    dummy <- data.frame(row_number = seq_along(x))
    x <- sp::SpatialLinesDataFrame(x, dummy, match.ID = FALSE)
  }
  tabs <- spbabel::map_table(x)
  ll <- vector("list", nrow(tabs$o))
  for (i_obj in seq(nrow(tabs$o))) {
    tabs_i <- tabs; tabs_i$o <- tabs_i$o[i_obj, ]
    tabs_i <- semi_cascade(tabs_i)
    tt_i <- line_mesh_map_table1(tabs_i)
    ll[[i_obj]] <- tt_i
  }
  
  outlist <- vector("list", length(ll[[1]]))
  nms <- names(ll[[1]])
  names(outlist) <- nms
  for (i in seq_along(outlist)) {
    outlist[[i]] <- dplyr::bind_rows(lapply(ll, "[[", nms[i]))
  }
  
  ## renormalize the vertices
  allverts <- dplyr::inner_join(outlist$lXv, outlist$v, "vertex_")
  allverts$uvert <- as.integer(factor(paste(allverts$x_, allverts$y_, sep = "_")))
  allverts$vertex_ <- spbabel:::id_n(length(unique(allverts$uvert)))[allverts$uvert]
  outlist$lXv <- allverts[, c("segment_", "vertex_")]
  
  ## normalize segments
  ## this arrange was borkifying
  a <- outlist$lXv #%>% dplyr::arrange(segment_, vertex_)
  lista <- split(a, a$segment_)
  f <- factor(unlist(lapply(lista, function(x) paste(x$vertex_, collapse = "_"))))
  outlist$lXv <- a %>% inner_join(tibble(segment_ = names(lista), usegment = as.integer(f))) %>% mutate(segment_ = segment_[usegment]) %>% 
    dplyr::select(segment_, vertex_) %>% distinct()
  outlist$l <- outlist$l %>% inner_join(tibble(segment_ = names(lista), usegment = as.integer(f))) %>% 
    mutate(segment_ = segment_[usegment]) %>% 
    dplyr::select(segment_, object_)
  
  
  outlist$v <- dplyr::distinct_(allverts, "x_", "y_", "vertex_")
  ## finally add longitude and latitude
  outlist$meta <- tibble::tibble(proj = pr4, x = "x_", y = "y_", ctime = format(Sys.time(), tz = "UTC"))
  class(outlist) <- "linemesh"
  outlist
}




