# Inex

An Elixir client for the [INE API JSON](https://www.ine.es/dyngs/DAB/index.htm?cid=1099), the open
data service of Spain's National Statistics Institute (*Instituto Nacional de Estadística*), powered
by [Req](https://hexdocs.pm/req) and integrated with [Explorer](https://hexdocs.pm/explorer).

> **Inex is not an official INE library.** It is an independent open source project, not
> developed, endorsed or supported by the INE. The official client published by the INE is
> [ineapir](https://github.com/es-ine/ineapir), for R.

The INE API gives access to everything published in INEbase: consumer prices (IPC), the labour force
survey (EPA), quarterly national accounts (GDP), population, tourism, housing prices and much more.
It is free and does **not** require an API key.

Inex follows the design of [Fred](https://hex.pm/packages/fred), the Elixir client for the Federal
Reserve Economic Data API, and has been cross-checked against
[ineapir](https://github.com/es-ine/ineapir), the official R package published by the INE.

## Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Finding Data](#finding-data)
- [Explorer Integration](#explorer-integration)
- [API Coverage](#api-coverage)
- [Livebook Notebooks](#livebook-notebooks)
- [Configuration](#configuration)
- [Telemetry](#telemetry)
- [Testing](#testing)

## Installation

Add `inex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:inex, "~> 0.1.0"}
  ]
end
```

Or in Livebook:

```elixir
Mix.install([{:inex, "~> 0.1.0"}])
```

## Quick Start

Get the latest observations of a series:

```elixir
iex> Inex.Series.observations("IPC290750", last: 2, friendly: true)
{:ok,
 %{
   "COD" => "IPC290750",
   "Nombre" => "Nacional. Índice general. Variación anual. ",
   "T3_Unidad" => "Tasas",
   "Data" => [
     %{"Anyo" => 2026, "Fecha" => "2026-08-01T00:00:00.000+02:00", "T3_Periodo" => "M08", "T3_TipoDato" => "Definitivo", "Valor" => 4.3},
     %{"Anyo" => 2026, "Fecha" => "2026-09-01T00:00:00.000+02:00", "T3_Periodo" => "M09", "T3_TipoDato" => "Avance", "Valor" => 4.9}
   ],
   ...
 }}
```

Or get several series into an `Explorer.DataFrame`, one column per series, just like
`Fred.Series.observations_as_data_frame/2`. Here: CPI annual change (monthly), unemployment rate
and GDP annual growth (quarterly):

```elixir
iex> ["IPC290750", "EPA452434", "CNTR6654"]
...> |> Inex.Series.observations_as_data_frame!(observation_start: ~D[2025-01-01])
...> |> Explorer.DataFrame.print(limit: 10, limit_dots: :bottom)
+-----------------------------------------------+
|  Explorer DataFrame: [rows: 21, columns: 4]   |
+------------+-----------+-----------+----------+
|    date    | IPC290750 | EPA452434 | CNTR6654 |
|   <date>   |   <f64>   |   <f64>   |  <f64>   |
+============+===========+===========+==========+
| 2025-01-01 | 2.9       | 11.36     | 2.8898   |
| 2025-02-01 | 3.0       | nil       | nil      |
| 2025-03-01 | 2.3       | nil       | nil      |
| 2025-04-01 | 2.2       | 10.29     | 2.6156   |
| 2025-05-01 | 2.0       | nil       | nil      |
| 2025-06-01 | 2.3       | nil       | nil      |
| 2025-07-01 | 2.7       | 10.45     | 2.3972   |
| 2025-08-01 | 2.7       | nil       | nil      |
| 2025-09-01 | 3.0       | nil       | nil      |
| 2025-10-01 | 3.1       | 9.93      | 2.4716   |
| …          | …         | …         | …        |
+------------+-----------+-----------+----------+
```

Every endpoint function returns `{:ok, decoded_json}` (with the INE's Spanish field names) or
`{:error, %Inex.Error{}}`. The `*_as_data_frame` functions return `{:ok, data_frame}` and have bang
variants (`observations_as_data_frame!/2`) that raise instead, handy for Livebook pipelines.

## Finding Data

INEbase is organised in **operations** (the CPI is `"IPC"`, the labour force survey `"EPA"`...),
which contain **tables**, which contain **series**. Series are defined by the **values** of some
**variables** (province, type of data...), which can be used to filter tables and operations.

```elixir
# 1. Find the operation and its tables
{:ok, operations} = Inex.Operations.list()
{:ok, tables} = Inex.Operations.tables("IPC")

# 2. Discover the variables and values of a table
{:ok, values} = Inex.Tables.values(76136)
values |> Inex.DataFrame.from_records() |> Explorer.DataFrame.print()

# 3. Get the data you need, filtering by variable/value ids
Inex.Tables.observations_as_data_frame!(76136,
  filters: [{3, 74}, {762, 304092}, {70, :all}],   # annual change, general index, every region
  last: 12
)

# Or with the shortcuts borrowed from ineapir
Inex.Tables.observations_as_data_frame!(76136,
  filters: [data_type: 74, cpi_group: 304092, ccaa: :all],
  last: 12
)

# 4. Or filter the series of a whole operation
# Madrid is the value with Id 29 of the provinces variable (its official INE code is "28")
Inex.Series.search("IPC", filters: [province: 29, data_type: 84, cpi_group: :all], periodicity: :monthly)
```

Table ids are the `t` parameter of INEbase URLs (`https://www.ine.es/jaxiT3/Tabla.htm?t=76136`). PC-Axis
(`"t20/e245/p08/l0/01001.px"`) and tpx (`33387`) tables are supported too, filtering by codes:
`filters: [{"sexo", "mujeres"}]`. See `Inex.Filters` for all the details.

> **Discontinued series.** When the INE changes the base or methodology of an operation it usually
> creates new series codes and stops updating the old ones, which keep answering with historical data
> and no warning. Many codes in the INE documentation (`IPC251852`, `EPA815`...) are in that
> situation. Check the date of the last observation and look for current codes with
> `Inex.Series.search/2` or `Inex.Tables.series/2`.

## Explorer Integration

`Inex.DataFrame` converts INE responses into data frames:

- **Wide** (default for `Inex.Series.observations_as_data_frame/2`): a `date` column plus one column
  per series.
- **Long/tidy** (default for tables and operations): one row per observation with `code`, `name`,
  `date`, `year`, `period`, `value`, `data_type`, `unit`, `scale` plus **one column per variable**
  that defines the series, so you can filter and group by any dimension:

```elixir
iex> Inex.Tables.observations_as_data_frame!(76136,
...>   filters: [data_type: 74, cpi_group: 304092, ccaa: :all],
...>   last: 2
...> )
...> |> Explorer.DataFrame.select(["code", "date", "value", "data_type", "Comunidades y Ciudades Autónomas"])
...> |> Explorer.DataFrame.print(limit: 5, limit_dots: :bottom)
+--------------------------------------------------------------------------------+
|                   Explorer DataFrame: [rows: 19, columns: 5]                   |
+-----------+------------+-------+------------+----------------------------------+
|   code    |    date    | value | data_type  | Comunidades y Ciudades Autónomas |
| <string>  |   <date>   | <f64> |  <string>  |             <string>             |
+===========+============+=======+============+==================================+
| IPC293659 | 2026-08-01 | 4.0   | Definitivo | Andalucía                        |
| IPC293715 | 2026-08-01 | 3.9   | Definitivo | Aragón                           |
| IPC293771 | 2026-08-01 | 3.9   | Definitivo | Asturias, Principado de          |
| IPC293827 | 2026-08-01 | 4.4   | Definitivo | Balears, Illes                   |
| IPC293883 | 2026-08-01 | 3.8   | Definitivo | Canarias                         |
| …         | …          | …     | …          | …                                |
+-----------+------------+-------+------------+----------------------------------+
```

Dates are converted to the calendar date in Madrid (the INE sends midnight in Madrid as epoch
milliseconds) and derived from the year and period when the INE does not send them (old
observations, PC-Axis and tpx tables). Metadata listings (operations, tables, values...) can be
converted with `Inex.DataFrame.from_records/1`.

## API Coverage

Every function of the INE API JSON is covered, plus five functions that are not in the official
reference (marked with \*), three of them used by the official R package.

| Module                  | Function                       | INE function                                    |
| ----------------------- | ------------------------------ | ----------------------------------------------- |
| `Inex.Operations`       | `list/1`                       | `OPERACIONES_DISPONIBLES`                       |
|                         | `get/2`                        | `OPERACION`                                     |
|                         | `variables/2`                  | `VARIABLES_OPERACION`                           |
|                         | `variable_values/3`            | `VALORES_VARIABLEOPERACION`                     |
|                         | `tables/2`                     | `TABLAS_OPERACION`                              |
|                         | `series/2`                     | `SERIES_OPERACION`                              |
|                         | `classifications/2`            | `CLASIFICACIONES_OPERACION`                     |
|                         | `publications/2`               | `PUBLICACIONES_OPERACION`                       |
|                         | `periodicities/2`              | `PERIODICIDAD_OPERACION`\*                      |
| `Inex.Series`           | `get/2`                        | `SERIE`                                         |
|                         | `metadata/2`                   | `VALORES_SERIE`                                 |
|                         | `observations/2`               | `DATOS_SERIE`                                   |
|                         | `observations_as_data_frame/2` | `DATOS_SERIE` → `Explorer.DataFrame`            |
|                         | `search/2`                     | `SERIE_METADATAOPERACION`                       |
|                         | `search_observations/2`        | `DATOS_METADATAOPERACION`                       |
|                         | `search_observations_as_data_frame/2` | `DATOS_METADATAOPERACION` → `Explorer.DataFrame` |
| `Inex.Tables`           | `observations/2`               | `DATOS_TABLA`                                   |
|                         | `observations_as_data_frame/2` | `DATOS_TABLA` → `Explorer.DataFrame`            |
|                         | `series/2`                     | `SERIES_TABLA`                                  |
|                         | `groups/2`                     | `GRUPOS_TABLA`                                  |
|                         | `group_values/3`               | `VALORES_GRUPOSTABLA`                           |
|                         | `values/2`                     | all the variables and values of a table         |
|                         | `operation/2`                  | `OPERACIONES_TABLA`\*                           |
| `Inex.Variables`        | `list/1`                       | `VARIABLES`                                     |
|                         | `values/2`                     | `VALORES_VARIABLE`                              |
|                         | `children/3`                   | `VALORES_HIJOS`                                 |
| `Inex.Publications`     | `list/1`                       | `PUBLICACIONES`                                 |
|                         | `dates/2`                      | `PUBLICACIONFECHA_PUBLICACION`                  |
| `Inex.Classifications`  | `list/1`                       | `CLASIFICACIONES`                               |
| `Inex.Periodicities`    | `list/1`                       | `PERIODICIDADES`                                |
|                         | `periods/2`                    | `PERIODOS_PERIODICIDAD`\*                       |
| `Inex.Units`            | `list/1`                       | `UNIDADES`\*                                    |
| `Inex.Scales`           | `list/1`                       | `ESCALAS`\*                                     |

The INE parameters are exposed as idiomatic, validated options:

| Inex option                             | INE parameter      |
| --------------------------------------- | ------------------ |
| `language: :en`                         | `/EN/` (default `:es`) |
| `detail: 0..2`                          | `det`              |
| `friendly: true` / `metadata: true`     | `tip=A` / `tip=M` / `tip=AM` |
| `last: n`                               | `nult`             |
| `observation_start:`, `observation_end:`, `dates:` | `date=yyyymmdd:yyyymmdd` |
| `filters:`                              | `tv` (tables), `g1`, `g2`... (operations) |
| `periodicity: :monthly`                 | `p`                |
| `geo: :national \| :regional`           | `geo`              |
| `classification: id`                    | `clasif`           |
| `page: n \| :all`                       | `page`             |

## Livebook Notebooks

The `livebooks/` directory contains interactive [Livebook](https://livebook.dev) notebooks with
[VegaLite](https://hexdocs.pm/vega_lite) charts:

| Notebook                                                                | Description                                                          |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------- |
| [`1_getting_started.livemd`](./livebooks/1_getting_started.livemd)      | Series, observations, date ranges, wide data frames and first charts |
| [`2_exploring_inebase.livemd`](./livebooks/2_exploring_inebase.livemd)  | Operations, tables, variables and values, filters, tidy data frames  |
| [`3_spanish_economy.livemd`](./livebooks/3_spanish_economy.livemd)      | CPI by region, unemployment and GDP: comparisons and heatmaps        |

## Configuration

No configuration is needed. Optionally:

```elixir
config :inex,
  language: :es,      # Default language of the responses (:es or :en)
  timeout: 60_000,    # Receive timeout of each request in milliseconds
  req_options: []     # Extra Req options: retries, proxies, test plugs...
```

## Telemetry

Inex emits `[:inex, :request, :start | :stop | :exception]` [telemetry](https://hexdocs.pm/telemetry)
events for every request. The quickest way to see what is going on is the built-in logger:

```elixir
Inex.Telemetry.Logger.attach()
```

```
[info] [inex] GET DATOS_SERIE/IPC290750 - 200 in 142ms (params: [tip: "A", nult: 12])
[info] [inex] GET SERIE/NOPE - error in 83ms: (HTTP 200) The INE API returned an empty response...
```

See `Inex.Telemetry` for the details of each event.

## Testing

```sh
mix test                          # Unit tests, using real responses recorded from the API
mix test --include integration    # Also run the tests against the live INE API
mix test --only ineapir           # Cross-check against the official R package (requires Docker)
```

The `ineapir` suite runs the same queries with [ineapir](https://github.com/es-ine/ineapir) (in a
Docker container, see `test/ineapir`) and with Inex against the live API, and compares data, dates,
metadata and identifiers.

## Acknowledgements

- [Fred](https://github.com/akoutmos/fred), whose interface Inex follows.
- [ineapir](https://github.com/es-ine/ineapir) and its
  [tutorial](https://github.com/es-ine/tutorial-ineapir), the official R package of the INE, used as
  reference implementation.
- Data © [INE](https://www.ine.es), published under
  [CC BY 4.0](https://www.ine.es/dyngs/AYU/index.htm?cid=125).

## License

MIT

## Artificial Intelligence

Contributions made with the help of AI tools are welcome. However, every issue and pull request
must be created and supervised by a human, who is responsible for its content and for following up
on the review.

AI coding agents will find instructions about this repository in [AGENTS.md](https://github.com/jaimeiniesta/inex/blob/master/AGENTS.md).
