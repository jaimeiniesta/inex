defmodule Inex.Filters do
  @shortcut_definitions [
    national: {349, "National total (Total Nacional)"},
    ccaa: {70, "Autonomous communities (Comunidades y Ciudades Autónomas)"},
    province: {115, "Provinces (Provincias)"},
    municipality: {19, "Municipalities (Municipios)"},
    island: {20, "Islands (Islas)"},
    cpi_group: {762, "CPI ECOICOP groups (Grupos ECOICOP)"},
    cpi_subgroup: {763, "CPI subgroups"},
    cpi_class: {764, "CPI classes"},
    cpi_subclass: {765, "CPI subclasses"},
    cpi_heading: {270, "CPI headings (Rúbricas)"},
    cpi_special_group: {269, "CPI special groups (Grupos especiales)"},
    data_type: {3, "Type of data (Tipo de dato): index, monthly change, annual change..."},
    sex: {18, "Sex (Sexo)"},
    age: {355, "Simple age values (Edad)"},
    age_total: {356, "Age totals (Totales de edad)"},
    age_group: {360, "Age groups (Grupos de edad)"},
    age_semi_interval: {357, "Age semi-intervals (Semiintervalos de edad)"},
    nationality: {141, "Nationality (Nacionalidad)"},
    generation: {612, "Generation/ages (Generación)"},
    birthplace: {97, "Place of birth (Lugar de nacimiento)"},
    effects_correction: {544, "Correction of effects (Corrección de efectos)"}
  ]

  @moduledoc """
  Variable/value filters for INE tables and operations.

  Several INE functions accept filters that select series by the values of the
  variables that define them (province, sex, type of data...). Inex uses a single
  Elixir representation for all of them: a list of `{variable, values}` tuples
  (a keyword list or a map also work).

  ```elixir
  filters: [
    {3, 74},              # variable 3 (type of data) = 74 (annual change)
    {70, [9003, 8999]},   # variable 70 (autonomous communities) = Castilla y León OR Asturias
    {762, :all}           # every value of variable 762 (CPI ECOICOP groups)
  ]
  ```

  - `variable` is the variable identifier: an integer (`70`), a string (`"sexo"`,
    `"349~id"`) or one of the [shortcuts](#module-shortcuts) (`:ccaa`).
  - `values` is a single value (`74`, `"mujeres"`), a list of values (combined
    with **OR**) or `:all` to select every value of the variable.

  Shortcuts read nicely as keywords:

  ```elixir
  filters: [data_type: 74, cpi_group: 304092, ccaa: :all]
  ```

  ## Table filters (`tv`)

  Used by `Inex.Tables.observations/2` and `Inex.Tables.series/2`. Each value is
  sent as a separate `tv=variable:value` parameter. The identifiers depend on the
  source of the table:

  - **Tempus3 tables** use numeric ids for variables and values. Find them with
    `Inex.Tables.values/2` (or `Inex.Tables.groups/2` + `Inex.Tables.group_values/3`).
  - **PC-Axis and tpx tables** use alphanumeric codes (`{"sexo", "mujeres"}`).
    Find them with `Inex.Tables.values/2` or `Inex.Tables.series(id, metadata: true)`.
    Some tpx tables also accept Tempus3 ids with the `~id` suffix: `{"349~id", "16473~id"}`.

  ## Operation filters (`g1`, `g2`, ...)

  Used by `Inex.Series.search/2` and `Inex.Series.search_observations/2`.
  Every tuple becomes a filter group (`g1`, `g2`...). Groups are combined with
  **AND** while the values inside a group are combined with **OR**. Up to 50
  groups are accepted. Only numeric Tempus3 identifiers are supported here. Find them with
  `Inex.Operations.variables/2` and `Inex.Operations.variable_values/3`.

  ## Shortcuts

  The following shortcuts (taken from the official
  [ineapir](https://github.com/es-ine/ineapir) R package) can be used instead
  of the numeric variable ids:

  #{Enum.map_join(@shortcut_definitions, "\n", fn {shortcut, {id, description}} -> "- `#{inspect(shortcut)}` - `#{id}` - #{description}" end)}
  """

  @shortcuts Map.new(@shortcut_definitions, fn {shortcut, {id, _description}} ->
               {shortcut, id}
             end)

  # Operation filter groups are sent as `g1`, `g2`... The keys are built at
  # compile time so that user input never creates atoms. One group per variable
  # is enough, so the limit is far above what any operation needs.
  @max_groups 50
  @group_keys Enum.map(1..@max_groups, &String.to_atom("g#{&1}"))

  @type variable :: pos_integer() | String.t() | atom()
  @type value :: non_neg_integer() | String.t()
  @type t ::
          [{variable(), value() | [value()] | :all}] | %{variable() => value() | [value()] | :all}

  @doc """
  Returns the map of variable shortcuts to INE variable ids.

      iex> Inex.Filters.shortcuts()[:ccaa]
      70
  """
  @spec shortcuts() :: %{atom() => pos_integer()}
  def shortcuts, do: @shortcuts

  @doc """
  Converts filters into `tv` query parameters for table functions.

      iex> Inex.Filters.to_table_params([{3, 74}, ccaa: [9003, 8999], cpi_group: :all])
      [tv: "3:74", tv: "70:9003", tv: "70:8999", tv: "762:"]

      iex> Inex.Filters.to_table_params(%{"sexo" => "mujeres"})
      [tv: "sexo:mujeres"]
  """
  @spec to_table_params(t()) :: keyword(String.t())
  def to_table_params(filters) do
    for {variable, values} <- filters, value <- List.wrap(values) do
      {:tv, pair(variable, value)}
    end
  end

  @doc """
  Converts filters into `g1`, `g2`... query parameters for operation functions.

      iex> Inex.Filters.to_operation_params([province: [29, 8], data_type: 84, cpi_group: :all])
      [g1: "115:29", g1: "115:8", g2: "3:84", g3: "762:"]
  """
  @spec to_operation_params(t()) :: keyword(String.t())
  def to_operation_params(filters) do
    if Enum.count(filters) > @max_groups do
      raise ArgumentError, "expected at most #{@max_groups} filter groups"
    end

    filters
    |> Enum.zip(@group_keys)
    |> Enum.flat_map(fn {{variable, values}, key} ->
      Enum.map(List.wrap(values), &{key, pair(variable, &1)})
    end)
  end

  @doc false
  # NimbleOptions custom validator
  def validate(filters) when is_map(filters), do: validate(Map.to_list(filters))

  def validate(filters) when is_list(filters) do
    case Enum.find(filters, &(not valid_filter?(&1))) do
      nil ->
        {:ok, filters}

      invalid ->
        {:error,
         "invalid filter #{inspect(invalid)}. Expected {variable, value | [value] | :all} where " <>
           "variable is a positive integer, a string or one of #{inspect(Map.keys(@shortcuts))}"}
    end
  end

  def validate(other),
    do: {:error, "expected filters to be a list or a map, got: #{inspect(other)}"}

  @doc false
  # NimbleOptions custom validator for operation filters (`g1`, `g2`...)
  def validate_operation(filters) do
    with {:ok, filters} <- validate(filters) do
      if length(filters) > @max_groups,
        do: {:error, "expected at most #{@max_groups} filter groups, got: #{length(filters)}"},
        else: {:ok, filters}
    end
  end

  defp valid_filter?({variable, values}) do
    valid_variable?(variable) and
      (values == :all or
         (List.wrap(values) != [] and Enum.all?(List.wrap(values), &valid_value?/1)))
  end

  defp valid_filter?(_other), do: false

  defp valid_variable?(variable) when is_atom(variable), do: Map.has_key?(@shortcuts, variable)
  defp valid_variable?(variable) when is_integer(variable), do: variable > 0
  defp valid_variable?(variable), do: is_binary(variable) and variable != ""

  defp valid_value?(value) when is_integer(value), do: value >= 0
  defp valid_value?(value), do: is_binary(value)

  defp pair(variable, :all), do: "#{variable_id(variable)}:"
  defp pair(variable, value), do: "#{variable_id(variable)}:#{value}"

  defp variable_id(variable) when is_atom(variable), do: Map.fetch!(@shortcuts, variable)
  defp variable_id(variable), do: variable
end
