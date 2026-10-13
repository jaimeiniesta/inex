defmodule Inex.IneapirCrossCheckTest do
  @moduledoc """
  Cross-checks Inex against [ineapir](https://github.com/es-ine/ineapir), the
  official R client published by the INE.

  The same queries are run with ineapir (inside Docker, see `queries.R`) and
  with Inex against the live API, and their results are compared.

      mix test --only ineapir

  Set `INEAPIR_OUTPUT=path/to/output` to reuse the results of a previous R run
  instead of running the R queries again.
  """

  use ExUnit.Case, async: false

  alias Explorer.DataFrame, as: DF

  @moduletag :ineapir
  @moduletag timeout: :timer.minutes(10)

  @image "inex-ineapir"
  @dir Path.expand(".", __DIR__)
  @px_table "t20/e245/p08/l0/01001.px"

  setup_all do
    output = System.get_env("INEAPIR_OUTPUT") || run_ineapir!()

    # Talk to the real API instead of the Req.Test stubs
    previous = Application.get_env(:inex, :req_options)
    Application.put_env(:inex, :req_options, [])
    on_exit(fn -> Application.put_env(:inex, :req_options, previous) end)

    {:ok, output: output}
  end

  describe "data" do
    test "series observations (raw epoch dates and period ids)", %{output: output} do
      r = r_rows(output, "series_ipc290750")

      {:ok, payload} = Inex.Series.observations("IPC290750", last: 24)
      df = Inex.DataFrame.from_observations(payload)

      assert observations(df, ~w(date year period value)) ==
               Enum.map(r, &{r_date(&1), &1["Anyo"], &1["T3_Periodo"], &1["Valor"] * 1.0})
    end

    test "series observations between two dates", %{output: output} do
      r = r_rows(output, "series_epa452434_range")

      df =
        Inex.Series.observations_as_data_frame!("EPA452434",
          observation_start: ~D[2020-01-01],
          observation_end: ~D[2024-12-31],
          format: :long
        )

      assert observations(df, ~w(date period value data_type)) ==
               Enum.map(r, &{r_date(&1), &1["T3_Periodo"], &1["Valor"] * 1.0, &1["T3_TipoDato"]})
    end

    test "series observations for several date ranges", %{output: output} do
      r = r_rows(output, "series_cntr6654_dates")

      df =
        Inex.Series.observations_as_data_frame!("CNTR6654",
          dates: [{~D[2019-01-01], ~D[2019-12-31]}, {~D[2023-01-01], ~D[2023-12-31]}],
          format: :long
        )

      assert observations(df, ~w(date value)) == Enum.map(r, &{r_date(&1), &1["Valor"] * 1.0})
    end

    test "Tempus3 table observations with filters and metadata", %{output: output} do
      r = r_rows(output, "table_76136")

      df =
        Inex.Tables.observations_as_data_frame!(76136,
          filters: [{3, 74}, {762, 304_092}, {70, :all}],
          last: 3
        )

      assert sorted_observations(df, ~w(code date value)) ==
               Enum.sort(Enum.map(r, &{&1["COD"], r_date(&1), &1["Valor"] * 1.0}))

      # Every series has the same metadata values in both clients
      metadata_columns = DF.names(df) -- ~w(code name date year period value data_type unit scale)

      inex_metadata =
        df
        |> DF.to_rows()
        |> Map.new(fn row ->
          {row["code"], row |> Map.take(metadata_columns) |> Map.values() |> non_nil_set()}
        end)

      r_metadata =
        Map.new(r, fn row ->
          {row["COD"], row["MetaData"] |> Enum.map(& &1["Nombre"]) |> non_nil_set()}
        end)

      assert inex_metadata == r_metadata
    end

    test "PC-Axis table observations", %{output: output} do
      r = r_rows(output, "table_px")

      df =
        Inex.Tables.observations_as_data_frame!(@px_table,
          filters: [
            {"sexo", :all},
            {"espanolesextranjeros", "espanoles"},
            {"edad3gruposdeedad", "totaledades"}
          ],
          last: 3,
          metadata: false
        )

      assert sorted_observations(df, ~w(name period value)) ==
               Enum.sort(Enum.map(r, &{&1["Nombre"], &1["NombrePeriodo"], &1["Valor"] * 1.0}))
    end

    test "tpx table observations", %{output: output} do
      r = r_rows(output, "table_tpx")

      df =
        Inex.Tables.observations_as_data_frame!(33387,
          filters: [{"tipodematerial", ["1biomasa", "2mineralesmetalicosmineralenbruto"]}],
          last: 2,
          metadata: false
        )

      assert sorted_observations(df, ~w(name period value)) ==
               Enum.sort(Enum.map(r, &{&1["Nombre"], &1["NombrePeriodo"], &1["Valor"] * 1.0}))
    end

    test "operation observations filtered by metadata", %{output: output} do
      r = r_rows(output, "series_filter_ipc")

      df =
        Inex.Series.search_observations_as_data_frame!("IPC",
          filters: [{115, :all}, {3, 74}, {762, 304_092}],
          periodicity: :monthly,
          last: 2
        )

      assert sorted_observations(df, ~w(code date value)) ==
               Enum.sort(Enum.map(r, &{&1["COD"], r_date(&1), &1["Valor"] * 1.0}))
    end
  end

  describe "metadata" do
    test "operations", %{output: output} do
      assert ids(Inex.Operations.list()) == ids(r_rows(output, "operations"))
      assert Inex.Operations.get("IPC") == {:ok, r_rows(output, "operation_ipc")}
    end

    test "variables and values", %{output: output} do
      assert ids(Inex.Operations.variables("IPC")) == ids(r_rows(output, "variables_ipc"))

      assert ids(Inex.Operations.variable_values("IPC", 762)) ==
               ids(r_rows(output, "values_ipc_762"))

      assert ids(Inex.Variables.values(115)) == ids(r_rows(output, "values_115"))
      assert ids(Inex.Variables.children(70, 9008)) == ids(r_rows(output, "children_70_9008"))
    end

    test "tables of an operation", %{output: output} do
      assert ids(Inex.Operations.tables("IPC")) == ids(r_rows(output, "tables_ipc"))
      assert ids(Inex.Tables.groups(76136)) == ids(r_rows(output, "table_groups_76136"))
      assert ids(Inex.Tables.operation(76136)) == ids(r_rows(output, "operation_table_76136"))
    end

    test "variables and values of a Tempus3 table", %{output: output} do
      {:ok, values} = Inex.Tables.values(76136)

      inex = MapSet.new(values, &{&1["Id"], &1["FK_Variable"] || get_in(&1, ["Variable", "Id"])})
      r = MapSet.new(r_rows(output, "table_varval_76136"), &{&1["Id"], &1["Fk_Variable"]})

      assert inex == r
    end

    test "variables and values of a PC-Axis table", %{output: output} do
      {:ok, values} = Inex.Tables.values(@px_table)

      inex = values |> Inex.DataFrame.from_records() |> DF.to_rows() |> MapSet.new()
      r = MapSet.new(r_rows(output, "table_varval_px"))

      assert inex == r
    end

    test "series of a table and of an operation filter", %{output: output} do
      assert codes(Inex.Tables.series(76136)) == codes(r_rows(output, "series_table_76136"))

      assert codes(
               Inex.Series.search("IPC",
                 filters: [{115, :all}, {3, 74}, {762, 304_092}],
                 periodicity: :monthly
               )
             ) ==
               codes(r_rows(output, "series_filter_meta_ipc"))
    end

    test "a series", %{output: output} do
      assert Inex.Series.get("IPC290750") == {:ok, r_rows(output, "series_ipc290750_meta")}

      assert ids(Inex.Series.metadata("IPC290750")) ==
               ids(r_rows(output, "series_values_ipc290750"))
    end

    test "publications", %{output: output} do
      assert ids(Inex.Operations.publications("IPC")) == ids(r_rows(output, "publications_ipc"))
      assert ids(Inex.Publications.dates(8)) == ids(r_rows(output, "publication_dates_8"))
    end

    test "periodicities and classifications", %{output: output} do
      assert ids(Inex.Periodicities.list()) == ids(r_rows(output, "periodicities"))
      assert ids(Inex.Operations.periodicities("IPC")) == ids(r_rows(output, "periodicities_ipc"))
      assert ids(Inex.Classifications.list()) == ids(r_rows(output, "classifications"))

      assert ids(Inex.Operations.classifications("IPC")) ==
               ids(r_rows(output, "classifications_ipc"))
    end
  end

  ## Helpers

  defp run_ineapir! do
    unless System.find_executable("docker"),
      do: raise("Docker is required to run the ineapir cross-check")

    {_output, status} = System.cmd("docker", ["image", "inspect", @image], stderr_to_stdout: true)

    if status != 0 do
      {output, 0} = System.cmd("docker", ["build", "-t", @image, @dir], stderr_to_stdout: true)
      IO.puts(output)
    end

    output = Path.join(System.tmp_dir!(), "inex-ineapir-#{System.unique_integer([:positive])}")
    File.mkdir_p!(output)

    args = [
      "run",
      "--rm",
      "-v",
      "#{@dir}:/work",
      "-v",
      "#{output}:/out",
      @image,
      "Rscript",
      "queries.R",
      "/out"
    ]

    {log, status} = System.cmd("docker", args, stderr_to_stdout: true)
    if status != 0, do: raise("ineapir queries failed:\n#{log}")

    output
  end

  defp r_rows(output, name) do
    output
    |> Path.join("#{name}.json")
    |> File.read!()
    |> JSON.decode!()
    |> drop_row_names()
  end

  # jsonlite adds "_row" with the R row names
  defp drop_row_names(rows) when is_list(rows), do: Enum.map(rows, &Map.delete(&1, "_row"))
  defp drop_row_names(row), do: Map.delete(row, "_row")

  defp r_date(%{"Fecha" => fecha}), do: fecha |> String.slice(0, 10) |> Date.from_iso8601!()

  defp observations(df, columns) do
    df
    |> DF.select(columns)
    |> DF.to_rows()
    |> Enum.map(fn row -> columns |> Enum.map(&row[&1]) |> List.to_tuple() end)
  end

  defp sorted_observations(df, columns), do: df |> observations(columns) |> Enum.sort()

  defp ids({:ok, records}), do: ids(records)
  defp ids(records) when is_list(records), do: records |> Enum.map(& &1["Id"]) |> Enum.sort()

  defp codes({:ok, records}), do: codes(records)
  defp codes(records), do: records |> Enum.map(& &1["COD"]) |> Enum.sort()

  defp non_nil_set(values), do: values |> Enum.reject(&is_nil/1) |> MapSet.new()
end
