# Cross-check against ineapir

[ineapir](https://github.com/es-ine/ineapir) is the official R client of the INE API. This
directory runs the same queries with ineapir and with Inex and compares the results: data values,
dates, periods, metadata and identifiers.

```sh
mix test --only ineapir
```

The test builds a Docker image with R and ineapir (`Dockerfile`), runs `queries.R` inside it and
compares its output with Inex calls made against the live API. Docker is the only requirement.

To iterate faster, run the R queries once and reuse their output:

```sh
docker build -t inex-ineapir test/ineapir
docker run --rm -v "$PWD/test/ineapir:/work" inex-ineapir Rscript queries.R output
INEAPIR_OUTPUT=$PWD/test/ineapir/output mix test --only ineapir
```
