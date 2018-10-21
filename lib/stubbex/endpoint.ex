defmodule Stubbex.Endpoint do
  use GenServer

  @timeout_ms 10 * 60 * 1_000 # 10 minutes

  # Client

  def start_link([], url) do
    GenServer.start_link(__MODULE__, url, name: {:global, url})
  end

  def request(method, url, headers \\ [], body \\ "") do
    GenServer.call(
      {:global, url},
      {:request, method, headers, body})
  end

  # Server

  def init(url) do
    Process.flag :trap_exit, true
    {:ok, {url, %{}}}
  end

  def handle_call({:request, method, headers, body}, _from, {url, mappings}) do
    headers = real_host(headers, url)
    md5_input = %{
      method: method,
      headers: Enum.into(headers, %{}),
      body: body
    }
    md5 = md5_input |> Poison.encode! |> :erlang.md5 |> Base.encode16
    file_dir = Path.join(".", url_to_path(url))
    file_path = Path.join(file_dir, md5 <> ".json")

    cond do
      Map.has_key?(mappings, md5) ->
        {:reply, Map.get(mappings, md5), {url, mappings}, @timeout_ms}
      File.exists?(file_path) ->
        %{"response" => response} =
          file_path |> File.read! |> Poison.decode!
        response = decode_response(response)

        {
          :reply,
          response,
          {url, Map.put(mappings, md5, response)},
          @timeout_ms
        }
      true ->
        response = real_request(method, url, headers, body)
        file_body = md5_input
          |> Map.put(:response, encode_headers(response))
          |> Poison.encode!
        File.mkdir_p!(file_dir)
        File.write!(file_path, file_body)

        {
          :reply,
          response,
          {url, Map.put(mappings, md5, response)},
          @timeout_ms
        }
    end
  end

  def handle_info(:timeout, state), do: {:stop, :timeout, state}

  defp url_to_path(url) do
    Path.join(
      "stubs",
      url |> String.replace("//", "/") |> String.replace(":", ""))
  end

  defp real_request(method, url, headers, body) do
    method
    |> HTTPoison.request!(url, body, headers)
    |> Map.take([:body, :headers, :status_code])
    # Need to ensure all header names are lowercased, otherwise Phoenix
    # will put in its own values for some of the headers, like "Server".
    |> Map.update!(:headers, &Enum.map(&1, fn {header, value} ->
        {String.downcase(header), value}
      end))
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
  defp real_host(headers, url) do
    %URI{host: host} = URI.parse(url)

    Enum.map(headers, fn
      {"host", _host} -> {"host", host}
      header -> header
    end)
  end
end
