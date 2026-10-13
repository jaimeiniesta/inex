# R + the official ineapir package, used to cross-check Inex against the
# reference implementation published by the INE. See test/ineapir/README.md.
FROM rocker/r-ver:4

RUN install2.r --error --skipinstalled ineapir jsonlite

WORKDIR /work
