defmodule Inex.Publications do
  @moduledoc """
  Functions for the INE **publications** endpoints.

  Publications determine the dissemination calendar: they contain the dates
  when the data of a statistical operation are released.

  ## Endpoints

    - `list/1` - [`PUBLICACIONES`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1159) - All publications
    - `dates/2` - [`PUBLICACIONFECHA_PUBLICACION/{id}`](https://www.ine.es/dyngs/DAB/index.htm?cid=1100#is1161) - Release dates of a publication

  To get the publications of an operation, see `Inex.Operations.publications/2`.
  """

  alias Inex.Client
  alias Inex.Utils

  @list_schema Utils.schema([:language, :detail, :friendly])
  @dates_schema Utils.schema([:language, :detail, :friendly])

  @doc """
  Get all the publications.

  ## Options

  #{NimbleOptions.docs(@list_schema)}

  ## Examples

      iex> Inex.Publications.list()
      {:ok, [%{"Id" => 1, "Nombre" => "Coyuntura Turística Hotelera (EOH/IPH/IRSH)", "FK_Periodicidad" => 1, ...}, ...]}
  """
  @spec list(keyword()) :: Client.response()
  def list(opts \\ []) do
    Utils.fetch("PUBLICACIONES", [], opts, @list_schema)
  end

  @doc """
  Get the release dates of a publication (past and scheduled).

  ## Options

  #{NimbleOptions.docs(@dates_schema)}

  ## Examples

      # Release calendar of the CPI publication (id 8)
      iex> Inex.Publications.dates(8, friendly: true)
      {:ok, [%{"Id" => 89, "Nombre" => "Índice de Precios de Consumo. Diciembre 2010", "Fecha" => "2011-01-14T09:00:00.000+01:00", ...}, ...]}
  """
  @spec dates(pos_integer(), keyword()) :: Client.response()
  def dates(publication, opts \\ []) do
    Utils.fetch("PUBLICACIONFECHA_PUBLICACION", [publication], opts, @dates_schema)
  end
end
