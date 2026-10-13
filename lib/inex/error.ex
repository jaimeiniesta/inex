defmodule Inex.Error do
  @moduledoc """
  Structured error type returned by every `Inex` function.

  ## Error Types

    - `:not_found` - The requested resource does not exist. The INE API
      answers unknown identifiers (series codes, operations, tables...) with an
      HTTP 200 and an *empty body*, and invalid parameter combinations with an
      HTTP 404 page. Both cases are reported with this type.
    - `:api_error` - The INE API answered with an error message (for example
      `"La operación indicada no existe"`) or with an unexpected HTTP status.
    - `:decode_error` - The response body looked like JSON but could not be decoded.
    - `:request_error` - The HTTP request could not be completed (timeout,
      DNS failure, connection refused...).
    - `:option_error` - The options given to a function were invalid.

  `Inex.Error` is an exception, so the bang (`!`) variants of the data frame
  functions raise it directly.
  """

  @type error_type :: :not_found | :api_error | :decode_error | :request_error | :option_error

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          status: non_neg_integer() | nil
        }

  defexception [:type, :message, :status]

  @doc false
  @spec new(error_type(), String.t(), non_neg_integer() | nil) :: t()
  def new(type, message, status \\ nil) do
    %__MODULE__{type: type, message: message, status: status}
  end

  @impl true
  def message(%__MODULE__{message: message, status: nil}), do: message
  def message(%__MODULE__{message: message, status: status}), do: "(HTTP #{status}) #{message}"
end
