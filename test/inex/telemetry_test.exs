defmodule Inex.TelemetryTest do
  # Telemetry handlers are global, so these tests can't run concurrently with others
  use Inex.Case, async: false

  import ExUnit.CaptureLog

  alias Inex.Telemetry.Logger, as: TelemetryLogger

  setup context do
    test_pid = self()
    handler_id = "inex-test-#{inspect(context.test)}"

    :telemetry.attach_many(
      handler_id,
      [[:inex, :request, :start], [:inex, :request, :stop], [:inex, :request, :exception]],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
  end

  test "emits start and stop events for successful requests" do
    stub_ine({:fixture, "operacion_ipc"})

    assert {:ok, _operation} = Inex.Operations.get("IPC", detail: 1)

    assert_received {:telemetry, [:inex, :request, :start], %{system_time: _}, start_metadata}

    assert %{function: "OPERACION", params: [det: 1], language: :es, url: url} = start_metadata
    assert url == "https://servicios.ine.es/wstempus/js/ES/OPERACION/IPC?det=1"

    assert_received {:telemetry, [:inex, :request, :stop], %{duration: duration}, stop_metadata}
    assert is_integer(duration)
    assert %{status: 200, result: :ok, function: "OPERACION"} = stop_metadata
  end

  test "includes the error in the stop event" do
    stub_ine({200, ""})

    assert {:error, _error} = Inex.Series.get("NOPE")

    assert_received {:telemetry, [:inex, :request, :stop], _measurements, metadata}
    assert %{result: :error, status: 200, error: %Inex.Error{type: :not_found}} = metadata
  end

  test "emits an exception event when the request raises" do
    stub_ine(fn _conn -> raise "boom" end)

    assert_raise RuntimeError, "boom", fn -> Inex.Series.get("IPC290750") end

    assert_received {:telemetry, [:inex, :request, :exception], _measurements, %{kind: :error}}
  end

  describe "Inex.Telemetry.Logger" do
    setup do
      on_exit(fn -> TelemetryLogger.detach() end)
    end

    test "logs successful requests" do
      stub_ine({:fixture, "datos_serie_ipc290750"})
      :ok = TelemetryLogger.attach(level: :warning)

      log = capture_log(fn -> Inex.Series.observations("IPC290750", last: 5) end)

      assert log =~ ~r/\[inex\] GET DATOS_SERIE\/IPC290750 - 200 in \d+ms \(params: \[nult: 5\]\)/
    end

    test "logs errors" do
      stub_ine({200, ""})
      :ok = TelemetryLogger.attach(level: :warning)

      log = capture_log(fn -> Inex.Series.get("NOPE") end)

      assert log =~ "[inex] GET SERIE/NOPE - error in"
      assert log =~ "empty response"
    end

    test "logs exceptions" do
      stub_ine(fn _conn -> raise "boom" end)
      :ok = TelemetryLogger.attach(level: :warning)

      log = capture_log(fn -> catch_error(Inex.Series.get("IPC290750")) end)

      assert log =~ "[inex] GET SERIE/IPC290750 - exception in"
      assert log =~ "boom"
    end

    test "can't be attached twice with the same id" do
      assert :ok = TelemetryLogger.attach()
      assert {:error, :already_exists} = TelemetryLogger.attach()
      assert :ok = TelemetryLogger.detach()
      assert {:error, :not_found} = TelemetryLogger.detach()
    end
  end
end
