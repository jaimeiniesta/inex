defmodule Inex.Client do
  @moduledoc """
  Low-level HTTP client for the INE JSON API (`wstempus`), built on `Req`.

  Every request has the shape documented by the INE:

  ```
  https://servicios.ine.es/wstempus/js/{language}/{function}/{inputs}[?params]
  ```

  This module handles URL construction, query string encoding (including the
  repeated `tv`/`g1` parameters the INE uses for filters), response decoding,
  error normalization, pagination and telemetry. All the endpoint modules
  (`Inex.Series`, `Inex.Tables`...) delegate to it, but you can also use it
  directly to call any INE function:

      iex> Inex.Client.get("DATOS_SERIE", ["IPC290750"], nult: 3, tip: "A")
      {:ok, %{"COD" => "IPC290750", "Data" => [...], ...}}

  ## Response handling

  The INE API does not use HTTP status codes consistently, so responses are
  normalized as follows:

    - `200` with a JSON body - `{:ok, decoded_json}`
    - `200` with an empty body (unknown identifier) - `{:error, %Inex.Error{type: :not_found}}`
    - `200` with a plain text body (e.g. an unknown function) - `{:error, %Inex.Error{type: :api_error}}`
    - `404` (invalid parameters or unknown table) - `{:error, %Inex.Error{type: :not_found}}`
    - any other status - `{:error, %Inex.Error{type: :api_error}}`
    - transport failures - `{:error, %Inex.Error{type: :request_error}}`

  ## Configuration

  ```elixir
  config :inex,
    language: :es,                                        # :es (default) or :en
    timeout: 60_000,                                      # receive timeout in ms
    base_url: "https://servicios.ine.es/wstempus/js",     # API root
    req_options: []                                       # extra options for Req.new/1
  ```

  `:req_options` is merged into the `Req` request, so you can tweak retries,
  add a proxy or plug a `Req.Test` stub in your test suite:

  ```elixir
  # config/test.exs
  config :inex, req_options: [plug: {Req.Test, Inex.Client}, retry: false]
  ```

  ## Telemetry

  Every HTTP request is wrapped in an `[:inex, :request]` telemetry span.
  See `Inex.Telemetry` for event names, measurements and metadata.
  """

  alias Inex.Error
  alias Inex.Telemetry

  @type response :: {:ok, term()} | {:error, Error.t()}
  @type input :: String.t() | integer()

  @default_base_url "https://servicios.ine.es/wstempus/js"
  @default_timeout 60_000
  @max_pages 1_000

  @languages %{es: "ES", en: "EN"}

  @doc """
  Makes a GET request to the given INE API `function`.

  ## Arguments

    - `function` - INE function name, e.g. `"DATOS_SERIE"` or `"TABLAS_OPERACION"`.
    - `inputs` - path inputs, e.g. `["IPC290750"]` or `[762, "IPC"]`. Slashes are
      preserved, so PC-Axis table identifiers like `"t20/e245/p08/l0/01001.px"` work.
    - `params` - query parameters as a keyword list using the INE names
      (`nult`, `det`, `tip`, `tv`, `g1`...). Repeated keys are kept, `nil`
      values are dropped.
    - `opts` - `:language` (`:es` or `:en`). Defaults to the `:language`
      application setting (`:es`).
  """
  @spec get(String.t(), [input()], keyword(), keyword()) :: response()
  def get(function, inputs \\ [], params \\ [], opts \\ []) do
    language = Keyword.get_lazy(opts, :language, &default_language/0)
    params = Enum.reject(params, fn {_key, value} -> is_nil(value) end)
    url = build_url(function, inputs, params, language)

    metadata = %{function: function, url: url, params: params, language: language}

    Telemetry.span(metadata, fn -> execute_request(url) end)
  end

  @doc """
  Fetches every page of a paginated INE function and concatenates the results.

  The INE paginates some listings (`SERIES_OPERACION`, `OPERACIONES_DISPONIBLES`,
  `VARIABLES`...). The page size is not fixed (it is 10,000 for series and
  larger for other listings), so pages are requested sequentially, starting at
  `page=1`, until the API returns an empty list.
  """
  @spec get_all_pages(String.t(), [input()], keyword(), keyword()) :: response()
  def get_all_pages(function, inputs \\ [], params \\ [], opts \\ []) do
    params = Keyword.delete(params, :page)

    Enum.reduce_while(1..@max_pages, {:ok, []}, fn page, {:ok, acc} ->
      case get(function, inputs, params ++ [page: page], opts) do
        {:ok, [_ | _] = items} -> {:cont, {:ok, [items | acc]}}
        {:ok, _empty_or_not_a_list} -> {:halt, {:ok, acc}}
        # An empty body on a page after the first one also signals the end
        {:error, %Error{type: :not_found}} when acc != [] -> {:halt, {:ok, acc}}
        {:error, _error} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, pages} -> {:ok, pages |> Enum.reverse() |> Enum.concat()}
      error -> error
    end
  end

  @doc false
  @spec build_url(String.t(), [input()], keyword(), atom()) :: String.t()
  def build_url(function, inputs, params, language) do
    path =
      [base_url(), Map.fetch!(@languages, language), function | Enum.map(inputs, &encode_input/1)]
      |> Enum.join("/")

    case params do
      [] -> path
      params -> path <> "?" <> URI.encode_query(params)
    end
  end

  defp execute_request(url) do
    request =
      [
        url: url,
        decode_body: false,
        receive_timeout: Application.get_env(:inex, :timeout, @default_timeout),
        headers: [user_agent: "inex/#{Application.spec(:inex, :vsn)} (Elixir)"]
      ]
      |> Keyword.merge(Application.get_env(:inex, :req_options, []))
      |> Req.new()

    case Req.get(request) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {decode_body(body), 200}

      {:ok, %Req.Response{status: 404}} ->
        message =
          "The INE API returned HTTP 404. The resource does not exist or the request " <>
            "parameters are invalid (e.g. DATOS_SERIE requires either nult or date)."

        {{:error, Error.new(:not_found, message, 404)}, 404}

      {:ok, %Req.Response{status: status}} ->
        {{:error, Error.new(:api_error, "Unexpected response from the INE API", status)}, status}

      {:error, exception} ->
        {{:error, Error.new(:request_error, "Request failed: #{Exception.message(exception)}")},
         nil}
    end
  end

  defp decode_body(body) do
    case String.trim(body) do
      "" ->
        message =
          "The INE API returned an empty response. The requested resource " <>
            "(series, table, operation...) probably does not exist."

        {:error, Error.new(:not_found, message, 200)}

      <<char, _rest::binary>> = json when char in [?[, ?{] ->
        case JSON.decode(json) do
          {:ok, decoded} ->
            {:ok, decoded}

          {:error, reason} ->
            {:error, Error.new(:decode_error, "Invalid JSON: #{inspect(reason)}", 200)}
        end

      text ->
        {:error, Error.new(:api_error, "INE API error: #{ensure_utf8(text)}", 200)}
    end
  end

  defp ensure_utf8(text) do
    if String.valid?(text), do: text, else: :unicode.characters_to_binary(text, :latin1)
  end

  # Keep "/" so PC-Axis table ids ("t20/e245/p08/l0/01001.px") stay as path segments
  defp encode_input(input) do
    input
    |> to_string()
    |> URI.encode(&(URI.char_unreserved?(&1) or &1 == ?/))
  end

  defp base_url do
    :inex
    |> Application.get_env(:base_url, @default_base_url)
    |> String.trim_trailing("/")
  end

  @doc false
  def default_language, do: Application.get_env(:inex, :language, :es)
end
