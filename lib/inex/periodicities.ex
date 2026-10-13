defmodule Inex.Periodicities do
  @moduledoc """
  Functions for the INE **periodicities** endpoints.

  Periodicities define the frequency of the series: monthly (`1`), quarterly
  (`3`), semiannual (`6`), annual (`12`)...

  ## Endpoints

    - `list/1` - [`PERIODICIDADES`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1158) - All periodicities
    - `periods/2` - `PERIODOS_PERIODICIDAD/{id}` - Periods of a periodicity
      (not in the official reference)

  To get the periodicities used by an operation, see `Inex.Operations.periodicities/2`.
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language])
  @periods_schema Utils.schema([:language])

  @doc """
  Get all the periodicities.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> Inex.Periodicities.list()
      {:ok, [%{"Id" => 0, "Nombre" => "Al Detalle", "Codigo" => "N"}, %{"Id" => 1, "Nombre" => "Mensual", "Codigo" => "M"}, ...]}
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("PERIODICIDADES", [], opts, @list_schema)
  end

  @doc """
  Get the periods of a periodicity, e.g. the four quarters of the quarterly
  periodicity. The period `"Id"` is the `"FK_Periodo"` of the observations.

  This function (`PERIODOS_PERIODICIDAD`) is not listed in the official API reference.

  ## Options

  #{NimbleOptions.docs(@periods_schema)}

  ## Examples

      iex> Inex.Periodicities.periods(3)
      {:ok, [%{"Id" => 19, "Nombre" => "T1", "Mes_inicio" => "1", ...}, %{"Id" => 20, "Nombre" => "T2", ...}, ...]}
  """
  @spec periods(non_neg_integer(), keyword()) :: Client.response()
  def periods(periodicity, opts \\ []) do
    Utils.fetch("PERIODOS_PERIODICIDAD", [periodicity], opts, @periods_schema)
  end
end
