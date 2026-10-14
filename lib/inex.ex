defmodule Inex do
  @moduledoc """
  Elixir client for the [INE API JSON](https://www.ine.es/dyngs/DAB/index.htm?cid=1099),
  the open data service of Spain's National Statistics Institute
  (*Instituto Nacional de Estadística*).

  The API gives access to all the statistics published in
  [INEbase](https://www.ine.es/inebmenu/indice.htm): consumer prices (IPC),
  labour force survey (EPA), quarterly national accounts (GDP), population,
  tourism, housing prices and many more. It is free and does **not** require
  an API key.

  See the [demo](https://jaimeiniesta.com/en/inex): Spain in charts, each
  chart with the Inex call that fetched its data.

  ## Run Your First Query

      iex> Inex.Series.observations("IPC290750", last: 2, friendly: true)
      {:ok,
       %{
         "COD" => "IPC290750",
         "Nombre" => "Nacional. Índice general. Variación anual. ",
         "T3_Unidad" => "Tasas",
         "Data" => [
           %{"Anyo" => 2026, "Fecha" => "2026-08-01T00:00:00.000+02:00", "T3_Periodo" => "M08", "Valor" => 4.3, ...},
           %{"Anyo" => 2026, "Fecha" => "2026-09-01T00:00:00.000+02:00", "T3_Periodo" => "M09", "Valor" => 4.9, ...}
         ],
         ...
       }}

  Or straight into an `Explorer.DataFrame`, one column per series:

      iex> Inex.Series.observations_as_data_frame!(["IPC290750", "EPA452434"],
      ...>   observation_start: ~D[2025-01-01]
      ...> )
      #Explorer.DataFrame<
        Polars[21 x 3]
        date date [2025-01-01, 2025-02-01, ...]
        IPC290750 f64 [2.9, 3.0, ...]
        EPA452434 f64 [11.36, nil, ...]
      >

  ## Concepts

  INEbase is organised around a few entities, each one with its own module:

    - **Operations** (`Inex.Operations`) - statistical operations such as the
      CPI (`"IPC"`) or the Labour Force Survey (`"EPA"`). They can be
      identified by their numeric Tempus3 id (`25`), alphabetic code (`"IPC"`)
      or IOE code (`"IOE30138"`).
    - **Tables** (`Inex.Tables`) - groups of series published together, the
      ones you see in INEbase. Their id is the `t` parameter of
      `https://www.ine.es/jaxiT3/Tabla.htm?t=76136`.
    - **Series** (`Inex.Series`) - the time series themselves, the only entity
      with data. Identified by codes like `"IPC290750"`.
    - **Variables and values** (`Inex.Variables`) - the dimensions that define
      a series (province, sex, type of data...) and their possible values.
      They are used to filter tables and operations (see `Inex.Filters`).
    - **Publications** (`Inex.Publications`), **classifications**
      (`Inex.Classifications`), **periodicities** (`Inex.Periodicities`),
      **units** (`Inex.Units`) and **scales** (`Inex.Scales`).

  ## Return values

  Every endpoint function returns `{:ok, decoded_json}` with the JSON exactly
  as returned by the INE (Spanish field names such as `"Nombre"`, `"Codigo"`,
  `"Valor"`), or `{:error, %Inex.Error{}}`. The `*_as_data_frame` functions
  return `{:ok, %Explorer.DataFrame{}}` and have bang (`!`) variants that
  raise `Inex.Error` instead, which is handy in Livebook pipelines.

  ## Common options

  Most functions accept these options, translated into the INE query parameters:

  | Inex option                              | INE parameter | Notes                                   |
  | ---------------------------------------- | ------------- | --------------------------------------- |
  | `language: :en`                          | `/EN/`        | `:es` (default) or `:en`                |
  | `detail: 2`                              | `det=2`       | `0`, `1` or `2`                         |
  | `friendly: true`                         | `tip=A`       | readable dates and names                |
  | `metadata: true`                         | `tip=M`       | variables and values of each series     |
  | `last: 12`                               | `nult=12`     | last `n` periods                        |
  | `observation_start:`/`observation_end:`  | `date=`       | `Date` structs                          |
  | `filters: [{3, 74}]`                     | `tv=3:74`     | tables, see `Inex.Filters`              |
  | `filters: [{3, 74}]`                     | `g1=3:74`     | operations, see `Inex.Filters`          |
  | `periodicity: :monthly`                  | `p=1`         | operations                              |
  | `geo: :regional`                         | `geo=1`       | operations and tables listings          |
  | `page: 2` / `page: :all`                 | `page=2`      | paginated listings                      |

  ## Configuration

  No configuration is required. Optionally:

  ```elixir
  config :inex,
    language: :es,       # Default language of the responses (:es or :en)
    timeout: 60_000,     # Receive timeout of each request in milliseconds
    req_options: []      # Extra options for Req (retries, proxies, test plugs...)
  ```

  See `Inex.Client` for details.

  ## Telemetry

  Inex emits `[:inex, :request, :start | :stop | :exception]` telemetry events
  for every HTTP request. For quick observability attach the built-in logger:

  ```elixir
  Inex.Telemetry.Logger.attach()
  ```

  See `Inex.Telemetry` for the details of each event.
  """

  @typedoc """
  Identifier of a statistical operation: the Tempus3 numeric id (`25`), the
  Tempus3 alphabetic code (`"IPC"`) or the IOE code (`"IOE30138"`).
  """
  @type operation_id :: String.t() | pos_integer()

  @typedoc """
  Identifier of a table: a Tempus3 id (`76136`), a tpx id (`33387`) or a
  PC-Axis path (`"t20/e245/p08/l0/01001.px"`).
  """
  @type table_id :: String.t() | pos_integer()

  @typedoc "Code of a Tempus3 series, e.g. `\"IPC290750\"`."
  @type series_code :: String.t()
end
