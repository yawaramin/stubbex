defmodule Stubbex.Endpoint do
  use GenServer

  @timeout_ms 10 * 60 * 1_000 # 10 minutes

  # Client

  def start_link([], request_path) do
    GenServer.start_link(
      __MODULE__,
      request_path,
      name: {:global, request_path})
  end

  def request(method, request_path, headers \\ [], body \\ "") do
    GenServer.call(
      {:global, request_path},
      {:request, method, headers, body})
  end

  # Server

  def init(request_path) do
    Process.flag :trap_exit, true
    "." |> Path.join(request_path) |> File.mkdir_p!

    {:ok, {request_path, %{}}}
  end

  def handle_call({:request, method, headers, body}, _from, {request_path, mappings}) do
    headers = real_host(headers, request_path)
    md5_input = %{
      method: method,
      headers: Enum.into(headers, %{}),
      body: body
    }
    md5 = md5_input |> Poison.encode! |> :erlang.md5 |> Base.encode16
    file_path = [".", request_path, md5]
      |> Path.join
      |> String.replace("//", "/")

    cond do
      Map.has_key?(mappings, md5) ->
        {
          :reply,
          Map.get(mappings, md5),
          {request_path, mappings},
          @timeout_ms
        }
      File.exists?(file_path) ->
        %{"response" => response} =
          file_path |> File.read! |> Poison.decode!
        response = decode_response(response)

        {
          :reply,
          response,
          {request_path, Map.put(mappings, md5, response)},
          @timeout_ms
        }
      true ->
        response = real_request(method, request_path, headers, body)
        file_body = md5_input
          |> Map.put(:response, encode_headers(response))
          |> Poison.encode!
        File.write!(file_path, file_body)

        {
          :reply,
          response,
          {request_path, Map.put(mappings, md5, response)},
          @timeout_ms
        }
    end
  end

  def handle_info(:timeout, state), do: {:stop, :timeout, state}

  defp real_request(method, request_path, headers, body) do
    method
    |> HTTPoison.request!(path_to_url(request_path), body, headers)
    |> Map.take([:body, :headers, :status_code])
    # Need to ensure all header names are lowercased, otherwise Phoenix
    # will put in its own values for some of the headers, like "Server".
    |> Map.update!(:headers, &Enum.map(&1, fn {header, value} ->
        {String.downcase(header), value}
      end))
  end

  # Convert a Stubbex stub request path to its corresponding real
  # endpoint URL.
  defp path_to_url("/stubs/" <> path) do
    String.replace(path, "/", "://", global: false)
  end

  defp encode_headers(response) do
    update_in(response.headers, &Enum.into(&1, %{}))
  end

  # The response is stored in the stub file in JSON format, so when we
  # read it back to respond to a stub request, we need to convert it back
  # to a format the client will understand.
  defp decode_response(response) do
    %{
      status_code: response["status_code"],
      headers: Map.to_list(response["headers"]),
      body: response["body"]
    }
  end

  # Stubbex needs to call real requests with the "Host" header set
  # correctly, because clients calling it set Stubbex as the "Host", e.g.
  # `localhost:4000`.
  defp real_host(headers, request_path) do
    %URI{host: host} = request_path |> path_to_url |> URI.parse

    Enum.map(headers, fn
      {"host", _host} -> {"host", host}
      header -> header
    end)
  end
end
