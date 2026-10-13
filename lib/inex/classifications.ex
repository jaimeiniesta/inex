defmodule Inex.Classifications do
  @moduledoc """
  Functions for the INE **classifications** endpoints.

  Classifications are, together with the id, name and periodicity, one of the
  properties that define the identity of a series: the national
  classification it follows (CNAE 2009...), the base of an index (Base 2021...),
  the population frame...

  ## Endpoints

    - `list/1` - [`CLASIFICACIONES`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1564) - All classifications

  To get the classifications of an operation, see `Inex.Operations.classifications/2`.
  Classification ids can be used to filter the values of a variable with
  `Inex.Variables.values(variable, classification: id)`.
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language])

  @doc """
  Get all the classifications.

  `"Fecha"` is the moment (epoch milliseconds) the classification came into effect.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> Inex.Classifications.list()
      {:ok, [%{"Id" => 1, "Nombre" => "CNAE 93", "Fecha" => 725842800000}, ...]}
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("CLASIFICACIONES", [], opts, @list_schema)
  end
end
