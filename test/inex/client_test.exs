defmodule Inex.ClientTest do
  use Inex.Case, async: true

  alias Inex.Client
  alias Inex.Error

  describe "build_url/4" do
    test "builds the URL from the language, function and inputs" do
      assert Client.build_url("DATOS_SERIE", ["IPC290750"], [], :es) ==
               "https://servicios.ine.es/wstempus/js/ES/DATOS_SERIE/IPC290750"

      assert Client.build_url("VALORES_VARIABLEOPERACION", [762, "IPC"], [], :en) ==
               "https://servicios.ine.es/wstempus/js/EN/VALORES_VARIABLEOPERACION/762/IPC"
    end

    test "keeps slashes in PC-Axis table identifiers" do
      assert Client.build_url("DATOS_TABLA", ["t20/e245/p08/l0/01001.px"], [], :es) ==
               "https://servicios.ine.es/wstempus/js/ES/DATOS_TABLA/t20/e245/p08/l0/01001.px"
    end

    test "escapes unsafe characters in inputs" do
      assert Client.build_url("SERIE", ["A B"], [], :es) ==
               "https://servicios.ine.es/wstempus/js/ES/SERIE/A%20B"
    end

    test "encodes params keeping repeated keys and their order" do
      url = Client.build_url("DATOS_TABLA", [50913], [nult: 2, tv: "3:74", tv: "70:"], :es)

      assert url ==
               "https://servicios.ine.es/wstempus/js/ES/DATOS_TABLA/50913?nult=2&tv=3%3A74&tv=70%3A"
    end
  end

  describe "get/4" do
    test "returns the decoded JSON" do
      stub_ine({:fixture, "operacion_ipc"})

      assert {:ok, %{"Id" => 25, "Codigo" => "IPC"}} = Client.get("OPERACION", ["IPC"])
      assert [] = assert_ine_request("ES/OPERACION/IPC")
    end

    test "drops nil params and keeps repeated ones" do
      stub_ine({200, "[]"})

      assert {:ok, []} = Client.get("DATOS_TABLA", [1], nult: nil, tv: "1:2", tv: "1:3", det: 2)

      assert assert_ine_request("ES/DATOS_TABLA/1") == [
               {"tv", "1:2"},
               {"tv", "1:3"},
               {"det", "2"}
             ]
    end

    test "uses the language option" do
      stub_ine({:fixture, "operacion_ipc"})

      assert {:ok, _operation} = Client.get("OPERACION", ["IPC"], [], language: :en)
      assert_ine_request("EN/OPERACION/IPC")
    end

    test "sends an inex user agent" do
      stub_ine({200, "[]"})

      Client.get("PERIODICIDADES")

      assert_received {:ine_request, %{headers: headers}}
      assert {"user-agent", "inex/" <> _version} = List.keyfind(headers, "user-agent", 0)
    end

    test "an empty body means the resource does not exist" do
      stub_ine({200, ""})

      assert {:error, %Error{type: :not_found, status: 200}} = Client.get("SERIE", ["NOPE"])
    end

    test "a plain text body is an API error message" do
      stub_ine({200, "La operación indicada no existe (NOFUNC)\n"})

      assert {:error, %Error{type: :api_error, message: message}} = Client.get("NOFUNC", [1])
      assert message =~ "La operación indicada no existe (NOFUNC)"
    end

    test "latin-1 error messages are converted to UTF-8" do
      stub_ine({200, <<"Operaci", 0xF3, "n inv", 0xE1, "lida">>})

      assert {:error, %Error{type: :api_error, message: message}} = Client.get("X")
      assert message =~ "Operación inválida"
    end

    test "invalid JSON is a decode error" do
      stub_ine({200, ~s({"COD": )})

      assert {:error, %Error{type: :decode_error}} = Client.get("SERIE", ["X"])
    end

    test "a 404 means not found or invalid parameters" do
      stub_ine({404, "<html>404</html>"})

      assert {:error, %Error{type: :not_found, status: 404}} =
               Client.get("DATOS_SERIE", ["IPC290750"])
    end

    test "other statuses are API errors" do
      stub_ine({503, "Service Unavailable"})

      assert {:error, %Error{type: :api_error, status: 503} = error} = Client.get("SERIE", ["X"])
      assert Exception.message(error) =~ "(HTTP 503)"
    end

    test "transport failures are request errors" do
      stub_ine(&Req.Test.transport_error(&1, :timeout))

      assert {:error, %Error{type: :request_error, message: message}} = Client.get("SERIE", ["X"])
      assert message =~ "timeout"
    end
  end

  describe "get_all_pages/4" do
    test "requests pages until an empty one and concatenates them" do
      stub_ine(fn conn ->
        body =
          case conn.query_string |> URI.decode_query() |> Map.fetch!("page") do
            "1" -> ~s([{"Id": 1}, {"Id": 2}])
            "2" -> ~s([{"Id": 3}])
            "3" -> "[]"
          end

        Plug.Conn.send_resp(conn, 200, body)
      end)

      assert {:ok, [%{"Id" => 1}, %{"Id" => 2}, %{"Id" => 3}]} =
               Client.get_all_pages("SERIES_OPERACION", ["IPC"], det: 1, page: 7)

      pages = Enum.map(ine_requests(), & &1.params)

      assert pages == [
               [{"det", "1"}, {"page", "1"}],
               [{"det", "1"}, {"page", "2"}],
               [{"det", "1"}, {"page", "3"}]
             ]
    end

    test "an empty body after the first page also ends the pagination" do
      stub_ine(fn conn ->
        body = if conn.query_string == "page=1", do: ~s([{"Id": 1}]), else: ""
        Plug.Conn.send_resp(conn, 200, body)
      end)

      assert {:ok, [%{"Id" => 1}]} = Client.get_all_pages("VARIABLES")
    end

    test "returns the first error" do
      stub_ine({200, ""})

      assert {:error, %Error{type: :not_found}} =
               Client.get_all_pages("SERIES_OPERACION", ["NOPE"])
    end
  end
end
