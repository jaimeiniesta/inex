defmodule Inex.Operations do
  @moduledoc """
  Functions for the INE statistical **operations** endpoints.

  Operations are the statistics produced by the INE: the Consumer Price Index
  (`IPC`), the Labour Force Survey (`EPA`), the Quarterly National Accounts
  (`CNTR`)... Every operation contains tables and series.

  An operation can be identified in three ways, all accepted by these functions:

    - the Tempus3 numeric id: `25`
    - the Tempus3 alphabetic code: `"IPC"`
    - the code in the Inventory of Statistical Operations: `"IOE30138"`

  ## Endpoints

    - `list/1` - [`OPERACIONES_DISPONIBLES`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1143) - All available operations
    - `get/2` - [`OPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1144) - A single operation
    - `variables/2` - [`VARIABLES_OPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1146) - Variables used in an operation
    - `variable_values/3` - [`VALORES_VARIABLEOPERACION/{var}/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1148) - Values of a variable in an operation
    - `tables/2` - [`TABLAS_OPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1149) - Tables of an operation
    - `series/2` - [`SERIES_OPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1154) - Series of an operation (paginated)
    - `classifications/2` - [`CLASIFICACIONES_OPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100) - Classifications of an operation
    - `publications/2` - [`PUBLICACIONES_OPERACION/{op}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1160) - Publications of an operation
    - `periodicities/2` - `PERIODICIDAD_OPERACION/{op}` - Periodicities of an operation
      (not in the official reference, used by the official `ineapir` R package)

  To retrieve the series of an operation filtered by variables and values, see
  `Inex.Series.search/2` and `Inex.Series.search_observations/2`.
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language, :detail, :geo, :page])
  @get_schema Utils.schema([:language, :detail])
  @variables_schema Utils.schema([:language, :page])
  @variable_values_schema Utils.schema([:language, :detail])
  @tables_schema Utils.schema([:language, :detail, :geo, :friendly, :page])
  @series_schema Utils.schema([:language, :detail, :friendly, :metadata, {:page, 1}])
  @classifications_schema Utils.schema([:language])
  @publications_schema Utils.schema([:language, :detail, :friendly])
  @periodicities_schema Utils.schema([:language])

  @doc """
  Get all the statistical operations available in the INE database.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> {:ok, operations} = Inex.Operations.list()
      iex> Enum.find(operations, &(&1["Codigo"] == "IPC"))
      %{"Id" => 25, "Cod_IOE" => "30138", "Codigo" => "IPC", "Nombre" => "Índice de Precios de Consumo (IPC)", "Url" => "..."}

      iex> {:ok, regional_operations} = Inex.Operations.list(geo: :regional)

      iex> {:error, %Inex.Error{type: :option_error}} = Inex.Operations.list(geo: :galaxy)
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("OPERACIONES_DISPONIBLES", [], opts, @list_schema)
  end

  @doc """
  Get a single statistical operation.

  ## Options

  #{NimbleOptions.docs(@get_schema)}

  ## Examples

      iex> Inex.Operations.get("IPC")
      {:ok, %{"Id" => 25, "Cod_IOE" => "30138", "Codigo" => "IPC", "Nombre" => "Índice de Precios de Consumo (IPC)", ...}}

      iex> {:ok, %{"Codigo" => "IPC"}} = Inex.Operations.get(25)
      iex> {:ok, %{"Codigo" => "IPC"}} = Inex.Operations.get("IOE30138")

      iex> {:error, %Inex.Error{type: :not_found}} = Inex.Operations.get("NOPE")
  """
  @spec get(Inex.operation_id(), keyword()) :: Client.response()
  def get(operation, opts \\ []) do
    Utils.fetch("OPERACION", [operation], opts, @get_schema)
  end

  @doc """
  Get the variables used in a statistical operation (province, sex, type of data...).

  Use the variable ids with `variable_values/3` and as filters for
  `Inex.Series.search/2`.

  ## Options

  #{NimbleOptions.docs(@variables_schema)}

  ## Examples

      iex> Inex.Operations.variables("IPC")
      {:ok, [%{"Id" => 3, "Nombre" => "Tipo de dato", "Codigo" => ""}, %{"Id" => 70, "Nombre" => "Comunidades y Ciudades Autónomas", "Codigo" => "CCAA"}, ...]}
  """
  @spec variables(Inex.operation_id(), keyword()) :: Client.response()
  def variables(operation, opts \\ []) do
    Utils.fetch("VARIABLES_OPERACION", [operation], opts, @variables_schema)
  end

  @doc """
  Get the values that a variable takes in a statistical operation.

  Note that the INE function takes the variable first
  (`VALORES_VARIABLEOPERACION/{variable}/{operation}`); this function keeps the
  operation first for consistency with the rest of the module.

  ## Options

  #{NimbleOptions.docs(@variable_values_schema)}

  ## Examples

      # Values of the variable "Grupos ECOICOP" (762) in the CPI
      iex> Inex.Operations.variable_values("IPC", 762)
      {:ok, [%{"Id" => 304092, "FK_Variable" => 762, "Nombre" => "Índice general", "Codigo" => "00"}, ...]}
  """
  @spec variable_values(Inex.operation_id(), pos_integer(), keyword()) :: Client.response()
  def variable_values(operation, variable, opts \\ []) do
    Utils.fetch("VALORES_VARIABLEOPERACION", [variable, operation], opts, @variable_values_schema)
  end

  @doc """
  Get the tables of a statistical operation.

  The `"Id"` of each table can be used with the `Inex.Tables` functions.

  ## Options

  #{NimbleOptions.docs(@tables_schema)}

  ## Examples

      iex> Inex.Operations.tables("IPC")
      {:ok, [%{"Id" => 24077, "Nombre" => "Índice general nacional. Series desde enero de 1961", "Codigo" => "NAC", ...}, ...]}

      iex> {:ok, tables} = Inex.Operations.tables("EPA", geo: :regional, friendly: true)
  """
  @spec tables(Inex.operation_id(), keyword()) :: Client.response()
  def tables(operation, opts \\ []) do
    Utils.fetch("TABLAS_OPERACION", [operation], opts, @tables_schema)
  end

  @doc """
  Get the series of a statistical operation.

  The response is paginated (10,000 series per page for large operations) and
  this function returns the **first page by default**, like the official R
  package. Use `page: 2`, `page: 3`... or `page: :all` to fetch every page
  (several requests of a few MB each for operations like the CPI).

  To get a specific subset of series use `Inex.Series.search/2` instead.

  ## Options

  #{NimbleOptions.docs(@series_schema)}

  ## Examples

      iex> Inex.Operations.series("IPC")
      {:ok, [%{"COD" => "IPC53262", "Nombre" => "Baleares. Tasa de variación en lo que va de año medicina", ...}, ...]}

      iex> {:ok, all_series} = Inex.Operations.series("ETCL", page: :all)
  """
  @spec series(Inex.operation_id(), keyword()) :: Client.response()
  def series(operation, opts \\ []) do
    Utils.fetch("SERIES_OPERACION", [operation], opts, @series_schema)
  end

  @doc """
  Get the classifications used in a statistical operation (bases, national
  classifications, population frames...).

  ## Options

  #{NimbleOptions.docs(@classifications_schema)}

  ## Examples

      iex> Inex.Operations.classifications("IPC")
      {:ok, [%{"Id" => 5, "Nombre" => "Base 1976", "Fecha" => 220921200000}, ...]}
  """
  @spec classifications(Inex.operation_id(), keyword()) :: Client.response()
  def classifications(operation, opts \\ []) do
    Utils.fetch("CLASIFICACIONES_OPERACION", [operation], opts, @classifications_schema)
  end

  @doc """
  Get the publications of a statistical operation.

  Use the publication `"Id"` with `Inex.Publications.dates/2` to get its
  release calendar.

  ## Options

  #{NimbleOptions.docs(@publications_schema)}

  ## Examples

      iex> Inex.Operations.publications("IPC")
      {:ok, [%{"Id" => 8, "Nombre" => "Índice de Precios de Consumo", "FK_Periodicidad" => 1, ...}, ...]}
  """
  @spec publications(Inex.operation_id(), keyword()) :: Client.response()
  def publications(operation, opts \\ []) do
    Utils.fetch("PUBLICACIONES_OPERACION", [operation], opts, @publications_schema)
  end

  @doc """
  Get the periodicities of the series of a statistical operation.

  This function (`PERIODICIDAD_OPERACION`) is not listed in the official API
  reference but it is used by the official `ineapir` R package.

  ## Options

  #{NimbleOptions.docs(@periodicities_schema)}

  ## Examples

      iex> Inex.Operations.periodicities("IPC")
      {:ok, [%{"Id" => 1, "Nombre" => "Mensual", "Codigo" => "M"}, %{"Id" => 12, "Nombre" => "Anual", "Codigo" => "A"}]}
  """
  @spec periodicities(Inex.operation_id(), keyword()) :: Client.response()
  def periodicities(operation, opts \\ []) do
    Utils.fetch("PERIODICIDAD_OPERACION", [operation], opts, @periodicities_schema)
  end
end
