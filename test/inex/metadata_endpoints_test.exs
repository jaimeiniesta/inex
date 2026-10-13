defmodule Inex.MetadataEndpointsTest do
  use Inex.Case, async: true

  alias Inex.Error

  describe "Inex.Variables" do
    test "list/1 requests VARIABLES" do
      stub_ine({200, ~s([{"Id": 349, "Nombre": "Totales Territoriales", "Codigo": "NAC"}])})

      assert {:ok, [%{"Id" => 349}]} = Inex.Variables.list(page: 2)
      assert [{"page", "2"}] = assert_ine_request("ES/VARIABLES")
    end

    test "values/2 requests VALORES_VARIABLE" do
      stub_ine({:fixture, "valores_variable_115"})

      assert {:ok, [%{"Nombre" => "Total Nacional"} | _]} =
               Inex.Variables.values(115, classification: 121, detail: 2)

      assert [{"det", "2"}, {"clasif", "121"}] = assert_ine_request("ES/VALORES_VARIABLE/115")
    end

    test "children/3 requests VALORES_HIJOS" do
      stub_ine({:fixture, "valores_hijos_70_8997"})

      assert {:ok, [%{"Nombre" => "Almería"} | _]} = Inex.Variables.children(70, 8997)
      assert_ine_request("ES/VALORES_HIJOS/70/8997")
    end

    test "validates the options" do
      assert {:error, %Error{type: :option_error}} =
               Inex.Variables.values(115, classification: "x")
    end
  end

  describe "Inex.Publications" do
    test "list/1 requests PUBLICACIONES" do
      stub_ine({:fixture, "publicaciones_operacion_ipc"})

      assert {:ok, [_ | _]} = Inex.Publications.list(detail: 1, friendly: true)
      assert [{"det", "1"}, {"tip", "A"}] = assert_ine_request("ES/PUBLICACIONES")
    end

    test "dates/2 requests PUBLICACIONFECHA_PUBLICACION" do
      stub_ine({:fixture, "publicacionfecha_publicacion_8"})

      assert {:ok, [%{"Fecha" => "20" <> _} | _]} = Inex.Publications.dates(8, friendly: true)
      assert [{"tip", "A"}] = assert_ine_request("ES/PUBLICACIONFECHA_PUBLICACION/8")
    end
  end

  test "Inex.Classifications.list/1 requests CLASIFICACIONES" do
    stub_ine({:fixture, "clasificaciones"})

    assert {:ok, [%{"Nombre" => "CNAE 93"} | _]} = Inex.Classifications.list(language: :en)
    assert_ine_request("EN/CLASIFICACIONES")
  end

  describe "Inex.Periodicities" do
    test "list/1 requests PERIODICIDADES" do
      stub_ine({:fixture, "periodicidades"})

      assert {:ok, periodicities} = Inex.Periodicities.list()
      assert %{"Id" => 3, "Nombre" => "Trimestral"} = Enum.find(periodicities, &(&1["Id"] == 3))
      assert_ine_request("ES/PERIODICIDADES")
    end

    test "periods/2 requests PERIODOS_PERIODICIDAD" do
      stub_ine({:fixture, "periodos_periodicidad_3"})

      assert {:ok, [%{"Id" => 19, "Nombre" => "T1"} | _]} = Inex.Periodicities.periods(3)
      assert_ine_request("ES/PERIODOS_PERIODICIDAD/3")
    end
  end

  test "Inex.Units.list/1 requests UNIDADES" do
    stub_ine({:fixture, "unidades"})

    assert {:ok, [%{"Nombre" => "Personas"} | _]} = Inex.Units.list()
    assert_ine_request("ES/UNIDADES")
  end

  test "Inex.Scales.list/1 requests ESCALAS" do
    stub_ine({:fixture, "escalas"})

    assert {:ok, [%{"Factor" => "1E0"} | _]} = Inex.Scales.list()
    assert_ine_request("ES/ESCALAS")
  end
end
