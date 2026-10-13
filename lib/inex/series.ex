defmodule Inex.Series do
  @moduledoc """
  Functions for the INE **series** endpoints.

  Series are the core element of the INE database (Tempus3): the only entity
  with data. Each series has a code like `"IPC290750"` (CPI, national, general
  index, annual change) and is defined by the values of several variables.

  You can find series codes:

    - in INEbase, by clicking on a series of a table
      (`https://www.ine.es/consul/serie.do?s=IPC290750`),
    - listing the series of a table with `Inex.Tables.series/2`,
    - filtering the series of an operation with `search/2`.

  > #### Discontinued series {: .warning}
  >
  > When the INE changes the base or the methodology of an operation, it
  > usually creates **new series codes** and stops updating the old ones,
  > which keep answering with their historical data and no warning. If a
  > series looks out of date (check `get/2` or the dates of the observations),
  > look for its current code with `search/2` or `Inex.Tables.series/2`.

  ## Endpoints

    - `get/2` - [`SERIE/{code}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1152) - Series metadata
    - `metadata/2` - [`VALORES_SERIE/{code}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1155) - Variables and values that define a series
    - `observations/2` - [`DATOS_SERIE/{code}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1129) - The data of a series
    - `observations_as_data_frame/2` - `DATOS_SERIE` for one or many series as an `Explorer.DataFrame`
    - `search/2` - [`SERIE_METADATAOPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100) - Series of an operation matching some filters
    - `search_observations/2` - [`DATOS_METADATAOPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100) - Data of the series of an operation matching some filters
    - `search_observations_as_data_frame/2` - `DATOS_METADATAOPERACION` as an `Explorer.DataFrame`
  """

  alias Explorer.DataFrame, as: DF
  alias Inex.Client
  alias Inex.Utils

  @get_schema Utils.schema([:language, :detail, :friendly, :metadata])
  @metadata_schema Utils.schema([:language, :detail])
  @observations_schema Utils.schema([
                         :language,
                         :detail,
                         :friendly,
                         :metadata,
                         :last,
                         :date_range
                       ])
  @observations_data_frame_schema Utils.schema([
                                    :language,
                                    :last,
                                    :date_range,
                                    {:metadata, false},
                                    {:format, :wide},
                                    :data_frame
                                  ])
  @search_schema Utils.schema([
                   :language,
                   :detail,
                   :friendly,
                   :metadata,
                   :operation_filters,
                   :periodicity,
                   {:page, 1}
                 ])
  @search_observations_schema Utils.schema([
                                :language,
                                :detail,
                                :friendly,
                                :metadata,
                                :operation_filters,
                                :periodicity,
                                :last,
                                :date_range,
                                {:page, 1}
                              ])
  @search_observations_data_frame_schema Utils.schema([
                                           :language,
                                           :operation_filters,
                                           :periodicity,
                                           :last,
                                           :date_range,
                                           {:page, 1},
                                           {:metadata, true},
                                           {:format, :long}
                                         ])

  @doc """
  Get the metadata of a series: name, operation, periodicity, publication,
  classification, unit, scale and number of decimals.

  ## Options

  #{NimbleOptions.docs(@get_schema)}

  ## Examples

      iex> Inex.Series.get("IPC290750")
      {:ok, %{"COD" => "IPC290750", "Nombre" => "Nacional. Índice general. Variación anual. ", "FK_Operacion" => 25, "FK_Periodicidad" => 1, ...}}

      iex> {:ok, %{"Periodicidad" => %{"Nombre" => "Mensual"}}} =
      ...>   Inex.Series.get("IPC290750", detail: 2, friendly: true)

      iex> {:error, %Inex.Error{type: :not_found}} = Inex.Series.get("NOPE")
  """
  @spec get(Inex.series_code(), keyword()) :: Client.response()
  def get(code, opts \\ []) do
    Utils.fetch("SERIE", [code], opts, @get_schema)
  end

  @doc """
  Get the variables and values that define a series.

  ## Options

  #{NimbleOptions.docs(@metadata_schema)}

  ## Examples

      iex> Inex.Series.metadata("IPC290750")
      {:ok, [%{"Id" => 16473, "FK_Variable" => 349, "Nombre" => "Nacional", "Codigo" => "00"}, ...]}

      iex> {:ok, [%{"Variable" => %{"Nombre" => "Totales Territoriales"}} | _]} =
      ...>   Inex.Series.metadata("IPC290750", detail: 1)
  """
  @spec metadata(Inex.series_code(), keyword()) :: Client.response()
  def metadata(code, opts \\ []) do
    Utils.fetch("VALORES_SERIE", [code], opts, @metadata_schema)
  end

  @doc """
  Get the observations (data) of a series.

  This is the primary function for retrieving time series data from the INE.
  When neither `:last` nor a date range are given, **all** the observations
  are returned (the INE API requires one of them, so Inex sends an open date
  range starting in 1800).

  ## Options

  #{NimbleOptions.docs(@observations_schema)}

  ## Examples

      iex> Inex.Series.observations("IPC290750", last: 2)
      {:ok,
       %{
         "COD" => "IPC290750",
         "Nombre" => "Nacional. Índice general. Variación anual. ",
         "FK_Unidad" => 135,
         "FK_Escala" => 1,
         "Data" => [
           %{"Fecha" => 1785535200000, "FK_Periodo" => 8, "Anyo" => 2026, "Valor" => 4.3, ...},
           %{"Fecha" => 1788213600000, "FK_Periodo" => 9, "Anyo" => 2026, "Valor" => 4.9, ...}
         ]
       }}

      iex> {:ok, %{"Data" => [_ | _]}} =
      ...>   Inex.Series.observations("IPC290750",
      ...>     observation_start: ~D[2024-01-01],
      ...>     observation_end: ~D[2024-12-31],
      ...>     friendly: true
      ...>   )

      # Several date ranges at once
      iex> {:ok, %{"Data" => [_, _, _]}} =
      ...>   Inex.Series.observations("IPC290750",
      ...>     dates: [~D[2024-01-01], ~D[2025-01-01], ~D[2026-01-01]]
      ...>   )

      iex> {:error, %Inex.Error{type: :option_error}} =
      ...>   Inex.Series.observations("IPC290750", last: 0)
  """
  @spec observations(Inex.series_code(), keyword()) :: Client.response()
  def observations(code, opts \\ []) do
    Utils.fetch("DATOS_SERIE", [code], opts, @observations_schema, ensure_data_range: true)
  end

  @doc """
  Same as `observations/2` except that it returns the observations inside of an
  `Explorer.DataFrame`. You can also pass a list of series codes: they are
  fetched concurrently and combined into a single data frame.

  By default the data frame is **wide**: a `date` column plus one column per
  series, named after the series code. Since series can have different dates
  (or periodicities), the `date` column holds the union of all the dates and
  series without data for a date get `nil`. Use `format: :long` to get one row
  per observation with the name, period, unit... of each series (see
  `Inex.DataFrame` for the columns).

  If any of the series cannot be fetched, the whole call returns the error.

  ## Options

  #{NimbleOptions.docs(@observations_data_frame_schema)}

  ## Examples

      iex> {:ok, df} = Inex.Series.observations_as_data_frame("IPC290750", last: 3)
      iex> df
      #Explorer.DataFrame<
        Polars[3 x 2]
        date date [2026-07-01, 2026-08-01, 2026-09-01]
        IPC290750 f64 [3.6, 4.3, 4.9]
      >

      # CPI (monthly) and unemployment rate (quarterly)
      iex> {:ok, df} =
      ...>   Inex.Series.observations_as_data_frame(["IPC290750", "EPA452434"],
      ...>     observation_start: ~D[2024-01-01],
      ...>     rename: %{"IPC290750" => "cpi", "EPA452434" => "unemployment"}
      ...>   )

      iex> {:ok, df} = Inex.Series.observations_as_data_frame(["IPC290750"], last: 12, format: :long)
  """
  @spec observations_as_data_frame(Inex.series_code() | [Inex.series_code()], keyword()) ::
          {:ok, DF.t()} | {:error, Inex.Error.t()}
  def observations_as_data_frame(codes, opts \\ [])

  def observations_as_data_frame(code, opts) when is_binary(code) do
    observations_as_data_frame([code], opts)
  end

  def observations_as_data_frame(codes, opts) when is_list(codes) do
    with {:ok, opts} <- Utils.validate_opts(opts, @observations_data_frame_schema),
         {:ok, payloads} <- fetch_many(codes, opts) do
      {:ok, Inex.DataFrame.build(payloads, opts)}
    end
  end

  @doc """
  Same as `observations_as_data_frame/2` but returns the data frame directly
  and raises an `Inex.Error` on failure.

  ## Examples

      iex> "IPC290750"
      ...> |> Inex.Series.observations_as_data_frame!(last: 12)
      ...> |> Explorer.DataFrame.print()
  """
  @spec observations_as_data_frame!(Inex.series_code() | [Inex.series_code()], keyword()) ::
          DF.t()
  def observations_as_data_frame!(codes, opts \\ []) do
    codes |> observations_as_data_frame(opts) |> Utils.bang!()
  end

  @doc """
  Get the series of an operation whose metadata match the given filters.

  This is how you find series codes without browsing INEbase: filter by the
  variables of the operation (see `Inex.Operations.variables/2`) and their
  values (see `Inex.Operations.variable_values/3`).

  ## Options

  #{NimbleOptions.docs(@search_schema)}

  ## Examples

      # CPI series for the province of Madrid (115:29), monthly change (3:84),
      # every ECOICOP group (762)
      iex> Inex.Series.search("IPC",
      ...>   filters: [{115, 29}, {3, 84}, {762, :all}],
      ...>   periodicity: :monthly
      ...> )
      {:ok, [%{"COD" => "IPC307289", "Nombre" => "Madrid. Información y comunicaciones. Variación mensual. ", ...}, ...]}

      # Same query with shortcuts
      iex> {:ok, _series} =
      ...>   Inex.Series.search("IPC",
      ...>     filters: [province: 29, data_type: 84, cpi_group: :all],
      ...>     periodicity: :monthly
      ...>   )
  """
  @spec search(Inex.operation_id(), keyword()) :: Client.response()
  def search(operation, opts \\ []) do
    Utils.fetch("SERIE_METADATAOPERACION", [operation], opts, @search_schema,
      filters_as: :operation
    )
  end

  @doc """
  Get the observations of the series of an operation whose metadata match the
  given filters. Combines `search/2` and `observations/2` in a single request.

  When neither `:last` nor a date range are given, all the observations are returned.

  ## Options

  #{NimbleOptions.docs(@search_observations_schema)}

  ## Examples

      # Last CPI annual change (3:74) of the general index (762:304092) for every province
      iex> Inex.Series.search_observations("IPC",
      ...>   filters: [data_type: 74, cpi_group: 304092, province: :all],
      ...>   periodicity: :monthly,
      ...>   last: 1
      ...> )
      {:ok, [%{"COD" => "IPC307255", "Nombre" => "Madrid. Índice general. Variación anual. ", "Data" => [...]}, ...]}
  """
  @spec search_observations(Inex.operation_id(), keyword()) :: Client.response()
  def search_observations(operation, opts \\ []) do
    Utils.fetch("DATOS_METADATAOPERACION", [operation], opts, @search_observations_schema,
      filters_as: :operation,
      ensure_data_range: true
    )
  end

  @doc """
  Same as `search_observations/2` except that it returns an `Explorer.DataFrame`.

  The data frame is **long** by default and includes one column per variable
  that defines the series (`metadata: true`), so you can filter or group by
  them. Use `format: :wide` for a `date` column plus one column per series.

  ## Options

  #{NimbleOptions.docs(@search_observations_data_frame_schema)}

  ## Examples

      iex> {:ok, df} =
      ...>   Inex.Series.search_observations_as_data_frame("IPC",
      ...>     filters: [data_type: 74, cpi_group: 304092, province: :all],
      ...>     periodicity: :monthly,
      ...>     last: 12
      ...>   )
      iex> Explorer.DataFrame.names(df)
      ["code", "name", "date", "year", "period", "value", "data_type", "unit", "scale",
       "Provincias", "Grupos ECOICOP", "Índices y Tasas"]
  """
  @spec search_observations_as_data_frame(Inex.operation_id(), keyword()) ::
          {:ok, DF.t()} | {:error, Inex.Error.t()}
  def search_observations_as_data_frame(operation, opts \\ []) do
    with {:ok, opts} <- Utils.validate_opts(opts, @search_observations_data_frame_schema),
         {:ok, payload} <- search_observations(operation, data_request_opts(opts)) do
      {:ok, Inex.DataFrame.build(payload, opts)}
    end
  end

  @doc """
  Same as `search_observations_as_data_frame/2` but returns the data frame
  directly and raises an `Inex.Error` on failure.
  """
  @spec search_observations_as_data_frame!(Inex.operation_id(), keyword()) :: DF.t()
  def search_observations_as_data_frame!(operation, opts \\ []) do
    operation |> search_observations_as_data_frame(opts) |> Utils.bang!()
  end

  defp fetch_many(codes, opts) do
    request_opts = data_request_opts(opts)

    codes
    |> Task.async_stream(
      fn code ->
        case observations(code, request_opts) do
          {:ok, payload} -> {:ok, payload}
          {:error, error} -> {:error, %{error | message: "#{code}: #{error.message}"}}
        end
      end,
      max_concurrency: opts[:max_concurrency],
      timeout: :infinity
    )
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, {:ok, payload}}, {:ok, payloads} -> {:cont, {:ok, [payload | payloads]}}
      {:ok, {:error, error}}, _acc -> {:halt, {:error, error}}
    end)
    |> case do
      {:ok, payloads} -> {:ok, Enum.reverse(payloads)}
      error -> error
    end
  end

  # Options for the underlying data functions: always friendly (readable
  # dates, units and data types), with metadata when requested.
  defp data_request_opts(opts) do
    opts
    |> Keyword.take([
      :language,
      :last,
      :observation_start,
      :observation_end,
      :dates,
      :filters,
      :periodicity,
      :page
    ])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.merge(friendly: true, metadata: opts[:metadata])
  end
end
