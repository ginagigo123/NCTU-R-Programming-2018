#' Save a gganimate object to a file
#'
#' @param g A gganimate object
#' @param filename File to write to
#' @param saver A string such as "mp4" or "gif" that specifies
#' a function from the animation package such as \code{saveVideo}
#' to use for saving. GIFs are saved manually using ImageMagick.
#' @param ... Additional arguments passed on to the saving function,
#' such as \code[pkg=ggplot2]{ggsave} for GIFs or
#' \code[pkg=animate]{saveVideo} for MP4.
#'
#' @details If saving to a GIF, uses a custom method that takes advantage
#' of redundant backgrounds (scales, static layers, etc).
#'
#' @export
gganimate_save <- function(g, filename = NULL, saver = NULL,
                           fps = 1, loop = 0, ...) {
  # save to a temporary file if necessary
  if (is.null(filename)) {
    if (is.null(saver)) {
      filename <- gganimate_tempfile(fileext = ".gif")
    } else {
      filename <- gganimate_tempfile(fileext = paste0(".", saver))
    }
  }
  # figure out how it should be saved
  s <- animation_saver(saver, filename)
  # temporarily move to directory (may be current one, that's OK)
  # this helps with animation functions like saveGIF that work only in
  # current directory
  withr::with_dir(dirname(filename), {
    if (s$saver == "gif" && FALSE) {
      save_gganimate_custom(g, filename = filename, ...)
    } else {
      s$func(for (pl in g$plots) {
        plot_ggplot_build(pl)
      }, basename(filename), autobrowse = FALSE, ...)
    }
  })
  g$filename <- filename
  if (!is.null(s$mime_type)) {
    # if it can be displayed in R, import it as an encoded string
    g$src <- base64enc::dataURI(file = filename, mime = s$mime_type)
    g$mime_type <- s$mime_type
  }
  g$saved <- TRUE
  g
}
#' Retrieve a function for saving animations based on a string/function or a filename
#'
#' @param saver A function or string describing an animation saver
#' @param filename File name to save to
#' @param mime_type If saver is a custom function instead of a string
#' specification, can specify a mime_type to save it as. Without this,
#' files can be saved but not browsed in RStudio.
animation_saver <- function(saver, filename, mime_type = NULL) {
  if (is.function(saver)) {
    return(list(func = saver, mime_type = mime_type))
  }
  if (is.null(saver)) {
    saver <- tolower(tools::file_ext(filename))
  }
  savers <- list(gif = animation::saveGIF,
                 mp4 = animation::saveVideo,
                 webm = animation::saveVideo,
                 avi = animation::saveVideo,
                 html = function(expr, filename, ...) animation::saveHTML(expr, htmlfile = filename, ...),
                 tex = function(expr, filename, ...) animation::saveLatex(expr, latex.filename = filename, ...),
                 pdf = function(expr, filename, ...) animation::saveLatex(expr, latex.filename = gsub("pdf$", "tex", filename, perl = TRUE)),
                 swf = animation::saveSWF)
  if (is.null(savers[[saver]])) {
    stop("Don't know how to save animation of type ", saver)
  }
  # for those that can be viewed in RStudio, save the mime_type
  mime_types <- list(gif = "image/gif",
                     mp4 = "video/mp4",
                     webm = "video/webm",
                     avi = "video/avi")
  list(saver = saver, func = savers[[saver]], mime_type = mime_types[[saver]])
}
# utility:
save_gganimate_custom <- function(g, filename, clean = TRUE, ...) {
  blank <- g$plots[[1]]
  blank$data <- lapply(blank$data, function(d) utils::head(d, 0))
  blank$plot$labels$title <- " "
  blank_gtable <- ggplot2::ggplot_gtable(blank)
  # align all of the plots
  gtables <- lapply(g$plots, function(p) {
    p$plot$theme <- theme_void()
    ggplot2::ggplot_gtable(p)
  })
  gtables_aligned <- cowplot::align_plots(
    plotlist = c(list(blank_gtable), gtables),
    align = "hv")
  filenames <- paste0("plot", seq_along(gtables_aligned), ".png")
  for (i in seq_along(gtables_aligned)) {
    bg <- ifelse(i == 1, "white", "transparent")
    suppressMessages(ggsave(gtables_aligned[[i]],
                            filename = filenames[i],
                            bg = bg, ...))
  }
  command <- paste("convert -dispose none -delay 0 %s",
                   "-dispose previous -delay %d %s",
                   "-loop 0 %s")
  opts <- "-dispose none -delay 0 plot1.png -dispose previous"
  animation::im.convert(filenames[-1], basename(filename), extra.opts = opts,
                        clean = clean)
  unlink(filenames[1])
}
#' Create a temporary file within the temporary directory
#'
#' This is necessary because the animation package often copies
#' to the temporary directory, which leads to animation trying to
#' copy a file to itself.
#'
#' @param pattern the initial part of the name
#' @param fileext file extension
gganimate_tempfile <- function(pattern = "file", fileext = "") {
  outdir <- file.path(tempdir(), "gganimate")
  dir.create(outdir, showWarnings = FALSE)
  tempfile(pattern, outdir, fileext = fileext)
}
#' Plot a built ggplot object
#'
#' We needed a customized version of ggplot2's \code{print.ggplot2},
#' because we need to build plots from the intermediate results of
#' \code{\link{ggplot_build}} rather than from a \code{gg} object.
#'
#' @param b A list resulting from \code{\link{ggplot_build}}
#' @param newpage draw new (empty) page first?
#' @param vp viewport to draw plot in
plot_ggplot_build <- function(b, newpage = is.null(vp), vp = NULL) {
  if (newpage) {
    grid::grid.newpage()
  }
  grDevices::recordGraphics(
    requireNamespace("ggplot2", quietly = TRUE),
    list(),
    getNamespace("ggplot2")
  )
  gtable <- ggplot_gtable(b)
  # browser()
  if (is.null(vp)) {
    grid::grid.draw(gtable)
  } else {
    if (is.character(vp)) grid::seekViewport(vp) else grid::pushViewport(vp)
    grid::grid.draw(gtable)
    grid::upViewport()
  }
}
#' Auto browse to a filename
#'
#' This utility function is adapted from the animation package
#' \url{https://github.com/yihui/animation/blob/df12e57b3cb1a71a1935f5351e007d141af8ae2c/R/utils.R}
#'
#' @param output Open a file
auto_browse = function(output){
  if (.Platform$OS.type == 'windows') {
    try(shell.exec(output))
  } else if (Sys.info()['sysname'] == 'Darwin') {
    system(paste('open ', shQuote(output)))
  } else system(paste('xdg-open ', shQuote(output)))
}
#' Show an animation of a ggplot2 object
#'
#' Show an animation of a ggplot2 object that contains a \code{frame} aesthetic. This
#' \code{frame} aesthetic will determine which frame the animation is shown in. For
#' example, you could add the aesthetic \code{frame = time} to a dataset including
#' a \code{time} variable. Each distinct value of the frame aesthetic is rendered
#' into one frame of the resulting animation, in sorted order.
#'
#' If \code{cumulative = TRUE} is set within a layer along with a \code{frame} aesthetic,
#' the frames build cumulatively rather than each being generated with separate data.
#'
#' @param p A ggplot2 object. If no plot is provided, use the last plot by default.
#' @param filename Optionally, an output file to save to. If not given, will
#' store as plots without (yet) saving to a file
#' @param saver A string such as "mp4" or "gif" that specifies
#' a function from the animation package such as \code{saveVideo}
#' or \code{saveGIF} to use for saving. This can also be recognized from the
#' filename extension.
#' @param title_frame Whether to title each image with the current \code{frame} value.
#' The value is appended on to any existing title.
#' @param ... If saving to a file, extra arguments to pass along to the animation
#' saving function (to \code{saveVideo}/\code{saveGIF}/etc).
#'
#' @import ggplot2
#'
#' @examples
#'
#' library(ggplot2)
#' library(gapminder)
#'
#' p <- ggplot(gapminder, aes(gdpPercap, lifeExp, size = pop, color = continent, frame = year)) +
#'   geom_point() +
#'   scale_x_log10()
#'
#' p
#'
#' gganimate(p)
#'
#' \dontrun{
#' gganimate(p, "output.gif")
#' gganimate(p, "output.mp4")
#' }
#'
#' # You can also create cumulative graphs by adding the `cumulative = TRUE` aesthetic.
#' # For example, we could show the progression of temperature over time.
#'
#' aq <- airquality
#' aq$date <- as.Date(paste(1973, aq$Month, aq$Day, sep = "-"))
#'
#' p2 <- ggplot(aq, aes(date, Temp, frame = Month, cumulative = TRUE)) +
#'   geom_line()
#'
#' gganimate(p2, title_frame = FALSE)
#'
#'
#' @export
gganimate <- function(p = last_plot(), filename = NULL,
                       saver = NULL, title_frame = TRUE, ...) {
  if (is.null(p)) {
    stop("no plot to animate")
  }
  built <- ggplot_build(p)
  # get frames
  frames <- plyr::compact(lapply(built$data, function(d) d$frame))
  if (length(frames) == 0) {
    stop("No frame aesthetic found; cannot create animation")
  }
  if (is.factor(frames[[1]])) {
    # for factors, have to use unlist to combine
    frames <- sort(unique(unlist(frames)))
  } else {
    frames <- sort(unique(do.call(c, frames)))
  }
  frames <- sort(unique(frames))
  plots <- lapply(frames, function(f) {
    # replace each data object with a subset
    b <- built
    for (i in seq_along(b$data)) {
      frame_vec <- b$data[[i]]$frame
      if (!is.null(frame_vec)) {
        sub <- (frame_vec == f | is.na(frame_vec))
        if (!is.null(b$data[[i]]$cumulative)) {
          sub <- sub | (b$data[[i]]$cumulative & (frame_vec <= f))
        }
        b$data[[i]] <- b$data[[i]][sub, ]
      }
    }
    # title plot according to frame
    if (title_frame) {
      if (!is.null(b$plot$labels$title)) {
        b$plot$labels$title <- paste(b$plot$labels$title, f)
      } else {
        b$plot$labels$title <- f
      }
    }
    b
  })
  ret <- list(plots = plots, frames = frames)
  class(ret) <- "gganimate"
  if (!is.null(filename)) {
    ret <- gganimate_save(ret, filename, saver, ...)
  } else {
    ret$ani_opts <- list(...)
    ret$saved <- FALSE
  }
  ret
}
#' Print a gganimate object, allowing browsing in RStudio
#'
#' Print a gganimate object as browsable HTML, which allows visualization
#' directly in RStudio. If we are in knitr, directly print each of the
#' images instead (you should use the \code{fig.show = "animate"} option
#' in the chunk).
#'
#' @param x gganimate object
#' @param format What format to display in, such as "gif" (default),
#' "mp4", or "avi".
#' @param ... Extra arguments for the <img> or <video> tag, such
#' as width or height
#'
#' This saves the plot to a file using \code{\link{gganimate_save}}
#' (and then loads the contents of that file into memory) if it has
#' not already been saved.
#'
#' @export
print.gganimate <- function(x, format = "gif", ...) {
  # if knitr is running, use a special case. Print all figures
  if (!(is.null(getOption("knitr.in.progress")))) {
    # don't print if it has already been saved
    if (!x$saved) {
      for (pl in x$plots) {
        plot_ggplot_build(pl)
      }
    }
    return()
  }
  # if it has not yet been saved to a file, save now (to a temporary file)
  if (!x$saved) {
    x <- do.call(gganimate_save, c(list(x, saver = format), x$ani_opts))
  }
  # construct HTML
  if (!is.null(x$mime_type) && grepl("^video", x$mime_type)) {
    d <- htmltools::tags$video(htmltools::tags$source(src = x$src),
                               autoplay = TRUE,
                               loop = TRUE, ...)
  } else if (!is.null(x$mime_type) && grepl("^image", x$mime_type)) {
    d <- htmltools::tags$img(src = x$src, ...)
  } else {
    message("opening gganimate file stored at ", x$filename)
    auto_browse(x$filename)
    return()
  }
  print(htmltools::browsable(d))
}
library(ggplot2)
library(gapminder)
p <- ggplot(gapminder, aes(gdpPercap, lifeExp, size = pop, color = continent, frame = year)) +
 geom_point() +
 scale_x_log10()
gganimate(p)
gganimate(p)

library(ggplot2)
library(gapminder)
p <- ggplot(gapminder, aes(gdpPercap, lifeExp, size = pop, color = continent, frame = year)) +
  geom_point() +
  scale_x_log10()
p
gganimate(p)

# You can also create cumulative graphs by adding the `cumulative = TRUE` aesthetic.
# For example, we could show the progression of temperature over time.


library(gapminder)
library(ggplot2)
library(gganimate)
aq <- airquality
aq$date <- as.Date(paste(1973, aq$Month, aq$Day, sep = "-"))
p2 <- ggplot(aq, aes(date, Temp, frame = Month, cumulative = TRUE)) +
  geom_line()
gganimate(p2, title_frame = FALSE)
}

library(gapminder)
library(ggplot2)
library(gganimate)
gganimate(p)
p
install.packages('animation')
gganimate(p)



