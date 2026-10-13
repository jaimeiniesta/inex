defmodule Inex.DataFrameTest do
  use Inex.Case, async: true

  alias Explorer.DataFrame, as: DF
  alias Explorer.Series

  doctest Inex.DataFrame

  @base_columns ~w(code name date year period value data_type unit scale)

  defp column(df, name), do: Series.to_list(df[name])

  describe "from_observations/1" do
    test "converts a single raw series (epoch dates, period ids)" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_ipc290750"))

      assert DF.names(df) == @base_columns
      assert DF.n_rows(df) == 5
      assert column(df, "code") |> Enum.uniq() == ["IPC290750"]
      assert column(df, "name") |> Enum.uniq() == ["Nacional. Índice general. Variación anual"]

      assert column(df, "date") == [
               ~D[2026-05-01],
               ~D[2026-06-01],
               ~D[2026-07-01],
               ~D[2026-08-01],
               ~D[2026-09-01]
             ]

      assert column(df, "period") == ["M05", "M06", "M07", "M08", "M09"]
      assert column(df, "year") == [2026, 2026, 2026, 2026, 2026]
      assert column(df, "value") == [3.2, 3.2, 3.6, 4.3, 4.9]
    end

    test "uses the expected dtypes" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_ipc290750"))

      assert DF.dtypes(df) == %{
               "code" => :string,
               "name" => :string,
               "date" => :date,
               "year" => {:s, 64},
               "period" => :string,
               "value" => {:f, 64},
               "data_type" => :string,
               "unit" => :string,
               "scale" => :string
             }
    end

    test "converts friendly responses (ISO dates, unit, data type)" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_ipc290750_friendly"))

      assert List.last(column(df, "date")) == ~D[2026-09-01]
      assert List.last(column(df, "data_type")) == "Avance"
      assert column(df, "unit") |> Enum.uniq() == ["Tasas"]
      # The blank scale (" ") becomes nil
      assert column(df, "scale") |> Enum.uniq() == [nil]
    end

    test "converts detailed responses (nested period, unit and data type)" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_ipc290750_detail2"))

      assert column(df, "period") == ["M08", "M09"]
      assert column(df, "data_type") == ["Definitivo", "Avance"]
      assert column(df, "unit") == ["Tasas", "Tasas"]
    end

    test "adds one column per metadata variable" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_ipc290750_metadata"))

      assert DF.names(df) ==
               @base_columns ++ ["Totales Territoriales", "Grupos ECOICOP", "Índices y Tasas"]

      assert column(df, "Índices y Tasas") |> Enum.uniq() == ["Variación anual"]
    end

    test "converts quarterly series" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_epa452434_friendly"))

      assert column(df, "period") == ["T3", "T4", "T1", "T2"]

      assert column(df, "date") == [
               ~D[2025-07-01],
               ~D[2025-10-01],
               ~D[2026-01-01],
               ~D[2026-04-01]
             ]
    end

    test "derives the date from the period when the INE does not send it" do
      df = Inex.DataFrame.from_observations(fixture!("datos_serie_ipc251856_old"))

      assert column(df, "date") == [~D[1962-01-01], ~D[1962-02-01], ~D[1962-03-01]]
    end

    test "converts tables with metadata, filling missing variables with nil" do
      df = Inex.DataFrame.from_observations(fixture!("datos_tabla_76136_metadata"))

      assert DF.n_rows(df) == 21
      assert "Comunidades y Ciudades Autónomas" in DF.names(df)

      national = DF.filter_with(df, &Series.equal(&1["code"], "IPC290750"))
      assert column(national, "Comunidades y Ciudades Autónomas") == [nil, nil]
      assert column(national, "Totales Territoriales") == ["Nacional", "Nacional"]
    end

    test "sorts the observations of each series by date" do
      # DATOS_TABLA returns the newest observation first
      df = Inex.DataFrame.from_observations(fixture!("datos_tabla_76136_metadata"))
      andalucia = DF.filter_with(df, &Series.equal(&1["code"], "IPC293659"))

      assert column(andalucia, "date") == Enum.sort(column(andalucia, "date"), Date)
    end

    test "converts PC-Axis tables (no code, no date)" do
      df = Inex.DataFrame.from_observations(fixture!("datos_tabla_px"))

      assert column(df, "code") |> Enum.uniq() == [nil]
      assert column(df, "period") |> Enum.take(2) == ["2021", "2022"]
      assert column(df, "date") |> Enum.take(2) == [~D[2021-01-01], ~D[2022-01-01]]

      assert column(df, "Sexo") |> Enum.uniq() |> Enum.sort() == [
               "Ambos sexos",
               "Hombres",
               "Mujeres"
             ]
    end

    test "converts tpx tables with provisional periods" do
      df = Inex.DataFrame.from_observations(fixture!("datos_tabla_tpx"))

      assert column(df, "period") |> Enum.take(2) == ["2023", "2024 (avance)"]
      assert column(df, "year") |> Enum.take(2) == [2023, 2024]
      assert column(df, "date") |> Enum.take(2) == [~D[2023-01-01], ~D[2024-01-01]]
    end

    test "converts operation data (abbreviated month labels)" do
      df = Inex.DataFrame.from_observations(fixture!("datos_metadataoperacion_ipc"))

      assert "jul." in column(df, "period")
      refute nil in column(df, "date")
    end

    test "handles series without data" do
      df = Inex.DataFrame.from_observations([%{"COD" => "X", "Nombre" => "x", "Data" => []}])

      assert DF.names(df) == @base_columns
      assert DF.n_rows(df) == 0
    end

    test "converts integer values to floats" do
      df =
        Inex.DataFrame.from_observations(%{
          "COD" => "X",
          "Data" => [%{"Anyo" => 2020, "Valor" => 5}]
        })

      assert column(df, "value") == [5.0]
    end

    test "avoids name clashes between variables and base columns" do
      payload = %{
        "COD" => "X",
        "MetaData" => [%{"T3_Variable" => "value", "Nombre" => "v"}],
        "Data" => [%{"Anyo" => 2020, "Valor" => 1.0}]
      }

      df = Inex.DataFrame.from_observations(payload)
      assert column(df, "value (variable)") == ["v"]
      assert column(df, "value") == [1.0]
    end
  end

  describe "observation_date/3" do
    test "converts epoch milliseconds at midnight in Madrid (summer and winter time)" do
      # 2026-08-01T00:00:00+02:00
      assert Inex.DataFrame.observation_date(1_785_535_200_000, nil, nil) == ~D[2026-08-01]
      # 2025-12-01T00:00:00+01:00
      assert Inex.DataFrame.observation_date(1_764_543_600_000, nil, nil) == ~D[2025-12-01]
      # Before 1970
      assert Inex.DataFrame.observation_date(-252_464_400_000, nil, nil) == ~D[1962-01-01]
    end

    test "parses ISO 8601 strings" do
      assert Inex.DataFrame.observation_date("2026-10-01T00:00:00.000+02:00", nil, nil) ==
               ~D[2026-10-01]
    end

    test "falls back to the year and the period label" do
      assert Inex.DataFrame.observation_date(nil, 2024, "M03") == ~D[2024-03-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "T3") == ~D[2024-07-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "Q4") == ~D[2024-10-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "S2") == ~D[2024-07-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "A") == ~D[2024-01-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "ago.") == ~D[2024-08-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "Dec") == ~D[2024-12-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "2024M11") == ~D[2024-11-01]
      assert Inex.DataFrame.observation_date(nil, 2024, "2024T2") == ~D[2024-04-01]
      assert Inex.DataFrame.observation_date("not a date", 2024, "M05") == ~D[2024-05-01]
    end

    test "returns nil for unknown periods" do
      assert Inex.DataFrame.observation_date(nil, 2024, "1 de enero de") == nil
      assert Inex.DataFrame.observation_date(nil, 2024, "M13") == nil
      assert Inex.DataFrame.observation_date(nil, nil, "M01") == nil
    end
  end

  describe "to_wide/2" do
    test "pivots by date with one column per series code" do
      wide =
        "datos_tabla_76136_metadata"
        |> fixture!()
        |> Inex.DataFrame.from_observations()
        |> Inex.DataFrame.to_wide()

      assert DF.n_rows(wide) == 2
      assert hd(DF.names(wide)) == "date"
      assert length(DF.names(wide)) == 21
      assert column(wide, "date") == [~D[2026-08-01], ~D[2026-09-01]]
      assert column(wide, "IPC290750") == [4.3, 4.9]
      # Regional series have no flash estimate (avance) for September
      assert column(wide, "IPC293659") == [4.0, nil]
    end

    test "can name the columns after the series names" do
      wide =
        "datos_serie_ipc290750"
        |> fixture!()
        |> Inex.DataFrame.from_observations()
        |> Inex.DataFrame.to_wide(columns: :name)

      assert DF.names(wide) == ["date", "Nacional. Índice general. Variación anual"]
    end

    test "uses the names when the series have no code" do
      wide =
        "datos_tabla_tpx"
        |> fixture!()
        |> Inex.DataFrame.from_observations()
        |> Inex.DataFrame.to_wide()

      assert DF.names(wide) == [
               "date",
               "1.  Biomasa",
               "2.  Minerales metálicos (mineral en bruto)"
             ]
    end

    test "uses the period when there are no dates" do
      long =
        DF.new(
          code: ["A", "B"],
          name: ["a", "b"],
          date: [nil, nil],
          period: ["X", "X"],
          value: [1.0, 2.0]
        )

      assert DF.to_columns(Inex.DataFrame.to_wide(long)) == %{
               "period" => ["X"],
               "A" => [1.0],
               "B" => [2.0]
             }
    end

    test "returns an empty data frame for empty input" do
      wide = Inex.DataFrame.to_wide(Inex.DataFrame.from_observations([]))

      assert DF.names(wide) == ["date"]
      assert DF.n_rows(wide) == 0
    end
  end

  describe "from_records/1" do
    test "converts metadata listings" do
      df = Inex.DataFrame.from_records(fixture!("operaciones_disponibles"))

      assert DF.names(df) == ["Id", "Nombre", "Codigo", "Cod_IOE", "Url"]
      assert DF.n_rows(df) == 15
      assert df["Id"].dtype == {:s, 64}
    end

    test "flattens nested maps and encodes lists" do
      df = Inex.DataFrame.from_records(fixture!("valores_serie_ipc290750"))

      assert "Variable.Nombre" in DF.names(df)
      assert column(df, "Variable.Nombre") |> hd() == "Totales Territoriales"

      df = Inex.DataFrame.from_records(fixture!("valores_hijos_70_8997"))
      assert column(df, "FK_JerarquiaPadres") |> hd() == "[8997]"
    end

    test "accepts a single record" do
      df = Inex.DataFrame.from_records(fixture!("serie_ipc290750"))

      assert DF.n_rows(df) == 1
      assert column(df, "COD") == ["IPC290750"]
    end

    test "normalizes columns with mixed types" do
      df =
        Inex.DataFrame.from_records([
          %{"a" => 1, "b" => 1},
          %{"a" => 1.5, "b" => "x"},
          %{"a" => nil, "b" => true}
        ])

      assert column(df, "a") == [1.0, 1.5, nil]
      assert column(df, "b") == ["1", "x", "true"]
    end
  end
end
