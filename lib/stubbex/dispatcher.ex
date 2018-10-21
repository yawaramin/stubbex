defmodule Stubbex.Dispatcher do
  use DynamicSupervisor
  alias Stubbex.Endpoint

  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def dispatch(method, request_path, headers, body) do
    start_endpoint(request_path)
    Endpoint.request(method, request_path, headers, body)
  end

  defp start_endpoint(request_path) do
    DynamicSupervisor.start_child(__MODULE__, %{
      id: request_path,
      start: {Endpoint, :start_link, [request_path]},
      restart: :temporary
    })
  end

  @impl true
  def init(args) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      extra_arguments: [args])
  end
end
