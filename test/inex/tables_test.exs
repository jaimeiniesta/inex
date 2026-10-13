defmodule Inex.TablesTest do
  use Inex.Case, async: true

  alias Explorer.DataFrame, as: DF
  alias Inex.Error
  alias Inex.Tables

  @px_table "t20/e245/p08/l0/01001.px"

  describe "observations/2" do
    test "requests DATOS_TABLA with tv filters" do
      stub_ine({:fixture, "datos_tabla_76136_metadata"})

      assert {:ok, [%{"COD" => "IPC290750"} | _]} =
               Tables.observations(76136,
                 last: 2,
                 metadata: true,
                 friendly: true,
                 filters: [data_type: 74, cpi_group: 304_092]
               )

      assert assert_ine_request("ES/DATOS_TABLA/76136") == [
               {"tip", "AM"},
               {"nult", "2"},
               {"tv", "3:74"},
               {"tv", "762:304092"}
             ]
    end

    test "does not force a date range (DATOS_TABLA returns everything without one)" do
      stub_ine({:fixture, "datos_tabla_76136_metadata"})

      assert {:ok, _series} = Tables.observations(76136)
      assert [] = assert_ine_request("ES/DATOS_TABLA/76136")
    end

    test "supports PC-Axis tables" do
      stub_ine({:fixture, "datos_tabla_px"})

      assert {:ok, [%{"Nombre" => _name} | _]} =
               Tables.observations(@px_table,
                 last: 2,
                 filters: [{"sexo", :all}, {"espanolesextranjeros", "espanoles"}]
               )

      assert [{"nult", "2"}, {"tv", "sexo:"}, {"tv", "espanolesextranjeros:espanoles"}] =
               assert_ine_request("ES/DATOS_TABLA/" <> @px_table)
    end

    test "validates the filters" do
      assert {:error, %Error{type: :option_error, message: message}} =
               Tables.observations(76136, filters: [galaxy: 1])

      assert message =~ "invalid filter"
    end
  end

  describe "observations_as_data_frame/2" do
    test "returns a long data frame with metadata by default" do
      stub_ine({:fixture, "datos_tabla_76136_metadata"})

      assert {:ok, df} =
               Tables.observations_as_data_frame(76136,
                 last: 2,
                 filters: [data_type: 74, cpi_group: 304_092]
               )

      assert DF.n_rows(df) == 21
      assert "Comunidades y Ciudades Autónomas" in DF.names(df)

      assert [{"tip", "AM"}, {"nult", "2"}, {"tv", "3:74"}, {"tv", "762:304092"}] =
               assert_ine_request("ES/DATOS_TABLA/76136")
    end

    test "returns a wide data frame without metadata" do
      stub_ine({:fixture, "datos_tabla_76136_metadata"})

      assert {:ok, df} = Tables.observations_as_data_frame(76136, format: :wide, metadata: false)

      assert ["date", "IPC290750" | _] = DF.names(df)
      assert [{"tip", "A"}] = assert_ine_request("ES/DATOS_TABLA/76136")
    end

    test "works with PC-Axis tables" do
      stub_ine({:fixture, "datos_tabla_px"})

      df = Tables.observations_as_data_frame!(@px_table, format: :wide)

      assert DF.names(df) == [
               "date",
               "TOTAL EDADES, Españoles, Ambos sexos",
               "TOTAL EDADES, Españoles, Hombres",
               "TOTAL EDADES, Españoles, Mujeres"
             ]
    end

    test "the bang variant raises" do
      stub_ine({200, ""})

      assert_raise Error, fn -> Tables.observations_as_data_frame!(1) end
    end
  end

  test "series/2 requests SERIES_TABLA" do
    stub_ine({:fixture, "series_tabla_px_metadata"})

    assert {:ok, [%{"MetaData" => [_ | _]} | _]} =
             Tables.series(@px_table, metadata: true, filters: [{"sexo", "mujeres"}])

    assert [{"tip", "M"}, {"tv", "sexo:mujeres"}] =
             assert_ine_request("ES/SERIES_TABLA/" <> @px_table)
  end

  test "groups/2 requests GRUPOS_TABLA" do
    stub_ine({:fixture, "grupos_tabla_76136"})

    assert {:ok, [%{"Id" => 155_612}, %{"Id" => 155_613}, %{"Id" => 155_614}]} =
             Tables.groups(76136)

    assert_ine_request("ES/GRUPOS_TABLA/76136")
  end

  test "group_values/3 requests VALORES_GRUPOSTABLA" do
    stub_ine({:fixture, "valores_grupostabla_76136_155614"})

    assert {:ok, [%{"Variable" => %{"Id" => 3}} | _]} =
             Tables.group_values(76136, 155_614, detail: 1)

    assert [{"det", "1"}] = assert_ine_request("ES/VALORES_GRUPOSTABLA/76136/155614")
  end

  describe "values/2" do
    test "collects the values of every group of a Tempus3 table" do
      stub_ine(%{
        "GRUPOS_TABLA/76136" => {:fixture, "grupos_tabla_76136"},
        "VALORES_GRUPOSTABLA/76136/155612" => {:fixture, "valores_grupostabla_76136_155612"},
        "VALORES_GRUPOSTABLA/76136/155613" => {:fixture, "valores_grupostabla_76136_155613"},
        "VALORES_GRUPOSTABLA/76136/155614" => {:fixture, "valores_grupostabla_76136_155614"}
      })

      assert {:ok, values} = Tables.values(76136)

      assert Enum.any?(values, &(&1["Nombre"] == "Andalucía"))
      assert Enum.any?(values, &(&1["Nombre"] == "Variación anual" and &1["Variable"]["Id"] == 3))

      requests = ine_requests()
      assert length(requests) == 4
      assert requests |> Enum.drop(1) |> Enum.all?(&(&1.params == [{"det", "1"}]))
    end

    test "extracts the values of PC-Axis/tpx tables from the series metadata" do
      stub_ine(%{
        ("GRUPOS_TABLA/" <> @px_table) => {200, ""},
        ("SERIES_TABLA/" <> @px_table) => {:fixture, "series_tabla_px_metadata"}
      })

      assert {:ok, values} = Tables.values(@px_table)

      assert %{
               "Codigo" => "mujeres",
               "Nombre" => "Mujeres",
               "Variable" => %{"Nombre" => "Sexo", "Codigo" => "sexo"}
             } in values

      assert %{
               "Codigo" => "espanoles",
               "Nombre" => "Españoles",
               "Variable" => %{
                 "Nombre" => "Españoles/Extranjeros",
                 "Codigo" => "espanolesextranjeros"
               }
             } in values

      assert values == Enum.uniq(values)
    end

    test "falls back to the series metadata when GRUPOS_TABLA returns a 404 (tpx tables)" do
      stub_ine(%{
        "GRUPOS_TABLA/33387" => {404, "Not found"},
        "SERIES_TABLA/33387" => {:fixture, "series_tabla_px_metadata"}
      })

      assert {:ok, [_ | _]} = Tables.values(33387)
    end

    test "returns other errors" do
      stub_ine({503, "Unavailable"})

      assert {:error, %Error{type: :api_error}} = Tables.values(76136)
    end
  end

  test "variable_code/1 builds the codes the INE expects for PC-Axis and tpx variables" do
    assert Tables.variable_code("edad (3 grupos de edad)") == "edad3gruposdeedad"
    assert Tables.variable_code("Españoles/Extranjeros") == "espanolesextranjeros"
    assert Tables.variable_code("tipo de material") == "tipodematerial"
    assert Tables.variable_code(nil) == nil
  end

  test "operation/2 requests OPERACIONES_TABLA" do
    stub_ine({:fixture, "operaciones_tabla_76136"})

    assert {:ok, [%{"Codigo" => "IPC"}]} = Tables.operation(76136)
    assert_ine_request("ES/OPERACIONES_TABLA/76136")
  end
end
