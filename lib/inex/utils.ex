defmodule Inex.Utils do
  @moduledoc false

  # Option schemas shared by the endpoint modules, plus the translation of the
  # idiomatic Elixir options into the query parameters the INE API expects.

  alias Inex.Client
  alias Inex.Error
  alias Inex.Filters

  @periodicities [monthly: 1, quarterly: 3, semiannual: 6, annual: 12]

  # When a data function needs "all the observations", the API still requires
  # either `nult` or `date`, so an open range starting long ago is sent instead.
  @all_data_start ~D[1800-01-01]

  @doc """
  Validates `opts` against `schema`, translates them into INE query parameters
  and calls `function`. Handles `page: :all` transparently.

  ## Fetch options

    - `:filters_as` - `:table` (default) or `:operation`. See `to_params/2`.
    - `:ensure_data_range` - when `true`, requests all observations if neither
      `:last` nor a date range were given.
  """
  def fetch(function, inputs, opts, schema, fetch_opts \\ []) do
    with {:ok, opts} <- validate_opts(opts, schema) do
      params = to_params(opts, Keyword.get(fetch_opts, :filters_as, :table))
      params = if fetch_opts[:ensure_data_range], do: ensure_data_range(params), else: params

      if opts[:page] == :all,
        do: Client.get_all_pages(function, inputs, params, language_opts(opts)),
        else: Client.get(function, inputs, params, language_opts(opts))
    end
  end

  @doc false
  def validate_opts(opts, schema) do
    with {:ok, opts} <- nimble_validate(opts, schema),
         :ok <- validate_date_order(opts) do
      {:ok, opts}
    end
  end

  defp nimble_validate(opts, schema) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, validated_opts} -> {:ok, validated_opts}
      {:error, %NimbleOptions.ValidationError{} = error} -> option_error(Exception.message(error))
    end
  end

  defp validate_date_order(opts) do
    case {opts[:observation_start], opts[:observation_end]} do
      {%Date{} = start_date, %Date{} = end_date} ->
        if Date.after?(start_date, end_date),
          do: option_error(":observation_start must be on or before :observation_end"),
          else: :ok

      _other ->
        :ok
    end
  end

  defp option_error(message), do: {:error, Error.new(:option_error, message)}

  @doc false
  def schema(fields) do
    fields
    |> Enum.flat_map(&field_spec/1)
    |> Enum.sort_by(fn {field, _spec} -> field end)
    |> NimbleOptions.new!()
  end

  @doc """
  Translates validated options into INE query parameters.

  `filters_as` selects how `:filters` are encoded: `:table` (`tv=...`) or
  `:operation` (`g1=...`, `g2=...`).
  """
  def to_params(opts, filters_as \\ :table) do
    [
      det: opts[:detail],
      tip: tip(opts),
      geo: geo(opts[:geo]),
      p: periodicity(opts[:periodicity]),
      clasif: opts[:classification],
      nult: opts[:last]
    ] ++
      date_params(opts) ++ filter_params(opts[:filters], filters_as) ++ [page: page(opts[:page])]
  end

  @doc """
  Adds an open `date` range covering all the observations when neither `nult`
  nor `date` were given. `DATOS_SERIE` and `DATOS_METADATAOPERACION` answer
  with a 404 otherwise.
  """
  def ensure_data_range(params) do
    if Keyword.get(params, :nult) || Keyword.has_key?(params, :date) do
      params
    else
      params ++ [date: format_date(@all_data_start) <> ":"]
    end
  end

  @doc false
  def bang!({:ok, result}), do: result
  def bang!({:error, %Error{} = error}), do: raise(error)

  @doc false
  def language_opts(opts), do: Keyword.take(opts, [:language])

  @doc false
  # Builds the response type parameter (`tip`) from `:friendly` and `:metadata`
  def tip(opts) do
    case {opts[:friendly], opts[:metadata]} do
      {true, true} -> "AM"
      {true, _} -> "A"
      {_, true} -> "M"
      _ -> nil
    end
  end

  defp geo(nil), do: nil
  defp geo(:national), do: 0
  defp geo(:regional), do: 1

  defp periodicity(nil), do: nil
  defp periodicity(id) when is_integer(id), do: id
  defp periodicity(name), do: Keyword.fetch!(@periodicities, name)

  defp page(page) when is_integer(page), do: page
  defp page(_nil_or_all), do: nil

  defp filter_params(nil, _filters_as), do: []
  defp filter_params(filters, :table), do: Filters.to_table_params(filters)
  defp filter_params(filters, :operation), do: Filters.to_operation_params(filters)

  defp date_params(opts) do
    range =
      case {opts[:observation_start], opts[:observation_end]} do
        {nil, nil} -> []
        {start_date, end_date} -> [{start_date || @all_data_start, end_date}]
      end

    Enum.map(range ++ Enum.map(opts[:dates] || [], &to_range/1), fn {start_date, end_date} ->
      {:date, format_date(start_date) <> ":" <> format_date(end_date)}
    end)
  end

  defp to_range(%Date{} = date), do: {date, date}

  defp to_range(%Date.Range{first: first, last: last}) do
    if Date.after?(first, last), do: {last, first}, else: {first, last}
  end

  defp to_range({start_date, end_date}), do: {start_date, end_date}

  defp format_date(nil), do: ""
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y%m%d")

  @doc false
  # NimbleOptions custom validator for the `:dates` option
  def validate_date_range(%Date{} = date), do: {:ok, date}
  def validate_date_range(%Date.Range{} = range), do: {:ok, range}

  def validate_date_range({%Date{} = start_date, end_date} = range)
      when is_nil(end_date) or is_struct(end_date, Date) do
    if end_date && Date.after?(start_date, end_date),
      do: {:error, "expected start date to be on or before end date, got: #{inspect(range)}"},
      else: {:ok, range}
  end

  def validate_date_range(other),
    do:
      {:error,
       "expected a Date, a Date.Range or a {start_date, end_date | nil} tuple, got: #{inspect(other)}"}

  ## Option specs

  defp field_spec(:language) do
    [
      language: [
        type: {:in, [:es, :en]},
        doc:
          "Language of the response: `:es` (Spanish) or `:en` (English). " <>
            "Defaults to the `:language` application setting (`:es`).",
        type_doc: "`:es | :en`"
      ]
    ]
  end

  defp field_spec(:detail) do
    [
      detail: [
        type: {:in, [0, 1, 2]},
        doc:
          "Level of detail of the response (`det`): `0` basic information, `1` detailed, " <>
            "`2` very detailed (nested objects instead of Tempus3 ids).",
        type_doc: "`0 | 1 | 2`"
      ]
    ]
  end

  defp field_spec(:friendly) do
    [
      friendly: [
        type: :boolean,
        doc:
          "Return a user-friendly response (`tip=A`): readable dates and names instead of Tempus3 ids."
      ]
    ]
  end

  defp field_spec(:metadata) do
    [
      metadata: [
        type: :boolean,
        doc: "Include the metadata (variables and values) that define each series (`tip=M`)."
      ]
    ]
  end

  defp field_spec({:metadata, default}) do
    [
      metadata: [
        type: :boolean,
        default: default,
        doc:
          "Request the metadata of each series (`tip=AM`) and add one column per variable " <>
            "(province, type of data...) to the long data frame."
      ]
    ]
  end

  defp field_spec(:geo) do
    [
      geo: [
        type: {:in, [:national, :regional]},
        doc:
          "Geographic scope (`geo`): `:national` (`geo=0`) for national results only, " <>
            "`:regional` (`geo=1`) for results broken down by autonomous communities, " <>
            "provinces, municipalities and other breakdowns.",
        type_doc: "`:national | :regional`"
      ]
    ]
  end

  defp field_spec(:page), do: page_spec(nil)
  defp field_spec({:page, default}), do: page_spec(default)

  defp field_spec(:last) do
    [last: [type: :pos_integer, doc: "Return only the last `n` periods (`nult`)."]]
  end

  defp field_spec(:date_range) do
    [
      observation_start: [
        type: {:struct, Date},
        doc: "Start date for observations (`date=yyyymmdd:`)."
      ],
      observation_end: [
        type: {:struct, Date},
        doc:
          "End date for observations (`date=...:yyyymmdd`). Without `:observation_start` " <>
            "the range starts in 1800, since the INE does not accept open starts."
      ],
      dates: [
        type: {:list, {:custom, __MODULE__, :validate_date_range, []}},
        doc:
          "Additional dates or date ranges to retrieve. Each element can be a `Date` " <>
            "(a single period), a `Date.Range` or a `{start_date, end_date}` tuple where " <>
            "`end_date` may be `nil` for an open range. Every element is sent as a separate " <>
            "`date` parameter.",
        type_doc: "list of `t:Date.t/0`, `t:Date.Range.t/0` or `{Date.t(), Date.t() | nil}`"
      ]
    ]
  end

  defp field_spec(:table_filters) do
    [
      filters: [
        type: {:custom, Filters, :validate, []},
        doc:
          "Variable/value filters, sent as `tv` parameters. For example " <>
            "`[{3, 74}, {70, [9003, 8999]}, {762, :all}]` or `[data_type: 74, ccaa: :all]`. " <>
            "See `Inex.Filters`.",
        type_doc: "`t:Inex.Filters.t/0`"
      ]
    ]
  end

  defp field_spec(:operation_filters) do
    [
      filters: [
        type: {:custom, Filters, :validate, []},
        doc:
          "Variable/value filters, sent as `g1`, `g2`... parameters. Each tuple is a filter " <>
            "group (groups are combined with AND, the values of a group with OR). For example " <>
            "`[{115, [29, 8]}, {3, 84}, {762, :all}]` or `[province: 29, data_type: 84]`. " <>
            "See `Inex.Filters`.",
        type_doc: "`t:Inex.Filters.t/0`"
      ]
    ]
  end

  defp field_spec(:periodicity) do
    [
      periodicity: [
        type: {:or, [{:in, Keyword.keys(@periodicities)}, :pos_integer]},
        doc:
          "Periodicity of the series (`p`): `:monthly` (1), `:quarterly` (3), `:semiannual` (6), " <>
            "`:annual` (12) or any periodicity id from `Inex.Periodicities.list/1`.",
        type_doc: "`:monthly | :quarterly | :semiannual | :annual | pos_integer()`"
      ]
    ]
  end

  defp field_spec(:classification) do
    [
      classification: [
        type: :pos_integer,
        doc:
          "Return values for the given classification id (`clasif`). See `Inex.Classifications.list/1`."
      ]
    ]
  end

  defp field_spec(:data_frame) do
    [
      max_concurrency: [
        type: :pos_integer,
        default: 5,
        doc: "Maximum number of concurrent requests when fetching several series."
      ]
    ]
  end

  defp field_spec({:format, default}) do
    [
      format: [
        type: {:in, [:wide, :long]},
        default: default,
        doc:
          "Shape of the data frame. `:wide` has a `date` column plus one column per series, " <>
            "`:long` (tidy) has one row per observation. See `Inex.DataFrame`.",
        type_doc: "`:wide | :long`"
      ],
      rename: [
        type: {:map, :string, :string},
        doc:
          "A map of columns to rename in the resulting data frame, e.g. `%{\"IPC290750\" => \"cpi\"}`."
      ]
    ]
  end

  defp page_spec(default) do
    spec = [
      type: {:or, [:pos_integer, {:in, [:all]}]},
      doc:
        "Page to retrieve (`page`). The INE paginates large listings; use `:all` to request " <>
          "every page and concatenate the results.",
      type_doc: "`pos_integer() | :all`"
    ]

    [page: if(default, do: Keyword.put(spec, :default, default), else: spec)]
  end
end
