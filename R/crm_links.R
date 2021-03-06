#' Get full text links from a DOI
#'
#' @export
#' @param doi (character) A Digital Object Identifier (DOI). required.
#' @param type (character) One of 'xml', 'html', 'plain', 'pdf',
#' 'unspecified', or 'all' (default). required.
#' @param ... Named parameters passed on to [crul::HttpClient()]
#'
#' @details Note that this function is not vectorized.
#'
#' Some links returned will not in fact lead you to full text
#' content as you would understandbly think and expect. That is, if you
#' use the `filter` parameter with e.g., [rcrossref::cr_works()]
#' and filter to only full text content, some links may actually give back
#' only metadata for an article. Elsevier is perhaps the worst offender,
#' for one because they have a lot of entries in Crossref TDM, but most
#' of the links that are apparently full text are not in fact full text,
#' but only metadata. You can get full text if you are part of a subscribing
#' institution to that specific Elsever content, but otherwise, you're SOL.
#'
#' Note that there are still some bugs in the data returned form CrossRef.
#' For example, for the publisher eLife, they return a single URL with
#' content-type application/pdf, but the URL is not for a PDF, but for both
#' XML and PDF, and content-type can be set with that URL as either XML or
#' PDF to get that type.
#'
#' In another example, all Elsevier URLs at time of writing are have
#' `http` scheme, while those don't actually work, so we have a
#' custom fix in this function for that publisher. Anyway, expect changes...
#'
#' @section Register for the Polite Pool:
#' The `crm_links()` uses the
#' [Crossref API](https://github.com/CrossRef/rest-api-doc)
#' You should send your email address with your `crm_links()` requests. This
#' has the advantage that queries are placed in the polite pool of servers.
#' In addition, even if the non-polite pool is having server problems,
#' the polite pool is often okay. Including your email address is good practice
#' as described in the Crossref documentation under
#' [Good manners](https://github.com/CrossRef/rest-api-doc).
#' To pass your email address to Crossref, simply store it as an environment
#' variable in .Renviron file like `crossref_email=name@example.com`, or
#' `CROSSREF_EMAIL=name@example.com`.
#' Save the file and restart your R session. To stop sharing your email when
#' using rcrossref simply delete it from your `.Renviron` file OR to temporarily
#' not use your email unset it for the session
#' like `Sys.unsetenv('crossref_email')`. To be sure your in the polite pool
#' use curl verbose by e.g., `crm_links(doi = "10.5555/515151", verbose = TRUE)`
#'
#' @return `NULL` if no full text links given; a list of tdmurl objects if
#' links found. a tdmurl object is an S3 class wrapped around a simple list,
#' with attributes for:
#'
#' - type: type, matchin type passed to the function
#' - doi: DOI
#' - member: Crossref member ID
#' - intended_application: intended application, e.g., text-mining
#'
#' @examples \dontrun{
#' data(dois_crminer)
#'
#' # pdf link
#' crm_links(doi = "10.5555/515151", "pdf")
#'
#' # xml and plain text links
#' crm_links(dois_crminer[1], "pdf")
#' crm_links(dois_crminer[6], "xml")
#' crm_links(dois_crminer[7], "plain")
#' crm_links(dois_crminer[1]) # all is the default
#'
#' # pdf link
#' crm_links(doi = "10.5555/515151", "pdf")
#' crm_links(doi = "10.3897/phytokeys.52.5250", "pdf")
#'
#' # many calls, use e.g., lapply
#' lapply(dois_crminer[1:3], crm_links)
#'
#' # elsevier
#' ## DOI that is open acccess
#' crm_links('10.1016/j.physletb.2010.10.049')
#' ## DOI that is not open acccess
#' crm_links('10.1006/jeth.1993.1066')
#' }
crm_links <- function(doi, type = 'all', ...) {
  res <- crm_works_links(dois = doi, ...)[[1]]
  if (is.null(unlist(res$links))) {
    return(list())
  } else {
    elife <- grepl("elife", res$links[[1]]$URL)
    withtype <- if (type == 'all') {
      res$links
    } else {
      Filter(function(x) grepl(type, x$`content-type`), res$links)
    }

    if (is.null(withtype) || length(withtype) == 0) {
      return(list())
    } else {
      withtype <- stats::setNames(withtype, sapply(withtype, function(x){
        if (x$`content-type` == "unspecified") {
          "unspecified"
        } else {
          strsplit(x$`content-type`, "/")[[1]][[2]]
        }
      }))

      if (elife) {
        withtype <- Filter(function(w) !grepl("lookup", w$URL), withtype)
      }

      if (basename(res$member) == "2258") {
        withtype <- lapply(withtype, function(z) {
          z$URL <- sub("http://", "https://", z$URL)
          z
        })
      }

      if (basename(res$member) == "78") {
        withtype <- lapply(withtype, function(z) {
          z$URL <- sub("http://", "https://", z$URL)
          z
        })
        pdf <- list(pdf =
          utils::modifyList(withtype[[1]],
            list(
              URL = sub("text/xml", "application/pdf", withtype[[1]]$URL),
              `content-type` = "application/pdf"
            )
        ))
        withtype <- c(withtype, pdf)
      }

      if (type == "all") {
        lapply(withtype, function(b) {
          makeurl(b$URL, st(b$`content-type`), doi, res$member, b$`intended-application`)
        })
      } else {
        y <- match.arg(type, c('xml', 'plain', 'html', 'pdf', 'unspecified'))
        makeurl(x = withtype[[y]]$URL, y = y, z = doi, res$member,
          withtype[[y]]$`intended-application`)
      }
    }
  }
}

crm_works_links <- function(dois = NULL, ...) {
  get_links <- function(x, ...) {
    tmp <- crm_GET(sprintf("works/%s", x), NULL, FALSE, ...)
    trylinks <- tryCatch(tmp$message$link, error = function(e) e)
    if (inherits(trylinks, "error")) {
      NULL
    } else {
      list(links = trylinks, member = tmp$message$member)
    }
  }
  stats::setNames(lapply(dois, get_links, ...), dois)
}

st <- function(x){
  if (grepl("/", x)) {
    strsplit(x, "/")[[1]][[2]]
  } else {
    x
  }
}
