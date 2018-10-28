defmodule Stubbex.Stub do
  def get_stub(file_path), do: file_path |> File.read!() |> Poison.decode!()

  def get_stub_eex(file_path_eex, bindings) do
    file_path_eex
    |> EEx.eval_file(Map.to_list(bindings))
    |> Poison.decode!()
  end
end
