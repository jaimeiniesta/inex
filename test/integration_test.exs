defmodule Inex.IntegrationTest do
  @moduledoc """
  Runs Inex against the live INE API.

      mix test --include integration

  These tests check invariants (shapes, types, errors...) rather than values,
  since the data changes with every INE release.
  """

  use ExUnit.Case, async: false

  alias Explorer.DataFrame, as: DF
  alias Inex.Error

  @moduletag :integration
  @moduletag timeout: :timer.minutes(5)

  setup_all do
    previous = Application.get_env(:inex, :req_options)
    Application.put_env(:inex, :req_options, [])
    on_exit(fn -> Application.put_env(:inex, :req_options, previous) end)
  end

  test "series observations come sorted, as floats, with current data" do
    df = Inex.Series.observations_as_data_frame!("IPC290750", last: 12, format: :long)

    assert DF.n_rows(df) == 12
    assert df["value"].dtype == {:f, 64}

    dates = Explorer.Series.to_list(df["date"])
    assert dates == Enum.sort(dates, Date)
    # IPC290750 is the current CPI series: its last observation is recent
    assert Date.diff(Date.utc_today(), List.last(dates)) < 120
  end

  test "wide data frame with series of different periodicities" do
    df =
      Inex.Series.observations_as_data_frame!(["IPC290750", "EPA452434", "CNTR6654"],
        observation_start: ~D[2024-01-01],
        observation_end: ~D[2024-12-31]
      )

    assert DF.names(df) == ["date", "IPC290750", "EPA452434", "CNTR6654"]
    assert DF.n_rows(df) == 12
    assert Explorer.Series.nil_count(df["IPC290750"]) == 0
    # Quarterly series only have data for the first month of each quarter
    assert Explorer.Series.nil_count(df["EPA452434"]) == 8
  end

  test "English responses" do
    {:ok, %{"Nombre" => name}} = Inex.Series.get("IPC290750", language: :en)

    assert name =~ "National"
  end

  test "errors from the real API" do
    assert {:error, %Error{type: :not_found}} = Inex.Series.get("NOPE")
    assert {:error, %Error{type: :not_found}} = Inex.Operations.get("NOPE")
    assert {:error, %Error{type: :not_found}} = Inex.Tables.observations(999_999_999, last: 1)
    assert {:error, %Error{type: :api_error, message: message}} = Inex.Client.get("NOFUNC", [1])
    assert message =~ "NOFUNC"
  end

  test "pagination" do
    {:ok, first_page} = Inex.Operations.series("ETCL")
    {:ok, all_series} = Inex.Operations.series("ETCL", page: :all)

    assert length(first_page) == 10_000
    assert length(all_series) > 10_000
    assert all_series |> Enum.map(& &1["COD"]) |> Enum.uniq() |> length() == length(all_series)
  end

  test "values of a tpx table can be used as filters" do
    {:ok, values} = Inex.Tables.values(33387)
    biomass = Enum.find(values, &(&1["Codigo"] == "1biomasa"))

    filters = [{biomass["Variable"]["Codigo"], biomass["Codigo"]}]
    {:ok, [series]} = Inex.Tables.observations(33387, filters: filters, last: 1)

    assert series["Nombre"] =~ "Biomasa"
  end

  test "undocumented functions" do
    assert {:ok, [%{"Id" => 19, "Nombre" => "T1"} | _]} = Inex.Periodicities.periods(3)
    assert {:ok, [_ | _]} = Inex.Units.list()
    assert {:ok, [%{"Factor" => "1E0"} | _]} = Inex.Scales.list()
  end

  test "metadata listings convert to data frames" do
    for {:ok, records} <- [
          Inex.Operations.list(),
          Inex.Operations.tables("IPC"),
          Inex.Classifications.list()
        ] do
      assert %DF{} = df = Inex.DataFrame.from_records(records)
      assert DF.n_rows(df) == length(records)
    end
  end
end
