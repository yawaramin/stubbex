defmodule Stubbex.Stub do
  def get_stub(file_contents), do: Poison.decode!(file_contents)

  def get_stub(file_contents, bindings) do
    file_contents
    |> EEx.eval_string(Map.to_list(bindings))
    |> Poison.decode!()
  end
end
