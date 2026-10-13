defmodule Inex.Variables do
  @moduledoc """
  Functions for the INE **variables** and **values** endpoints.

  Variables are the measurable characteristics of the system (province, sex,
  age group, type of data...). They are shared by all the statistical
  operations. Values are the states a variable can take (`"Madrid"`,
  `"Mujeres"`, `"Variación anual"`...). Series are defined by the values of
  several variables, which is what `Inex.Filters` builds upon.

  ## Endpoints

    - `list/1` - [`VARIABLES`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1145) - All variables
    - `values/2` - [`VALORES_VARIABLE/{var}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1147) - Values of a variable
    - `children/3` - [`VALORES_HIJOS/{var}/{value}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100) - Children of a value in a hierarchy

  To get the variables (and their values) used by a given operation, see
  `Inex.Operations.variables/2` and `Inex.Operations.variable_values/3`.
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language, :page])
  @values_schema Utils.schema([:language, :detail, :classification])
  @children_schema Utils.schema([:language, :detail])

  @doc """
  Get all the variables of the INE database.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> Inex.Variables.list()
      {:ok, [%{"Id" => 349, "Nombre" => "Total Nacional", "Codigo" => "NAC"}, ...]}
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("VARIABLES", [], opts, @list_schema)
  end

  @doc """
  Get all the values of a variable.

  ## Options

  #{NimbleOptions.docs(@values_schema)}

  ## Examples

      # Provinces (variable 115)
      iex> Inex.Variables.values(115)
      {:ok, [%{"Id" => 16473, "FK_Variable" => 115, "Nombre" => "Total Nacional", "Codigo" => "00"}, ...]}

      # Municipalities (19) for a given classification
      iex> {:ok, municipalities} = Inex.Variables.values(19, classification: 121, detail: 2)
  """
  @spec values(pos_integer(), keyword()) :: Client.response()
  def values(variable, opts \\ []) do
    Utils.fetch("VALORES_VARIABLE", [variable], opts, @values_schema)
  end

  @doc """
  Get the children of a value within a hierarchical structure, e.g. the
  provinces of an autonomous community or the municipalities of a province.

  ## Options

  #{NimbleOptions.docs(@children_schema)}

  ## Examples

      # Provinces of Andalucía (variable 70, value 8997)
      iex> Inex.Variables.children(70, 8997)
      {:ok, [%{"Id" => 5, "FK_Variable" => 115, "Nombre" => "Almería", "Codigo" => "04", ...}, ...]}
  """
  @spec children(pos_integer(), non_neg_integer(), keyword()) :: Client.response()
  def children(variable, value, opts \\ []) do
    Utils.fetch("VALORES_HIJOS", [variable, value], opts, @children_schema)
  end
end
