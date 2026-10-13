# Changelog

## v0.1.0

Initial release.

- Coverage of every function of the INE API JSON (`wstempus`), plus the undocumented
  `OPERACIONES_TABLA`, `PERIODICIDAD_OPERACION`, `PERIODOS_PERIODICIDAD`, `UNIDADES` and `ESCALAS`.
- Fred-like interface: `Inex.Series.observations/2` and `Inex.Series.observations_as_data_frame/2`.
- Explorer integration: wide and long (tidy) data frames with one column per metadata variable,
  conversion of metadata listings with `Inex.DataFrame.from_records/1`.
- Validated, documented options (`NimbleOptions`) translated into the INE parameters, filters with
  the variable shortcuts of the official `ineapir` R package, `page: :all` pagination.
- Normalization of the INE error responses into `Inex.Error`.
- Telemetry events and a built-in logger.
- Livebook notebooks.
- Test suite with recorded responses, integration tests and a cross-check against `ineapir`.
