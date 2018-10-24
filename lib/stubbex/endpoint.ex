defmodule Stubbex.Endpoint do
  use GenServer

  @timeout_ms Application.get_env(:stubbex, :timeout_ms)

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
      {:request, method, headers, body},
      @timeout_ms)
  end

  # Server

  def init(request_path) do
    Process.flag(:trap_exit, true)
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

        with {:ok, file_body} <- md5_input
          |> Map.put(:response, encode_headers(response))
          |> Poison.encode_to_iodata,
          :ok <- "." |> Path.join(request_path) |> File.mkdir_p,
          :ok <- File.write(file_path, file_body) do
          nil
        else
          {:error, _any} ->
            require Logger
            Logger.warn(["Could not write stub file: ", file_path])
        end

        {
          :reply,
          response,
          {request_path, Map.put(mappings, md5, response)},
          @timeout_ms
        }
    end
  end

  @doc "Go out with an explanation."
  def handle_info(:timeout, _state) do
    {:stop, :timeout, "normal shutdown due to inactivity."}
  end

  defp real_request(method, request_path, headers, body) do
    %HTTPoison.Response{
      body: body,
      headers: headers,
      status_code: status_code
    } = HTTPoison.request!(
      method,
      path_to_url(request_path),
      body,
      headers,
      timeout: @timeout_ms,
      # See https://github.com/edgurgel/httpoison/issues/294 for more
      ssl: [cacertfile: Application.get_env(:stubbex, :cert_pem)])

    headers = Enum.flat_map(headers, fn
      # Get rid of "Transfer-Encoding: chunked" header because HTTPoison
      # is accumulating the entire response body anyway, so it wouldn't
      # be correct to send an entire response body with this header back
      # to our client.
      {"Transfer-Encoding", "chunked"} -> []
      # Need to ensure all header names are lowercased, otherwise Phoenix
      # will put in its own values for some of the headers, like
      # "Server".
      {header, value} -> [{String.downcase(header), value}]
    end)

    %{body: body, headers: headers, status_code: status_code}
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
