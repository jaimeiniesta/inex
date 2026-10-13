defmodule Inex.Units do
  @moduledoc """
  Functions for the INE **units** endpoint.

  Units describe what the values of a series measure (`"Personas"`, `"Euros"`,
  `"Tasas"`, `"Índice"`...). Raw (non-friendly) series and observations only
  include the unit id (`"FK_Unidad"`); use this listing to decode it.

  ## Endpoints

    - `list/1` - `UNIDADES` - All units (not in the official reference)
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language])

  @doc """
  Get all the units.

  This function (`UNIDADES`) is not listed in the official API reference.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> Inex.Units.list()
      {:ok, [%{"Id" => 3, "Nombre" => "Personas", "Codigo" => nil, "Abrev" => nil}, %{"Id" => 7, "Nombre" => "Euros", "Abrev" => "€", ...}, ...]}
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("UNIDADES", [], opts, @list_schema)
  end
end
