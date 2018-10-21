defmodule Stubbex.Dispatcher do
  use DynamicSupervisor
  alias Stubbex.Endpoint

  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def request(method, url, headers, body) do
    start_endpoint(url)
    Endpoint.request(method, url, headers, body)
  end

  defp start_endpoint(url) do
    DynamicSupervisor.start_child(__MODULE__, %{
      id: url,
      start: {Endpoint, :start_link, [url]},
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
