#' @importFrom utils head
path2seg <- function(x) {
  ## this is a trick of array logic to generate paired indexes from a sequence
  head(suppressWarnings(matrix(x, nrow = length(x) + 1, ncol = 2, byrow = FALSE)), -2L)
}


## this could replace tri_mesh_map_table1
## by input of a simpler object, not so many tables
tri_mesh_PRIMITIVE <- function(x, max_area = NULL)


## this internal function does the decomposition to primitives of a 
##  single Spatial object, i.e. a "multipolygon"
## we need to do it one object at a time otherwise keeping track
## of the input versus add vertices is harder (but maybe possible later)
tri_mesh_map_table1 <- function(tabs, max_area = NULL) {
  ## the row index of the vertices
  ## we need this in the triangulation
  tabs$v$countingIndex <- seq(nrow(tabs$v))
  ## join the vertex-instances to the vertices table
  ## so, i.e. expand out the duplicated x/y coordinates
  nonuq <- dplyr::inner_join(tabs$bXv, tabs$v, "vertex_")
  
  ## create Triangle's Planar Straight Line Graph
  ## which is an index matrix S of every vertex pair P
  ps <- RTriangle::pslg(P = as.matrix(tabs$v[, c("x_", "y_")]),
                        S = do.call(rbind, lapply(split(nonuq, nonuq$branch_),
                                                  function(x) path2seg(x$countingIndex))))
  
  ## build the triangulation, with input max_area (defaults to NULL)
  tr <- RTriangle::triangulate(ps, a = max_area)
  
  ## NOTE: the following only checks for presence of triangle centres within
  ## known holes, so this doesn't pick up examples of overlapping areas e.g. 
  ## https://github.com/r-gris/rangl/issues/39
  
  ## process the holes if present
  if (any(!tabs$b$island_)) {
    ## filter out all the hole geometry and build an sp polygon object with it
    ## this 
    ##   filters all the branches that are holes
    ##   joins on the vertex instance index
    ##   joins on the vertex values
    ##   recomposes a SpatialPolygonsDataFrame using the spbabel::sp convention
    holes <- spbabel::sp(dplyr::inner_join(dplyr::inner_join(dplyr::filter_(tabs$b, quote(!island_)), tabs$bXv, "branch_"), 
                                           tabs$v, "vertex_"))
    ## centroid of every triangle
    centroids <- matrix(unlist(lapply(split(tr$P[t(tr$T), ], rep(seq(nrow(tr$T)), each = 3)), .colMeans, 3, 2)), 
                        ncol = 2, byrow = TRUE)
    ## sp::over() is very efficient, but has to use high-level objects as input
    badtris <- !is.na(over(SpatialPoints(centroids), sp::geometry(holes)))
    ## presumably this will always be true inside this block (but should check some time)
    if (any(badtris)) tr$T <- tr$T[!badtris, ]
  }
  
  ## trace and remove any unused triangles
  ## the raw vertices with a unique vertex_ id
  tabs$v <- tibble::tibble(x_ = tr$P[,1], y_ = tr$P[,2], vertex_ = spbabel:::id_n(nrow(tr$P)))
  ## drop the path topology
  tabs$b <- tabs$bXv <- NULL
  ## add triangle topology
  tabs$t <- tibble::tibble(triangle_ = spbabel:::id_n(nrow(tr$T)), object_ = tabs$o$object_[1])
  tabs$tXv <- tibble::tibble(triangle_ = rep(tabs$t$triangle_, each = 3), 
                             vertex_ = tabs$v$vertex_[as.vector(t(tr$T))])
  
  tabs
}

#' @rdname rangl
#' @export
#' @section Warning:
#' rangl only checks for presence of triangle centres within
#' known holes, so this doesn't pick up examples of overlapping areas e.g. 
#' https://github.com/r-gris/rangl/issues/39
#' @importFrom sp geometry  over SpatialPoints proj4string CRS SpatialPolygonsDataFrame
#' @importFrom dplyr inner_join
#' @importFrom RTriangle pslg triangulate
#' @importFrom spbabel map_table
#' @importFrom tibble tibble
#' @importFrom methods slotNames
rangl.SpatialPolygons <- function(x, max_area = NULL, ...) {
  pr4 <- proj4string(x)
  x0 <- x
  ## kludge for non DataFrames
  if (! "data" %in% slotNames(x)) {
    dummy <- data.frame(row_number = seq_along(x))
    x <- sp::SpatialPolygonsDataFrame(x, dummy, match.ID = FALSE)
  }
  tabs <- spbabel::map_table(x)
  
  ll <- vector("list", nrow(tabs$o))
  for (i_obj in seq(nrow(tabs$o))) {
    tabs_i <- tabs; tabs_i$o <- tabs_i$o[i_obj, ]
    tabs_i <- semi_cascade(tabs_i)
    tt_i <- tri_mesh_map_table1(tabs_i, max_area = max_area)
    # plot.trimesh(tt_i)
    # scan("", 1L)
    # rgl::rgl.clear()
    ll[[i_obj]] <- tt_i
  }
  
  outlist <- vector("list", length(ll[[1]]))
  nms <- names(ll[[1]])
  names(outlist) <- nms
  for (i in seq_along(outlist)) {
    outlist[[i]] <- dplyr::bind_rows(lapply(ll, "[[", nms[i]))
  }
  
  ## renormalize the vertices
  allverts <- dplyr::inner_join(outlist$tXv, outlist$v, "vertex_")
  allverts$uvert <- as.integer(factor(paste(allverts$x_, allverts$y_, sep = "_")))
  allverts$vertex_ <- spbabel:::id_n(length(unique(allverts$uvert)))[allverts$uvert]
  outlist$tXv <- allverts[, c("triangle_", "vertex_")]
  outlist$v <- dplyr::distinct_(allverts,  "vertex_", .keep_all = TRUE)[, c("x_", "y_", "vertex_")]
  ## finally add longitude and latitude
  outlist$meta <- tibble::tibble(proj = pr4, x = "x_", y = "y_", ctime = format(Sys.time(), tz = "UTC"))
  class(outlist) <- "trimesh"
  outlist
}


ranglPoly <- function(x, max_area = NULL, ...) {
  pr4 <- proj4string(x)
  x0 <- x
  ## kludge for non DataFrames
  if (! "data" %in% slotNames(x)) {
    dummy <- data.frame(row_number = seq_along(x))
    x <- sp::SpatialPolygonsDataFrame(x, dummy, match.ID = FALSE)
  }
  tabs <- spbabel::map_table(x)
  
  outlist <- tri_mesh_map_table1(tabs, max_area = max_area)
  
    ## renormalize the vertices
  allverts <- dplyr::inner_join(outlist$tXv, outlist$v, "vertex_")
  allverts$uvert <- as.integer(factor(paste(allverts$x_, allverts$y_, sep = "_")))
  allverts$vertex_ <- spbabel:::id_n(length(unique(allverts$uvert)))[allverts$uvert]
  outlist$tXv <- allverts[, c("triangle_", "vertex_")]
  outlist$v <- dplyr::distinct_(allverts,  "vertex_", .keep_all = TRUE)[, c("x_", "y_", "vertex_")]
  ## finally add longitude and latitude
  outlist$meta <- tibble::tibble(proj = pr4, x = "x_", y = "y_", ctime = format(Sys.time(), tz = "UTC"))
  class(outlist) <- "trimesh"
  outlist
}

th3d <- function() {
  structure(list(vb = NULL, it = NULL, primitivetype = "triangle",
                 material = list(), normals = NULL, texcoords = NULL), .Names = c("vb",
                                                                                  "it", "primitivetype", "material", "normals", "texcoords"), class = c("mesh3d",
                                                                                                                                                        "shape3d"))
}

trimesh_cols <- function(n) {
  viridis::viridis(n)
}
