defmodule Inex.OperationsTest do
  use Inex.Case, async: true

  alias Inex.Error
  alias Inex.Operations

  describe "list/1" do
    test "requests OPERACIONES_DISPONIBLES" do
      stub_ine({:fixture, "operaciones_disponibles"})

      assert {:ok, [%{"Id" => 4, "Codigo" => "EI"} | _]} = Operations.list()
      assert [] = assert_ine_request("ES/OPERACIONES_DISPONIBLES")
    end

    test "translates the options" do
      stub_ine({:fixture, "operaciones_disponibles"})

      assert {:ok, _operations} =
               Operations.list(detail: 2, geo: :regional, page: 1, language: :en)

      assert assert_ine_request("EN/OPERACIONES_DISPONIBLES") == [
               {"det", "2"},
               {"geo", "1"},
               {"page", "1"}
             ]
    end

    test "fetches every page with page: :all" do
      stub_ine(fn conn ->
        body =
          if conn.query_string == "page=1", do: fixture("operaciones_disponibles"), else: "[]"

        Plug.Conn.send_resp(conn, 200, body)
      end)

      assert {:ok, operations} = Operations.list(page: :all)
      assert length(operations) == 15
      assert length(ine_requests()) == 2
    end

    test "validates the options" do
      assert {:error, %Error{type: :option_error}} = Operations.list(geo: :galaxy)
      assert {:error, %Error{type: :option_error}} = Operations.list(page: 0)
      refute_received {:ine_request, _request}
    end
  end

  describe "get/2" do
    test "requests OPERACION with any kind of identifier" do
      stub_ine({:fixture, "operacion_ipc"})

      assert {:ok, %{"Id" => 25, "Cod_IOE" => "30138", "Codigo" => "IPC"}} = Operations.get("IPC")
      assert {:ok, _operation} = Operations.get(25, detail: 1)
      assert {:ok, _operation} = Operations.get("IOE30138")

      assert [] = assert_ine_request("ES/OPERACION/IPC")
      assert [{"det", "1"}] = assert_ine_request("ES/OPERACION/25")
      assert [] = assert_ine_request("ES/OPERACION/IOE30138")
    end

    test "returns not found for unknown operations" do
      stub_ine({200, ""})

      assert {:error, %Error{type: :not_found}} = Operations.get("NOPE")
    end
  end

  test "variables/2 requests VARIABLES_OPERACION" do
    stub_ine({:fixture, "variables_operacion_ipc"})

    assert {:ok, [%{"Id" => 3, "Nombre" => "Tipo de dato"} | _]} =
             Operations.variables("IPC", page: 1)

    assert [{"page", "1"}] = assert_ine_request("ES/VARIABLES_OPERACION/IPC")
  end

  test "variable_values/3 requests VALORES_VARIABLEOPERACION with the variable first" do
    stub_ine({:fixture, "valores_variableoperacion_762_ipc"})

    assert {:ok, [%{"Id" => 304_092, "Nombre" => "Índice general"} | _]} =
             Operations.variable_values("IPC", 762, detail: 1)

    assert [{"det", "1"}] = assert_ine_request("ES/VALORES_VARIABLEOPERACION/762/IPC")
  end

  test "tables/2 requests TABLAS_OPERACION" do
    stub_ine({:fixture, "tablas_operacion_ipc"})

    assert {:ok, [%{"Id" => _id, "Nombre" => _name} | _]} =
             Operations.tables("IPC", geo: :national, friendly: true, detail: 2)

    assert [{"det", "2"}, {"tip", "A"}, {"geo", "0"}] =
             assert_ine_request("ES/TABLAS_OPERACION/IPC")
  end

  describe "series/2" do
    test "requests the first page of SERIES_OPERACION by default" do
      stub_ine({:fixture, "series_operacion_ipc_page1"})

      assert {:ok, [%{"COD" => "IPC53262"} | _]} = Operations.series("IPC")
      assert [{"page", "1"}] = assert_ine_request("ES/SERIES_OPERACION/IPC")
    end

    test "translates the options" do
      stub_ine({:fixture, "series_operacion_ipc_page1"})

      assert {:ok, _series} =
               Operations.series("IPC", page: 2, friendly: true, metadata: true, detail: 1)

      assert [{"det", "1"}, {"tip", "AM"}, {"page", "2"}] =
               assert_ine_request("ES/SERIES_OPERACION/IPC")
    end
  end

  test "classifications/2 requests CLASIFICACIONES_OPERACION" do
    stub_ine({:fixture, "clasificaciones_operacion_ipc"})

    assert {:ok, [%{"Nombre" => "Base 1976"} | _]} = Operations.classifications("IPC")
    assert_ine_request("ES/CLASIFICACIONES_OPERACION/IPC")
  end

  test "publications/2 requests PUBLICACIONES_OPERACION" do
    stub_ine({:fixture, "publicaciones_operacion_ipc"})

    assert {:ok, [%{"Id" => 8} | _]} = Operations.publications("IPC", friendly: true)
    assert [{"tip", "A"}] = assert_ine_request("ES/PUBLICACIONES_OPERACION/IPC")
  end

  test "periodicities/2 requests PERIODICIDAD_OPERACION" do
    stub_ine({:fixture, "periodicidad_operacion_ipc"})

    assert {:ok, [%{"Nombre" => "Mensual"}, %{"Nombre" => "Anual"}]} =
             Operations.periodicities("IPC")

    assert_ine_request("ES/PERIODICIDAD_OPERACION/IPC")
  end
end
