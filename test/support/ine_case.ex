defmodule Inex.Case do
  @moduledoc """
  Test case for code that talks to the INE API.

  Requests are routed to `Req.Test` (see `config/test.exs`) and answered with
  real responses captured from the API (`test/support/fixtures`). Every request
  is reported to the test process so tests can assert on the exact function,
  inputs and query parameters sent to the INE.
  """

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  @fixtures_path Path.expand("fixtures", __DIR__)
  @api_path "/wstempus/js"

  using do
    quote do
      import Inex.Case
    end
  end

  @doc "Raw body of a fixture."
  def fixture(name), do: File.read!(Path.join(@fixtures_path, "#{name}.json"))

  @doc "Decoded fixture."
  def fixture!(name), do: name |> fixture() |> JSON.decode!()

  @doc """
  Stubs the INE API.

  `response` can be:

    - `{:fixture, name}` - 200 with the body of the fixture
    - `{status, body}` - the given status and raw body
    - a map of `"FUNCTION/inputs" => response` to route by path, e.g.
      `%{"GRUPOS_TABLA/76136" => {:fixture, "grupos_tabla_76136"}}`
    - a `fun(conn)` plug
  """
  def stub_ine(response) do
    test_pid = self()

    Req.Test.stub(Inex.Client, fn conn ->
      request = %{
        path: conn.request_path,
        endpoint: endpoint(conn.request_path),
        params: conn.query_string |> URI.query_decoder() |> Enum.to_list(),
        headers: conn.req_headers
      }

      send(test_pid, {:ine_request, request})
      respond(conn, response, request)
    end)
  end

  @doc """
  Asserts that a request was made to `endpoint` (e.g. `"ES/DATOS_SERIE/IPC290750"`)
  and returns its query params as a list of `{key, value}` string tuples.
  """
  def assert_ine_request(endpoint) do
    assert_received {:ine_request, %{endpoint: ^endpoint} = request}
    request.params
  end

  @doc "Returns every request received so far, in order."
  def ine_requests(acc \\ []) do
    receive do
      {:ine_request, request} -> ine_requests([request | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp respond(conn, {:fixture, name}, _request), do: send_json(conn, 200, fixture(name))
  defp respond(conn, {status, body}, _request), do: send_json(conn, status, body)
  defp respond(conn, fun, _request) when is_function(fun, 1), do: fun.(conn)

  defp respond(conn, routes, %{endpoint: endpoint}) when is_map(routes) do
    route = endpoint |> String.split("/", parts: 2) |> List.last()

    case Map.fetch(routes, route) do
      {:ok, response} -> respond(conn, response, nil)
      :error -> send_json(conn, 500, "Unexpected request in test: #{route}")
    end
  end

  defp send_json(conn, status, body) do
    conn
    |> Plug.Conn.put_resp_content_type("application/json")
    |> Plug.Conn.send_resp(status, body)
  end

  # "/wstempus/js/ES/DATOS_SERIE/IPC290750" -> "ES/DATOS_SERIE/IPC290750"
  defp endpoint(@api_path <> "/" <> endpoint), do: endpoint
  defp endpoint(path), do: path
end
