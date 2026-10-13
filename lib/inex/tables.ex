defmodule Inex.Tables do
  @moduledoc """
  Functions for the INE **tables** endpoints.

  Tables are groups of series published together in INEbase, defined by
  crossing the values of several variables. Their data can come from three
  different sources, and so can their identifiers:

    - **Tempus3** tables: the `t` parameter of
      `https://www.ine.es/jaxiT3/Tabla.htm?t=76136` → `76136`
    - **PC-Axis** tables: the `path` and `file` parameters of
      `https://www.ine.es/jaxi/Tabla.htm?path=/t20/e245/p08/l0/&file=01001.px`
      concatenated → `"t20/e245/p08/l0/01001.px"`
    - **tpx** tables: the `tpx` parameter of
      `https://www.ine.es/jaxi/Tabla.htm?tpx=33387` → `33387`

  You can also list the tables of an operation with `Inex.Operations.tables/2`.

  ## Endpoints

    - `observations/2` - [`DATOS_TABLA/{id}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1128) - The data of a table
    - `observations_as_data_frame/2` - `DATOS_TABLA` as an `Explorer.DataFrame`
    - `series/2` - [`SERIES_TABLA/{id}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1156) - Series of a table
    - `groups/2` - [`GRUPOS_TABLA/{id}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1150) - Groups (selection combos) of a Tempus3 table
    - `group_values/3` - [`VALORES_GRUPOSTABLA/{id}/{group}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1151) - Values of a group
    - `values/2` - all the variables and values of a table, ready to build `:filters`
    - `operation/2` - `OPERACIONES_TABLA/{id}` - Operation a table belongs to
      (not in the official reference, used by the official `ineapir` R package)

  ## Filtering

  Large tables can be filtered with the `:filters` option (`tv` parameter).
  Use `values/2` to discover the variables and values of a table:

      iex> {:ok, values} = Inex.Tables.values(76136)
      iex> values |> Inex.DataFrame.from_records() |> Explorer.DataFrame.select(["Id", "Nombre", "Variable.Id", "Variable.Nombre"])

      iex> Inex.Tables.observations_as_data_frame!(76136,
      ...>   filters: [data_type: 74, cpi_group: 304092, ccaa: :all],
      ...>   last: 12
      ...> )

  See `Inex.Filters` for the details for each kind of table.
  """

  alias Explorer.DataFrame, as: DF
  alias Inex.Client
  alias Inex.Error
  alias Inex.Utils

  @observations_schema Utils.schema([
                         :language,
                         :detail,
                         :friendly,
                         :metadata,
                         :last,
                         :date_range,
                         :table_filters
                       ])
  @observations_data_frame_schema Utils.schema([
                                    :language,
                                    :last,
                                    :date_range,
                                    :table_filters,
                                    {:metadata, true},
                                    {:format, :long}
                                  ])
  @series_schema Utils.schema([:language, :detail, :friendly, :metadata, :table_filters])
  @groups_schema Utils.schema([:language])
  @group_values_schema Utils.schema([:language, :detail])
  @values_schema Utils.schema([:language])
  @operation_schema Utils.schema([:language])

  @doc """
  Get the observations (data) of all the series of a table.

  Returns a list of series, each one with its `"Data"`. Without `:last` or a
  date range, all the periods are returned, which can be a lot of data for big
  tables: consider using `:filters`.

  Note that `:last` counts the periods of the **table**, not of each series.
  When the INE publishes a flash estimate (*avance*) only some series have
  data for the most recent period (e.g. the national CPI but not the regional
  ones), so `last: 1` may return series with an empty `"Data"`.

  ## Options

  #{NimbleOptions.docs(@observations_schema)}

  ## Examples

      iex> Inex.Tables.observations(76136, last: 1, filters: [data_type: 74, cpi_group: 304092])
      {:ok, [%{"COD" => "IPC290750", "Nombre" => "Nacional. Índice general. Variación anual. ", "Data" => [...]}, ...]}

      # PC-Axis table filtered by codes
      iex> Inex.Tables.observations("t20/e245/p08/l0/01001.px",
      ...>   last: 2,
      ...>   filters: [{"sexo", "mujeres"}, {"espanolesextranjeros", "espanoles"}, {"edad3gruposdeedad", "totaledades"}]
      ...> )
      {:ok, [%{"Nombre" => "TOTAL EDADES, Españoles, Mujeres", "Data" => [...]}]}
  """
  @spec observations(Inex.table_id(), keyword()) :: Client.response()
  def observations(table, opts \\ []) do
    Utils.fetch("DATOS_TABLA", [table], opts, @observations_schema)
  end

  @doc """
  Same as `observations/2` except that it returns the data inside of an
  `Explorer.DataFrame`.

  The data frame is **long** (tidy) by default: one row per observation, plus
  one column per variable that defines the series (`metadata: true`). This
  makes it easy to filter, group or pivot by any dimension of the table. Use
  `format: :wide` to get a `date` column plus one column per series instead.
  See `Inex.DataFrame` for the details of the columns.

  ## Options

  #{NimbleOptions.docs(@observations_data_frame_schema)}

  ## Examples

      iex> {:ok, df} =
      ...>   Inex.Tables.observations_as_data_frame(76136,
      ...>     filters: [data_type: 74, cpi_group: 304092, ccaa: :all],
      ...>     last: 12
      ...>   )
      iex> Explorer.DataFrame.names(df)
      ["code", "name", "date", "year", "period", "value", "data_type", "unit", "scale",
       "Comunidades y Ciudades Autónomas", "Grupos ECOICOP", "Índices y Tasas"]
  """
  @spec observations_as_data_frame(Inex.table_id(), keyword()) ::
          {:ok, DF.t()} | {:error, Error.t()}
  def observations_as_data_frame(table, opts \\ []) do
    with {:ok, opts} <- Utils.validate_opts(opts, @observations_data_frame_schema),
         {:ok, payload} <- observations(table, data_request_opts(opts)) do
      {:ok, Inex.DataFrame.build(payload, opts)}
    end
  end

  @doc """
  Same as `observations_as_data_frame/2` but returns the data frame directly
  and raises an `Inex.Error` on failure.
  """
  @spec observations_as_data_frame!(Inex.table_id(), keyword()) :: DF.t()
  def observations_as_data_frame!(table, opts \\ []) do
    table |> observations_as_data_frame(opts) |> Utils.bang!()
  end

  @doc """
  Get the series of a table (without data).

  With `metadata: true` each series includes the variables and values that
  define it, which is how you find the codes to filter PC-Axis and tpx tables.

  ## Options

  #{NimbleOptions.docs(@series_schema)}

  ## Examples

      iex> Inex.Tables.series(76136)
      {:ok, [%{"COD" => "IPC290751", "Nombre" => "Nacional. Índice general. Índice. ", ...}, ...]}

      iex> {:ok, [%{"MetaData" => [_ | _]} | _]} =
      ...>   Inex.Tables.series("t20/e245/p08/l0/01001.px", metadata: true)
  """
  @spec series(Inex.table_id(), keyword()) :: Client.response()
  def series(table, opts \\ []) do
    Utils.fetch("SERIES_TABLA", [table], opts, @series_schema)
  end

  @doc """
  Get the groups (selection combos) that define a Tempus3 table.

  Each group is defined by the values of one or more variables. Use
  `group_values/3` to get them, or `values/2` to get every value of every
  group in one call.

  ## Options

  #{NimbleOptions.docs(@groups_schema)}

  ## Examples

      iex> Inex.Tables.groups(76136)
      {:ok,
       [
         %{"Id" => 155612, "Nombre" => "Comunidades y Ciudades Autónomas"},
         %{"Id" => 155613, "Nombre" => "Grupos ECOICOP ver.2"},
         %{"Id" => 155614, "Nombre" => "Tipo de dato"}
       ]}
  """
  @spec groups(Inex.table_id(), keyword()) :: Client.response()
  def groups(table, opts \\ []) do
    Utils.fetch("GRUPOS_TABLA", [table], opts, @groups_schema)
  end

  @doc """
  Get the values of a group of a Tempus3 table.

  ## Options

  #{NimbleOptions.docs(@group_values_schema)}

  ## Examples

      iex> Inex.Tables.group_values(76136, 155614)
      {:ok, [%{"Id" => 83, "FK_Variable" => 3, "Nombre" => "Índice", "Codigo" => "0"}, ...]}

      iex> Inex.Tables.group_values(76136, 155614, detail: 1)
      {:ok, [%{"Id" => 83, "Nombre" => "Índice", "Codigo" => "0", "Variable" => %{"Id" => 3, "Nombre" => "Índices y Tasas", "Codigo" => "7"}}, ...]}
  """
  @spec group_values(Inex.table_id(), pos_integer(), keyword()) :: Client.response()
  def group_values(table, group, opts \\ []) do
    Utils.fetch("VALORES_GRUPOSTABLA", [table, group], opts, @group_values_schema)
  end

  @doc """
  Get all the variables and values of a table, ready to build `:filters`.

  Equivalent to `get_metadata_table_varval()` in the official `ineapir` R
  package. Every value has the shape of `group_values/3` with `detail: 1`:

      %{
        "Id" => 9003,
        "Nombre" => "Castilla y León",
        "Codigo" => "07",
        "Variable" => %{"Id" => 70, "Nombre" => "Comunidades y Ciudades Autónomas", "Codigo" => "0"},
        "JerarquiaPadres" => [...]
      }

  - For **Tempus3** tables the values come from `groups/2` and `group_values/3`
    (one request per group). Filter with `{value["Variable"]["Id"], value["Id"]}`.
  - **PC-Axis and tpx** tables have no groups, so the values are extracted from
    the metadata of their series (`series(table, metadata: true)`). In that case
    `"Variable"` holds the variable name and the code to filter by (lowercase,
    without spaces, accents or symbols, as the INE expects). Filter with
    `{value["Variable"]["Codigo"], value["Codigo"]}`.

  ## Options

  #{NimbleOptions.docs(@values_schema)}

  ## Examples

      iex> {:ok, values} = Inex.Tables.values(76136)
      iex> Enum.find(values, &(&1["Nombre"] == "Variación anual"))
      %{"Id" => 74, "Nombre" => "Variación anual", "Codigo" => "2", "Variable" => %{"Id" => 3, "Nombre" => "Índices y Tasas", "Codigo" => "7"}}

      iex> {:ok, values} = Inex.Tables.values("t20/e245/p08/l0/01001.px")
      iex> Enum.find(values, &(&1["Nombre"] == "Mujeres"))
      %{"Nombre" => "Mujeres", "Codigo" => "mujeres", "Variable" => %{"Nombre" => "Sexo", "Codigo" => "sexo"}}
  """
  @spec values(Inex.table_id(), keyword()) :: Client.response()
  def values(table, opts \\ []) do
    with {:ok, opts} <- Utils.validate_opts(opts, @values_schema) do
      case groups(table, opts) do
        {:ok, [_ | _] = groups} -> tempus_values(table, groups, opts)
        {:ok, _no_groups} -> metadata_values(table, opts)
        {:error, %Error{type: :not_found}} -> metadata_values(table, opts)
        {:error, _error} = error -> error
      end
    end
  end

  @doc """
  Get the statistical operation a table belongs to.

  This function (`OPERACIONES_TABLA`) is not listed in the official API
  reference but it is used by the official `ineapir` R package.

  ## Options

  #{NimbleOptions.docs(@operation_schema)}

  ## Examples

      iex> Inex.Tables.operation(76136)
      {:ok, [%{"Id" => 25, "Codigo" => "IPC", "Cod_IOE" => "30138", "Nombre" => "Índice de Precios de Consumo (IPC)", ...}]}
  """
  @spec operation(Inex.table_id(), keyword()) :: Client.response()
  def operation(table, opts \\ []) do
    Utils.fetch("OPERACIONES_TABLA", [table], opts, @operation_schema)
  end

  defp tempus_values(table, groups, opts) do
    Enum.reduce_while(groups, {:ok, []}, fn %{"Id" => group}, {:ok, acc} ->
      case group_values(table, group, Keyword.put(opts, :detail, 1)) do
        {:ok, values} -> {:cont, {:ok, acc ++ values}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
  end

  defp metadata_values(table, opts) do
    with {:ok, series} <- series(table, Keyword.put(opts, :metadata, true)) do
      values =
        series
        |> Enum.flat_map(&Map.get(&1, "MetaData", []))
        |> Enum.map(fn value ->
          variable = value["T3_Variable"]

          %{
            "Nombre" => value["Nombre"],
            "Codigo" => value["Codigo"],
            "Variable" => %{"Nombre" => variable, "Codigo" => variable_code(variable)}
          }
        end)
        |> Enum.uniq()

      {:ok, values}
    end
  end

  # "edad (3 grupos de edad)" -> "edad3gruposdeedad", "Españoles/Extranjeros" -> "espanolesextranjeros"
  @doc false
  def variable_code(nil), do: nil

  def variable_code(name) do
    name
    |> String.normalize(:nfd)
    |> String.replace(~r/[^A-Za-z0-9]/u, "")
    |> String.downcase()
  end

  defp data_request_opts(opts) do
    opts
    |> Keyword.take([:language, :last, :observation_start, :observation_end, :dates, :filters])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Keyword.merge(friendly: true, metadata: opts[:metadata])
  end
end
