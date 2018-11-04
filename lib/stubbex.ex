defmodule Stubbex do
  @moduledoc "Convenience functions available under the Stubbex namespace."

  @doc """
  Escapes JavaScript and also JSON-encoded strings so they can be
  injected into stub responses. See the README for an example.
  """
  defdelegate stringify(data), to: Phoenix.HTML, as: :escape_javascript
end
