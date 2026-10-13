defmodule Inex.DataFrame do
  @moduledoc """
  Converts INE API responses into `Explorer.DataFrame`s.

  Most users will not call this module directly: the `*_as_data_frame`
  functions (`Inex.Series.observations_as_data_frame/2`,
  `Inex.Tables.observations_as_data_frame/2`...) use it under the hood. It is
  public so that you can convert any raw response yourself.

  ## Long (tidy) format

  `from_observations/2` turns the payload of the data functions
  (`DATOS_SERIE`, `DATOS_TABLA`, `DATOS_METADATAOPERACION`) into a data frame
  with **one row per observation**:

  | column      | dtype    | description                                               |
  | ----------- | -------- | --------------------------------------------------------- |
  | `code`      | string   | Series code (`COD`), `nil` for PC-Axis/tpx tables         |
  | `name`      | string   | Series name                                               |
  | `date`      | date     | First day of the period (`2026-09-01` for September 2026) |
  | `year`      | s64      | Year of the period (`Anyo`)                               |
  | `period`    | string   | Period label (`"M09"`, `"T2"`, `"A"`, `"2024 (avance)"`)  |
  | `value`     | f64      | Observation value (`nil` when not available)              |
  | `data_type` | string   | `"Definitivo"`, `"Provisional"`, `"Avance"`...            |
  | `unit`      | string   | Unit of the series (`"Tasas"`, `"Euros"`...)              |
  | `scale`     | string   | Scale of the series (`"Miles"`...)                        |

  When the payload includes metadata (`metadata: true`, i.e. `tip=M` or `tip=AM`)
  one extra column is added **per variable** that defines the series, holding
  the name of its value. For a CPI table that could be `"Comunidades y Ciudades
  Autónomas"`, `"Grupos ECOICOP"` and `"Tipo de dato"`, which makes filtering
  and grouping with `Explorer.DataFrame` straightforward.

  Several fields are only present in some response types (`data_type`, `unit`
  and `scale` require `friendly: true` or `detail: 1`), so these columns may be
  `nil`. The `*_as_data_frame` functions always request friendly responses.

  ## Dates

  The INE reports dates as epoch milliseconds at **midnight in Madrid** (or as
  ISO 8601 strings with an offset in friendly responses). They are converted
  to the calendar date in Madrid. Very old observations and PC-Axis/tpx tables
  come without a date; in that case the date is derived from the year and the
  period label (months, quarters, semesters and years are supported).

  ## Wide format

  `to_wide/2` pivots a long data frame into a `date` column plus one column per
  series, which is convenient for charts and comparisons.
  """

  alias Explorer.DataFrame, as: DF

  @base_columns ~w(code name date year period value data_type unit scale)
  @base_dtypes [
    code: :string,
    name: :string,
    date: :date,
    year: {:s, 64},
    period: :string,
    value: {:f, 64},
    data_type: :string,
    unit: :string,
    scale: :string
  ]

  # Tempus3 period ids (FK_Periodo) for the most common periodicities.
  # See `Inex.Periodicities.periods/2`.
  @period_labels Map.merge(
                   Map.new(1..12, &{&1, "M" <> String.pad_leading("#{&1}", 2, "0")}),
                   %{
                     19 => "T1",
                     20 => "T2",
                     21 => "T3",
                     22 => "T4",
                     26 => "S1",
                     27 => "S2",
                     28 => "A"
                   }
                 )

  # Friendly responses of some functions label months as "jul.", "ago."...
  @month_abbreviations Map.merge(
                         Map.new(
                           Enum.with_index(~w(ENE FEB MAR ABR MAY JUN JUL AGO SEP OCT NOV DIC), 1)
                         ),
                         Map.new(
                           Enum.with_index(~w(JAN FEB MAR APR MAY JUN JUL AUG SEP OCT NOV DEC), 1)
                         )
                       )

  # Well-known INE fields shown first in `from_records/1`, the rest are sorted
  @preferred_record_columns ~w(Id COD Nombre Codigo Cod_IOE FK_Variable)

  @doc """
  Builds a long (tidy) data frame from the payload of a data function.

  `payload` can be a single series (as returned by `DATOS_SERIE`) or a list of
  series (as returned by `DATOS_TABLA` and `DATOS_METADATAOPERACION`).

  ## Examples

      iex> payload = %{
      ...>   "COD" => "IPC290750",
      ...>   "Nombre" => "Nacional. Índice general. Variación anual. ",
      ...>   "T3_Unidad" => "Tasas",
      ...>   "Data" => [
      ...>     %{"Fecha" => "2026-08-01T00:00:00.000+02:00", "T3_TipoDato" => "Definitivo",
      ...>       "T3_Periodo" => "M08", "Anyo" => 2026, "Valor" => 4.6},
      ...>     %{"Fecha" => "2026-09-01T00:00:00.000+02:00", "T3_TipoDato" => "Avance",
      ...>       "T3_Periodo" => "M09", "Anyo" => 2026, "Valor" => 4.9}
      ...>   ]
      ...> }
      iex> df = Inex.DataFrame.from_observations(payload)
      iex> Explorer.DataFrame.to_columns(df, atom_keys: true) |> Map.take([:date, :value, :data_type])
      %{date: [~D[2026-08-01], ~D[2026-09-01]], value: [4.6, 4.9], data_type: ["Definitivo", "Avance"]}
  """
  @spec from_observations(map() | [map()]) :: DF.t()
  def from_observations(payload) when is_map(payload), do: from_observations([payload])

  def from_observations(payload) when is_list(payload) do
    {rows, meta_columns} =
      Enum.reduce(payload, {[], []}, fn series, {rows, meta_columns} ->
        metadata = series_metadata(series)
        series_rows = series_rows(series, metadata)
        new_columns = for {column, _value} <- metadata, column not in meta_columns, do: column
        {[series_rows | rows], meta_columns ++ Enum.uniq(new_columns)}
      end)

    rows = rows |> Enum.reverse() |> Enum.concat()

    base = Enum.map(@base_columns, fn column -> {column, Enum.map(rows, & &1[column])} end)

    meta =
      Enum.map(meta_columns, fn column ->
        {column, Enum.map(rows, &get_in(&1, [:meta, column]))}
      end)

    meta_dtypes = Enum.map(meta_columns, &{&1, :string})

    DF.new(base ++ meta,
      dtypes: Enum.map(@base_dtypes, fn {k, v} -> {to_string(k), v} end) ++ meta_dtypes
    )
  end

  @doc false
  # Shared by the `*_as_data_frame` functions: long or wide data frame + renames
  @spec build(map() | [map()], keyword()) :: DF.t()
  def build(payload, opts) do
    rename = Keyword.get(opts, :rename) || %{}
    long = from_observations(payload)

    case Keyword.get(opts, :format, :long) do
      :wide -> to_wide(long, rename: rename)
      :long -> DF.rename(long, rename)
    end
  end

  @doc """
  Pivots a long data frame (see `from_observations/1`) into a wide one.

  The result has a `date` column followed by one column per series, sorted by
  date. Series that do not have an observation for a given date get `nil`.

  ## Options

    - `:columns` - which column names the series: `:code` (default) or `:name`.
      `:name` is used automatically when the series have no code (PC-Axis/tpx tables).
    - `:rename` - a map to rename the resulting columns, e.g. `%{"IPC290750" => "cpi"}`.

  ## Examples

      iex> long = Explorer.DataFrame.new(
      ...>   code: ["A", "A", "B"],
      ...>   name: ["a", "a", "b"],
      ...>   date: [~D[2026-01-01], ~D[2026-02-01], ~D[2026-01-01]],
      ...>   value: [1.0, 2.0, 3.0]
      ...> )
      iex> wide = Inex.DataFrame.to_wide(long, rename: %{"B" => "b"})
      iex> Explorer.DataFrame.to_columns(wide, atom_keys: true)
      %{A: [1.0, 2.0], b: [3.0, nil], date: [~D[2026-01-01], ~D[2026-02-01]]}
  """
  @spec to_wide(DF.t(), keyword()) :: DF.t()
  def to_wide(%DF{} = df, opts \\ []) do
    names_from =
      case Keyword.get(opts, :columns, :code) do
        :code -> if Explorer.Series.nil_count(df["code"]) == 0, do: "code", else: "name"
        :name -> "name"
      end

    index = if Explorer.Series.nil_count(df["date"]) == 0, do: "date", else: "period"

    if DF.n_rows(df) == 0 do
      DF.new([{index, []}], dtypes: [{index, df[index].dtype}])
    else
      df
      |> DF.select([index, names_from, "value"])
      |> DF.pivot_wider(names_from, "value")
      |> DF.sort_with(&[asc: &1[index]])
      |> DF.rename(Keyword.get(opts, :rename, %{}))
    end
  end

  @doc """
  Builds a data frame from a list of metadata records (operations, tables,
  variables, values, publications...).

  Nested maps are flattened using dots (`"Variable.Nombre"`), lists are encoded
  as JSON strings and columns mixing incompatible types are converted to strings.
  Column names keep the INE field names. `"Id"`, `"COD"`, `"Nombre"`, `"Codigo"`,
  `"Cod_IOE"` and `"FK_Variable"` come first, the rest are sorted alphabetically.

  ## Examples

      iex> records = [
      ...>   %{"Id" => 25, "Codigo" => "IPC", "Nombre" => "Índice de Precios de Consumo (IPC)"},
      ...>   %{"Id" => 293, "Codigo" => "EPA", "Nombre" => "Encuesta de Población Activa (EPA)", "Url" => "/epa"}
      ...> ]
      iex> df = Inex.DataFrame.from_records(records)
      iex> Explorer.DataFrame.names(df)
      ["Id", "Nombre", "Codigo", "Url"]
      iex> df["Url"] |> Explorer.Series.to_list()
      [nil, "/epa"]
  """
  @spec from_records(map() | [map()]) :: DF.t()
  def from_records(record) when is_map(record), do: from_records([record])

  def from_records(records) when is_list(records) do
    rows = Enum.map(records, &flatten_record/1)

    columns =
      rows
      |> Enum.flat_map(&Enum.map(&1, fn {key, _value} -> key end))
      |> Enum.uniq()
      |> Enum.sort_by(
        &{Enum.find_index(@preferred_record_columns, fn column -> column == &1 end) || 99, &1}
      )

    row_maps = Enum.map(rows, &Map.new/1)

    columns
    |> Enum.map(fn column -> {column, normalize_column(Enum.map(row_maps, & &1[column]))} end)
    |> DF.new()
  end

  ## Observations helpers

  defp series_rows(series, metadata) do
    base = %{
      "code" => series["COD"],
      "name" => clean_name(series["Nombre"]),
      "unit" => blank_to_nil(series["T3_Unidad"] || get_in(series, ["Unidad", "Nombre"])),
      "scale" => blank_to_nil(series["T3_Escala"] || get_in(series, ["Escala", "Nombre"])),
      meta: Map.new(metadata)
    }

    series
    |> Map.get("Data", [])
    |> List.wrap()
    |> Enum.map(&Map.merge(base, observation(&1)))
    |> Enum.sort_by(&sort_key/1)
  end

  defp observation(data) do
    period = period_label(data)
    year = data["Anyo"] || year_from_label(period)

    %{
      "date" => observation_date(data["Fecha"], year, period),
      "year" => year,
      "period" => period,
      "value" => to_float(data["Valor"]),
      "data_type" => data["T3_TipoDato"] || get_in(data, ["TipoDato", "Nombre"])
    }
  end

  defp sort_key(%{"date" => %Date{} = date}), do: {0, Date.to_gregorian_days(date)}
  defp sort_key(%{"year" => year}) when is_integer(year), do: {1, year}
  defp sort_key(_row), do: {2, 0}

  defp series_metadata(series) do
    series
    |> Map.get("MetaData", Map.get(series, "Metadata", []))
    |> List.wrap()
    |> Enum.map(fn value ->
      variable =
        value["T3_Variable"] || get_in(value, ["Variable", "Nombre"]) ||
          (value["FK_Variable"] && "Variable #{value["FK_Variable"]}")

      {variable && unique_column_name(String.trim(variable)), value["Nombre"]}
    end)
    |> Enum.reject(fn {variable, _value} -> is_nil(variable) end)
  end

  defp unique_column_name(column) do
    if column in @base_columns, do: column <> " (variable)", else: column
  end

  defp blank_to_nil(value) when is_binary(value) do
    if String.trim(value) == "", do: nil, else: String.trim(value)
  end

  defp blank_to_nil(value), do: value

  defp clean_name(nil), do: nil
  defp clean_name(name), do: name |> String.trim() |> String.trim_trailing(".") |> String.trim()

  defp period_label(data) do
    cond do
      label = data["T3_Periodo"] -> label
      label = get_in(data, ["Periodo", "Nombre"]) -> label
      label = data["NombrePeriodo"] -> label
      id = data["FK_Periodo"] -> Map.get(@period_labels, id, to_string(id))
      true -> nil
    end
  end

  defp year_from_label(nil), do: nil

  defp year_from_label(label) do
    case Regex.run(~r/^\s*(\d{4})/, label) do
      [_, year] -> String.to_integer(year)
      nil -> nil
    end
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value * 1.0
  defp to_float(_other), do: nil

  @doc false
  # Converts an INE `Fecha` into the calendar date in Madrid, falling back to
  # the year and period label when the date is missing.
  @spec observation_date(integer() | String.t() | nil, integer() | nil, String.t() | nil) ::
          Date.t() | nil
  def observation_date(milliseconds, _year, _period) when is_integer(milliseconds) do
    # Dates are midnight in Madrid (UTC+1/UTC+2), i.e. 22:00 or 23:00 UTC of the
    # previous day. Shifting by 12 hours lands on the right calendar day.
    milliseconds
    |> Kernel.+(12 * 60 * 60 * 1000)
    |> DateTime.from_unix!(:millisecond)
    |> DateTime.to_date()
  end

  def observation_date(<<iso_date::binary-size(10), _rest::binary>>, year, period) do
    case Date.from_iso8601(iso_date) do
      {:ok, date} -> date
      {:error, _reason} -> observation_date(nil, year, period)
    end
  end

  def observation_date(_fecha, year, period) when is_integer(year) and is_binary(period) do
    period
    |> String.trim()
    |> String.replace_prefix("#{year}", "")
    |> String.trim()
    |> String.upcase()
    |> period_start_month()
    |> case do
      nil -> nil
      month -> Date.new!(year, month, 1)
    end
  end

  def observation_date(_fecha, _year, _period), do: nil

  # "M09" -> 9, "SEP." -> 9, "T2"/"Q2" -> 4, "S2" -> 7, "A"/"" -> 1, "(AVANCE)" -> 1
  defp period_start_month(label) do
    cond do
      match = Regex.run(~r/^M(\d{1,2})$/, label) -> month(match, 1)
      month = Map.get(@month_abbreviations, String.trim_trailing(label, ".")) -> month
      match = Regex.run(~r/^[TQ]([1-4])$/, label) -> month(match, 3)
      match = Regex.run(~r/^S([12])$/, label) -> month(match, 6)
      label in ["", "A"] or String.starts_with?(label, "(") -> 1
      true -> nil
    end
  end

  defp month([_, n], months_per_period) do
    month = (String.to_integer(n) - 1) * months_per_period + 1
    if month in 1..12, do: month
  end

  ## Records helpers

  defp flatten_record(record, prefix \\ nil) do
    Enum.flat_map(record, fn {key, value} ->
      key = if prefix, do: "#{prefix}.#{key}", else: to_string(key)

      case value do
        %{} = nested -> flatten_record(nested, key)
        list when is_list(list) -> [{key, JSON.encode!(list)}]
        scalar -> [{key, scalar}]
      end
    end)
  end

  defp normalize_column(values) do
    types = values |> Enum.reject(&is_nil/1) |> Enum.map(&value_type/1) |> Enum.uniq()

    case types do
      [:float, :integer] -> Enum.map(values, &to_float/1)
      [:integer, :float] -> Enum.map(values, &to_float/1)
      [_single_type] -> values
      [] -> values
      _mixed -> Enum.map(values, &(&1 && to_string(&1)))
    end
  end

  defp value_type(value) when is_integer(value), do: :integer
  defp value_type(value) when is_float(value), do: :float
  defp value_type(value) when is_boolean(value), do: :boolean
  defp value_type(value) when is_binary(value), do: :string
  defp value_type(_value), do: :other
end
