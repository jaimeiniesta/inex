defmodule Inex.UtilsTest do
  use ExUnit.Case, async: true

  alias Inex.Error
  alias Inex.Utils

  @schema Utils.schema([
            :language,
            :detail,
            :friendly,
            :metadata,
            :geo,
            :last,
            :date_range,
            :table_filters,
            :periodicity,
            :classification,
            :page
          ])

  defp params(opts, filters_as \\ :table) do
    {:ok, opts} = Utils.validate_opts(opts, @schema)

    opts
    |> Utils.to_params(filters_as)
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  describe "to_params/2" do
    test "translates the simple options" do
      assert params(detail: 2, last: 5, classification: 121, page: 3) == [
               det: 2,
               clasif: 121,
               nult: 5,
               page: 3
             ]
    end

    test "builds tip from friendly and metadata" do
      assert params(friendly: true) == [tip: "A"]
      assert params(metadata: true) == [tip: "M"]
      assert params(friendly: true, metadata: true) == [tip: "AM"]
      assert params(friendly: false, metadata: false) == []
    end

    test "translates geo and periodicity" do
      assert params(geo: :national) == [geo: 0]
      assert params(geo: :regional) == [geo: 1]
      assert params(periodicity: :monthly) == [p: 1]
      assert params(periodicity: :quarterly) == [p: 3]
      assert params(periodicity: :semiannual) == [p: 6]
      assert params(periodicity: :annual) == [p: 12]
      assert params(periodicity: 7) == [p: 7]
    end

    test "does not send page: :all to the API" do
      assert params(page: :all) == []
    end

    test "builds date ranges" do
      assert params(observation_start: ~D[2024-01-01]) == [date: "20240101:"]

      assert params(observation_start: ~D[2024-01-01], observation_end: ~D[2024-12-31]) == [
               date: "20240101:20241231"
             ]

      assert params(observation_end: ~D[2000-03-31]) == [date: "18000101:20000331"]
    end

    test "builds several dates and ranges" do
      dates = [
        ~D[2024-01-01],
        Date.range(~D[2025-01-01], ~D[2025-03-01]),
        {~D[2026-01-01], nil},
        {~D[2023-01-01], ~D[2023-02-01]}
      ]

      assert params(dates: dates) == [
               date: "20240101:20240101",
               date: "20250101:20250301",
               date: "20260101:",
               date: "20230101:20230201"
             ]
    end

    test "normalizes decreasing date ranges" do
      assert params(dates: [Date.range(~D[2025-03-01], ~D[2025-01-01], -1)]) == [
               date: "20250101:20250301"
             ]
    end

    test "combines observation_start/observation_end with dates" do
      assert params(observation_start: ~D[2020-01-01], dates: [~D[2010-01-01]]) ==
               [date: "20200101:", date: "20100101:20100101"]
    end

    test "encodes filters for tables or operations" do
      assert params([filters: [{3, 74}, ccaa: :all]], :table) == [tv: "3:74", tv: "70:"]
      assert params([filters: [{3, 74}, ccaa: :all]], :operation) == [g1: "3:74", g2: "70:"]
    end
  end

  describe "validate_opts/2" do
    test "returns option errors" do
      assert {:error, %Error{type: :option_error, message: message}} =
               Utils.validate_opts([detail: 3], @schema)

      assert message =~ ":detail"

      assert {:error, %Error{type: :option_error}} = Utils.validate_opts([unknown: 1], @schema)

      assert {:error, %Error{type: :option_error}} =
               Utils.validate_opts([observation_start: "2024-01-01"], @schema)

      assert {:error, %Error{type: :option_error}} =
               Utils.validate_opts([dates: ["2024"]], @schema)

      assert {:error, %Error{type: :option_error}} = Utils.validate_opts([language: :fr], @schema)
    end

    test "checks the order of the dates" do
      assert {:error, %Error{type: :option_error, message: message}} =
               Utils.validate_opts(
                 [observation_start: ~D[2025-01-01], observation_end: ~D[2024-01-01]],
                 @schema
               )

      assert message =~ "on or before"

      assert {:error, %Error{type: :option_error}} =
               Utils.validate_opts([dates: [{~D[2025-01-01], ~D[2024-01-01]}]], @schema)
    end
  end

  describe "ensure_data_range/1" do
    test "adds an open range when there is no nult nor date" do
      assert Utils.ensure_data_range(det: 1, nult: nil) == [det: 1, nult: nil, date: "18000101:"]
    end

    test "keeps the params when there is nult or date" do
      assert Utils.ensure_data_range(nult: 3) == [nult: 3]
      assert Utils.ensure_data_range(date: "20240101:") == [date: "20240101:"]
    end
  end
end
