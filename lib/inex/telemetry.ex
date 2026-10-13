defmodule Inex.Telemetry do
  @moduledoc """
  Telemetry integration for the Inex library.

  Inex emits telemetry events using `:telemetry.span/3` for every HTTP request
  made to the INE API. Each span produces the following events:

  ## Events

  ### `[:inex, :request, :start]`

  Emitted when a request begins.

  **Measurements:**

    - `:system_time` - System time at the start of the request (in native units)
    - `:monotonic_time` - Monotonic time at the start of the request

  **Metadata:**

    - `:function` - The INE API function being called (e.g. `"DATOS_SERIE"`)
    - `:url` - The full requested URL (including the query string)
    - `:params` - The query parameters sent to the INE API (keyword list)
    - `:language` - The language of the request (`:es` or `:en`)

  ### `[:inex, :request, :stop]`

  Emitted when a request completes (the HTTP round-trip finished, regardless of
  API-level errors like an empty response or a 404).

  **Measurements:**

    - `:duration` - Total wall-clock duration in native time units.
      Convert with `System.convert_time_unit(duration, :native, :millisecond)`.

  **Metadata:** everything from the `:start` event plus:

    - `:status` - HTTP status code, or `nil` if the request never got a response
    - `:result` - `:ok` or `:error`
    - `:error` - The `%Inex.Error{}` struct (only present when `:result` is `:error`)

  ### `[:inex, :request, :exception]`

  Emitted when the request raises an unexpected exception.

  **Measurements:**

    - `:duration` - Wall-clock duration until the exception

  **Metadata:** everything from the `:start` event plus `:kind`, `:reason` and `:stacktrace`.

  ## Attaching Handlers

  You can attach your own handlers to any of these events:

  ```elixir
  :telemetry.attach(
    "my-inex-handler",
    [:inex, :request, :stop],
    &MyApp.handle_inex_event/4,
    nil
  )
  ```

  Or use the built-in logger for quick request observability:

  ```elixir
  Inex.Telemetry.Logger.attach()
  ```
  """

  alias Inex.Error

  @doc false
  @spec span(map(), (-> {{:ok, term()} | {:error, Error.t()}, non_neg_integer() | nil})) ::
          {:ok, term()} | {:error, Error.t()}
  def span(metadata, fun) when is_map(metadata) and is_function(fun, 0) do
    :telemetry.span([:inex, :request], metadata, fn ->
      case fun.() do
        {{:ok, _body} = result, status} ->
          {result, Map.merge(metadata, %{status: status, result: :ok})}

        {{:error, %Error{} = error} = result, status} ->
          {result, Map.merge(metadata, %{status: status, result: :error, error: error})}
      end
    end)
  end
end
