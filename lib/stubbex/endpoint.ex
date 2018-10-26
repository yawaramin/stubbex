defmodule Stubbex.Endpoint do
  use GenServer
  require Logger

  @timeout_ms Application.get_env(:stubbex, :timeout_ms)

  # Client

  def start_link([], request_path) do
    GenServer.start_link(__MODULE__, request_path, name: {:global, request_path})
  end

  def request(method, request_path, query_string \\ "", headers \\ [], body \\ "") do
    GenServer.call(
      {:global, request_path},
      {:request, method, query_string, headers, body},
      @timeout_ms
    )
  end

  # Server

  def init(request_path) do
    Process.flag(:trap_exit, true)
    {:ok, {request_path, %{}}}
  end

  def handle_call(
        {:request, method, query_string, headers, body},
        _from,
        {request_path, mappings}
      ) do
    headers = real_host(headers, request_path)

    md5_input = %{
      method: method,
      query_string: query_string,
      headers: Enum.into(headers, %{}),
      body: body
    }

    if Map.has_key?(mappings, md5_input) do
      {
        :reply,
        Map.get(mappings, md5_input),
        {request_path, mappings},
        @timeout_ms
      }
    else
      alias Stubbex.Response

      file_path =
        (
          md5 = md5_input |> Poison.encode!() |> :erlang.md5() |> Base.encode16()

          [".", request_path, md5 <> ".json"]
          |> Path.join()
          |> String.replace("//", "/")
        )

      if File.exists?(file_path) do
        %{"response" => response} = file_path |> File.read!() |> Poison.decode!()
        response = Response.decode(response)

        {
          :reply,
          response,
          {request_path, Map.put(mappings, md5_input, response)},
          @timeout_ms
        }
      else
        response = real_request(method, request_path <> "?" <> query_string, headers, body)

        with {:ok, file_body} <-
               md5_input
               |> Map.put(:response, Response.encode(response))
               |> Poison.encode_to_iodata(),
             :ok <- "." |> Path.join(request_path) |> File.mkdir_p(),
             :ok <- File.write(file_path, file_body) do
          nil
        else
          {:error, reason} ->
            Logger.warn([
              "Could not write stub file: ",
              file_path,
              ", because: ",
              inspect(reason)
            ])
        end

        {
          :reply,
          response,
          {request_path, Map.put(mappings, md5_input, response)},
          @timeout_ms
        }
      end
    end
  end

  @doc "Go out with an explanation."
  def handle_info(:timeout, _state) do
    {:stop, :timeout, "This stub is now dormant due to inactivity."}
  end

  defp real_request(method, request_path, headers, body) do
    Logger.debug(["Headers: ", inspect(headers)])

    %HTTPoison.Response{
      body: body,
      headers: headers,
      status_code: status_code
    } =
      HTTPoison.request!(
        method,
        path_to_url(request_path),
        body,
        headers,
        recv_timeout: @timeout_ms,
        # See https://github.com/edgurgel/httpoison/issues/294 for more
        ssl: [cacertfile: Application.get_env(:stubbex, :cert_pem)]
      )

    headers =
      Enum.flat_map(headers, fn
        # Get rid of "Transfer-Encoding: chunked" header because HTTPoison
        # is accumulating the entire response body anyway, so it wouldn't
        # be correct to send an entire response body with this header back
        # to our client.
        {"Transfer-Encoding", "chunked"} ->
          []

        # Need to ensure all header names are lowercased, otherwise Phoenix
        # will put in its own values for some of the headers, like
        # "Server".
        {header, value} ->
          [{String.downcase(header), value}]
      end)

    %{body: body, headers: headers, status_code: status_code}
  end

  # Convert a Stubbex stub request path to its corresponding real
  # endpoint URL.
  defp path_to_url("/stubs/" <> path) do
    String.replace(path, "/", "://", global: false)
  end

  # Stubbex needs to call real requests with the "Host" header set
  # correctly, because clients calling it set Stubbex as the "Host", e.g.
  # `localhost:4000`.
  defp real_host(headers, request_path) do
    %URI{host: host} = request_path |> path_to_url |> URI.parse()

    Enum.map(headers, fn
      {"host", _host} -> {"host", host}
      header -> header
    end)
  end
end
