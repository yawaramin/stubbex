defmodule Stubbex do
  @moduledoc """
  Convenience functions available under the Stubbex namespace. Mostly
  intended for use in EEx template stubs.
  """

  @doc """
  Escapes JavaScript and also JSON-encoded strings so they can be
  injected into stub responses. See the README for an example.
  """
  defdelegate stringify(data), to: Phoenix.HTML, as: :escape_javascript

  @doc """
  Returns the values which match the given header name. More than one
  may match because HTTP headers may be duplicated.

  ## Examples

      iex> Stubbex.header_values([["set-cookie", "a=1"], ["set-cookie", "b=2"]], "set-cookie")
      ["a=1", "b=2"]

      iex> Stubbex.header_values([["cookie", "a=1"]], "set-cookie")
      []

      iex> Stubbex.header_values([], "set-cookie")
      []
  """
  @spec header_values(Stubbex.Response.headers_list(), String.t()) :: [String.t()]
  def header_values(headers, name) do
    Enum.flat_map(headers, fn
      [^name, value] -> [value]
      _else -> []
    end)
  end
end
