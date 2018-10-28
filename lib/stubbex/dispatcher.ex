defmodule Stubbex.Dispatcher do
  use DynamicSupervisor
  alias Stubbex.Endpoint

  @spec start_link() :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link() do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec dispatch(String.t(), String.t(), String.t(), Response.headers(), binary) :: Response.t()
  def dispatch(method, request_path, query_string, headers, body) do
    start_endpoint(request_path)
    Endpoint.request(method, request_path, query_string, headers, body)
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
      extra_arguments: [args]
    )
  end
end
