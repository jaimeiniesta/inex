defmodule Inex.Scales do
  @moduledoc """
  Functions for the INE **scales** endpoint.

  Scales tell the magnitude of the values of a series (`"Miles"` means the
  values are in thousands, with a `"Factor"` of `"1E3"`). Raw (non-friendly)
  series and observations only include the scale id (`"FK_Escala"`); use this
  listing to decode it.

  ## Endpoints

    - `list/1` - `ESCALAS` - All scales (not in the official reference)
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language])

  @doc """
  Get all the scales.

  This function (`ESCALAS`) is not listed in the official API reference.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> Inex.Scales.list()
      {:ok, [%{"Id" => 1, "Nombre" => " ", "Factor" => "1E0", ...}, %{"Id" => 2, "Nombre" => "Decenas", "Factor" => "1E1", ...}, ...]}
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("ESCALAS", [], opts, @list_schema)
  end
end
