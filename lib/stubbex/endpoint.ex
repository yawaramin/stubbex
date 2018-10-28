defmodule Stubbex.Endpoint do
  use GenServer
  require Logger

  @typep mappings :: %{required(md5_input) => Response.t()}
  @typep md5_input :: %{
           method: String.t(),
           query_string: String.t(),
           headers: Response.headers(),
           body: binary
         }

  @timeout_ms Application.get_env(:stubbex, :timeout_ms)

  # Client

  @spec start_link([], String.t()) :: {:error, any()} | {:ok, pid()}
  def start_link([], request_path) do
    GenServer.start_link(__MODULE__, request_path, name: {:global, request_path})
  end

  @spec request(String.t(), String.t(), String.t(), Response.headers(), binary) :: Response.t()
  def request(method, request_path, query_string \\ "", headers \\ [], body \\ "") do
    GenServer.call(
      {:global, request_path},
      {:request, method, query_string, headers, body},
      @timeout_ms
    )
  end

  # Server

  @spec init(String.t()) :: {:ok, {String.t(), mappings}}
  @impl true
  def init(request_path) do
    Process.flag(:trap_exit, true)
    {:ok, {request_path, %{}}}
  end

  @impl true
  def handle_call(
        {:request, method, query_string, headers, body},
        _from,
        {request_path, mappings}
      ) do
    alias Stubbex.Response
    headers = real_host(headers, request_path)

    md5_input = %{
      method: method,
      query_string: query_string,
      headers: Map.new(headers),
      body: body
    }

    md5 =
      md5_input
      |> Poison.encode_to_iodata!()
      |> :erlang.md5()
      |> Base.encode16()

    file_path =
      [
        Application.get_env(:stubbex, :stubs_dir),
        request_path,
        md5 <> ".json"
      ]
      |> Path.join()
      |> String.replace("//", "/")

    file_path_eex = file_path <> ".eex"

    cond do
      File.exists?(file_path_eex) ->
        url = path_to_url(request_path)

        %{"response" => response} =
          file_path_eex
          |> EEx.eval_file(md5_input |> Map.to_list() |> Keyword.put(:url, url))
          |> Poison.decode!()

        response =
          response
          |> Response.correct_content_length()
          |> Response.decode()

        {:reply, response, {request_path, mappings}, @timeout_ms}

      Map.has_key?(mappings, md5_input) ->
        {
          :reply,
          Map.get(mappings, md5_input),
          {request_path, mappings},
          @timeout_ms
        }

      File.exists?(file_path) ->
        %{"response" => response} = file_path |> File.read!() |> Poison.decode!()
        response = Response.decode(response)

        reply_update(response, request_path, mappings, md5_input)

      true ->
        response = real_request(method, request_path, query_string, headers, body)

        with {:ok, file_body} <-
               md5_input
               |> Map.put(:response, Response.encode(response))
               |> Poison.encode_to_iodata(pretty: true),
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

        reply_update(response, request_path, mappings, md5_input)
    end
  end

  @doc "Go out with an explanation."
  @impl true
  def handle_info(:timeout, _state) do
    {:stop, :timeout, "This stub is now dormant due to inactivity."}
  end

  defp reply_update(response, request_path, mappings, md5_input) do
    {
      :reply,
      response,
      {request_path, Map.put(mappings, md5_input, response)},
      @timeout_ms
    }
  end

  defp real_request(method, request_path, query_string, headers, body) do
    Logger.debug(["Headers: ", inspect(headers)])

    %HTTPoison.Response{
      body: body,
      headers: headers,
      status_code: status_code
    } =
      HTTPoison.request!(
        method,
        url_query(request_path, query_string),
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

  defp url_query(request_path, ""), do: path_to_url(request_path)

  defp url_query(request_path, query_string) do
    path_to_url(request_path) <> "?" <> query_string
  end

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
