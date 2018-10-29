defmodule Stubbex.Dispatcher do
  use DynamicSupervisor
  alias Stubbex.Endpoint

  @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec stub(String.t(), String.t(), String.t(), Response.headers(), binary) :: Response.t()
  def stub(method, stub_path, query_string, headers, body) do
    start_endpoint(stub_path)
    Endpoint.stub(method, stub_path, query_string, headers, body)
  end

  def validations(conn) do
    path = stub_path(conn.request_path)

    start_endpoint(path)
    Endpoint.validations(conn, path)
  end

  defp start_endpoint(request_path) do
    DynamicSupervisor.start_child(__MODULE__, %{
      id: request_path,
      start: {Endpoint, :start_link, [request_path]},
      restart: :temporary
    })
  end

  defp stub_path("/validations" <> path), do: "/stubs" <> path

  @impl true
  def init(args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [args])
  end
end
