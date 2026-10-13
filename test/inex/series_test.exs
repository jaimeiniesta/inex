defmodule Inex.SeriesTest do
  use Inex.Case, async: true

  alias Explorer.DataFrame, as: DF
  alias Inex.Error
  alias Inex.Series

  test "get/2 requests SERIE" do
    stub_ine({:fixture, "serie_ipc290750"})

    assert {:ok, %{"COD" => "IPC290750", "FK_Periodicidad" => 1}} =
             Series.get("IPC290750", detail: 2, friendly: true, metadata: true)

    assert [{"det", "2"}, {"tip", "AM"}] = assert_ine_request("ES/SERIE/IPC290750")
  end

  test "metadata/2 requests VALORES_SERIE" do
    stub_ine({:fixture, "valores_serie_ipc290750"})

    assert {:ok, [%{"Nombre" => "Nacional", "Variable" => %{"Id" => 349}} | _]} =
             Series.metadata("IPC290750", detail: 1)

    assert [{"det", "1"}] = assert_ine_request("ES/VALORES_SERIE/IPC290750")
  end

  describe "observations/2" do
    test "requests DATOS_SERIE with nult" do
      stub_ine({:fixture, "datos_serie_ipc290750"})

      assert {:ok, %{"COD" => "IPC290750", "Data" => [_, _, _, _, _]}} =
               Series.observations("IPC290750", last: 5)

      assert [{"nult", "5"}] = assert_ine_request("ES/DATOS_SERIE/IPC290750")
    end

    test "requests all the observations by default" do
      stub_ine({:fixture, "datos_serie_ipc290750"})

      assert {:ok, _series} = Series.observations("IPC290750")
      assert [{"date", "18000101:"}] = assert_ine_request("ES/DATOS_SERIE/IPC290750")
    end

    test "sends the date ranges" do
      stub_ine({:fixture, "datos_serie_ipc290750"})

      assert {:ok, _series} =
               Series.observations("IPC290750",
                 observation_start: ~D[2024-01-01],
                 observation_end: ~D[2024-12-31],
                 dates: [~D[2020-01-01]],
                 friendly: true
               )

      assert [{"tip", "A"}, {"date", "20240101:20241231"}, {"date", "20200101:20200101"}] =
               assert_ine_request("ES/DATOS_SERIE/IPC290750")
    end

    test "validates the options" do
      assert {:error, %Error{type: :option_error}} = Series.observations("IPC290750", last: 0)

      assert {:error, %Error{type: :option_error}} =
               Series.observations("IPC290750",
                 observation_start: ~D[2025-01-01],
                 observation_end: ~D[2024-01-01]
               )

      assert {:error, %Error{type: :option_error}} =
               Series.observations("IPC290750", filters: [{3, 74}])
    end
  end

  describe "observations_as_data_frame/2" do
    setup do
      stub_ine(%{
        "DATOS_SERIE/IPC290750" => {:fixture, "datos_serie_ipc290750_friendly"},
        "DATOS_SERIE/EPA452434" => {:fixture, "datos_serie_epa452434_friendly"},
        "DATOS_SERIE/NOPE" => {200, ""}
      })

      :ok
    end

    test "returns a wide data frame with one column per series" do
      assert {:ok, df} = Series.observations_as_data_frame("IPC290750", last: 5)

      assert DF.names(df) == ["date", "IPC290750"]
      assert DF.n_rows(df) == 5
      assert Explorer.Series.to_list(df["IPC290750"]) == [3.2, 3.2, 3.6, 4.3, 4.9]

      # Always requests friendly responses
      assert [{"tip", "A"}, {"nult", "5"}] = assert_ine_request("ES/DATOS_SERIE/IPC290750")
    end

    test "combines several series with different periodicities" do
      assert {:ok, df} = Series.observations_as_data_frame(["IPC290750", "EPA452434"], last: 5)

      assert DF.names(df) == ["date", "IPC290750", "EPA452434"]
      dates = Explorer.Series.to_list(df["date"])
      assert dates == Enum.sort(dates, Date)
      assert ~D[2025-07-01] in dates
      assert ~D[2026-09-01] in dates

      assert length(ine_requests()) == 2
    end

    test "renames columns" do
      assert {:ok, df} =
               Series.observations_as_data_frame(["IPC290750", "EPA452434"],
                 rename: %{"IPC290750" => "cpi", "EPA452434" => "unemployment"}
               )

      assert DF.names(df) == ["date", "cpi", "unemployment"]
    end

    test "returns a long data frame" do
      assert {:ok, df} =
               Series.observations_as_data_frame(["IPC290750", "EPA452434"], format: :long)

      assert ["code", "name", "date" | _] = DF.names(df)
      assert DF.n_rows(df) == 9

      assert df["code"] |> Explorer.Series.distinct() |> Explorer.Series.to_list() == [
               "IPC290750",
               "EPA452434"
             ]
    end

    test "requests metadata when asked to" do
      assert {:ok, _df} =
               Series.observations_as_data_frame("IPC290750", format: :long, metadata: true)

      assert [{"tip", "AM"}, {"date", "18000101:"}] =
               assert_ine_request("ES/DATOS_SERIE/IPC290750")
    end

    test "returns the error of the first series that fails" do
      assert {:error, %Error{type: :not_found, message: "NOPE: " <> _}} =
               Series.observations_as_data_frame(["IPC290750", "NOPE"])
    end

    test "validates the options" do
      assert {:error, %Error{type: :option_error}} =
               Series.observations_as_data_frame("IPC290750", format: :tall)

      assert {:error, %Error{type: :option_error}} =
               Series.observations_as_data_frame("IPC290750", detail: 2)
    end

    test "the bang variant returns the data frame or raises" do
      assert %DF{} = Series.observations_as_data_frame!("IPC290750")

      assert_raise Error, ~r/NOPE/, fn -> Series.observations_as_data_frame!("NOPE") end
    end
  end

  describe "search/2" do
    test "requests SERIE_METADATAOPERACION with g filters" do
      stub_ine({:fixture, "serie_metadataoperacion_ipc"})

      assert {:ok, [%{"COD" => _code} | _]} =
               Series.search("IPC",
                 filters: [national: 16473, cpi_group: 304_092, data_type: :all],
                 periodicity: :monthly
               )

      assert assert_ine_request("ES/SERIE_METADATAOPERACION/IPC") == [
               {"p", "1"},
               {"g1", "349:16473"},
               {"g2", "762:304092"},
               {"g3", "3:"},
               {"page", "1"}
             ]
    end
  end

  describe "search_observations/2" do
    test "requests DATOS_METADATAOPERACION" do
      stub_ine({:fixture, "datos_metadataoperacion_ipc"})

      assert {:ok, [_ | _]} =
               Series.search_observations("IPC", filters: [{115, [29, 8]}], last: 2)

      assert assert_ine_request("ES/DATOS_METADATAOPERACION/IPC") == [
               {"nult", "2"},
               {"g1", "115:29"},
               {"g1", "115:8"},
               {"page", "1"}
             ]
    end

    test "requests all the observations by default" do
      stub_ine({:fixture, "datos_metadataoperacion_ipc"})

      assert {:ok, _series} = Series.search_observations("IPC", filters: [{3, 74}])

      assert [{"g1", "3:74"}, {"page", "1"}, {"date", "18000101:"}] =
               assert_ine_request("ES/DATOS_METADATAOPERACION/IPC")
    end
  end

  describe "search_observations_as_data_frame/2" do
    test "returns a long data frame with metadata columns" do
      stub_ine({:fixture, "datos_metadataoperacion_ipc"})

      assert {:ok, df} =
               Series.search_observations_as_data_frame("IPC",
                 filters: [national: 16473, cpi_group: 304_092, data_type: :all],
                 periodicity: :monthly,
                 last: 2
               )

      assert "Índices y Tasas" in DF.names(df)

      assert [{"tip", "AM"}, {"p", "1"}, {"nult", "2"} | _] =
               assert_ine_request("ES/DATOS_METADATAOPERACION/IPC")
    end

    test "returns a wide data frame" do
      stub_ine({:fixture, "datos_metadataoperacion_ipc"})

      df =
        Series.search_observations_as_data_frame!("IPC",
          filters: [{3, 74}],
          format: :wide,
          metadata: false
        )

      assert ["date" | codes] = DF.names(df)
      assert "IPC290750" in codes
      assert [{"tip", "A"} | _] = assert_ine_request("ES/DATOS_METADATAOPERACION/IPC")
    end

    test "the bang variant raises" do
      stub_ine({404, "Not found"})

      assert_raise Error, fn ->
        Series.search_observations_as_data_frame!("IPC", filters: [{3, 74}])
      end
    end
  end
end
