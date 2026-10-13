defmodule Inex.Telemetry.Logger do
  @moduledoc """
  A built-in telemetry handler that logs INE API request details using Elixir's `Logger`.

  Attach it in your application's `start/2` callback (or at the top of a
  Livebook) for quick observability:

  ```elixir
  Inex.Telemetry.Logger.attach()
  ```

  ## Output

  On every completed request (`:stop` event) it logs at the configured level:

  ```
  [inex] GET DATOS_SERIE/IPC290750 - 200 in 142ms (params: [nult: 12, tip: "A"])
  ```

  On errors:

  ```
  [inex] GET SERIE/NOPE - error in 83ms: (HTTP 200) The INE API returned an empty response... (params: [])
  ```

  On exceptions (`:exception` event):

  ```
  [inex] GET DATOS_TABLA/50902 - exception in 5012ms: %RuntimeError{message: "boom"}
  ```

  ## Configuration

  ```elixir
  Inex.Telemetry.Logger.attach(
    level: :info,              # Logger level (default: :info)
    handler_id: "my-inex-log"  # Unique handler ID (default: "inex-default-logger")
  )
  ```

  ## Detaching

  ```elixir
  Inex.Telemetry.Logger.detach()

  # or with a custom ID:
  Inex.Telemetry.Logger.detach("my-inex-log")
  ```
  """

  require Logger

  @default_id "inex-default-logger"

  @doc """
  Attaches the logger handler to the Inex telemetry events.

  ## Options

    - `:level` - The `Logger` level to log at. Default: `:info`
    - `:handler_id` - A unique string ID for this handler. Default: `"inex-default-logger"`.

  Returns `:ok` or `{:error, :already_exists}` if the handler ID is taken.
  """
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    level = Keyword.get(opts, :level, :info)
    handler_id = Keyword.get(opts, :handler_id, @default_id)

    :telemetry.attach_many(
      handler_id,
      [[:inex, :request, :stop], [:inex, :request, :exception]],
      &__MODULE__.handle_event/4,
      %{level: level}
    )
  end

  @doc """
  Detaches the logger handler. Defaults to the `"inex-default-logger"` handler ID.
  """
  @spec detach(String.t()) :: :ok | {:error, :not_found}
  def detach(handler_id \\ @default_id) do
    :telemetry.detach(handler_id)
  end

  @doc false
  def handle_event([:inex, :request, :stop], measurements, metadata, config) do
    duration = duration_ms(measurements)

    message =
      case metadata[:result] do
        :ok ->
          "[inex] GET #{endpoint(metadata)} - #{metadata[:status]} in #{duration}ms#{format_params(metadata)}"

        :error ->
          error_detail =
            if error = metadata[:error], do: ": #{Exception.message(error)}", else: ""

          "[inex] GET #{endpoint(metadata)} - error in #{duration}ms#{error_detail}#{format_params(metadata)}"
      end

    Logger.log(config.level, message)
  end

  def handle_event([:inex, :request, :exception], measurements, metadata, config) do
    message =
      "[inex] GET #{endpoint(metadata)} - exception in #{duration_ms(measurements)}ms: " <>
        "#{inspect(metadata[:reason])}#{format_params(metadata)}"

    Logger.log(config.level, message)
  end

  defp duration_ms(%{duration: duration}),
    do: System.convert_time_unit(duration, :native, :millisecond)

  # Shows the API function plus its inputs, e.g. "DATOS_SERIE/IPC290750"
  defp endpoint(%{url: url, function: function}) do
    path = URI.parse(url).path || ""

    case String.split(path, "/#{function}", parts: 2) do
      [_prefix, inputs] -> function <> inputs
      _ -> function
    end
  end

  defp format_params(%{params: [_ | _] = params}), do: " (params: #{inspect(params)})"
  defp format_params(_metadata), do: ""
end
