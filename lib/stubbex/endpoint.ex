defmodule Stubbex.Endpoint do
  use GenServer
  require Logger
  alias Stubbex.Response
  alias Stubbex.Stub

  @typep mappings :: %{required(md5_input) => Response.t()}
  @typep md5_input :: %{
           method: String.t(),
           query_string: String.t(),
           headers: Response.headers(),
           body: binary
         }

  @timeout_ms Application.get_env(:stubbex, :timeout_ms)
  @stubs_dir Application.get_env(:stubbex, :stubs_dir)
  @pretty_opts [{:pretty, true}, {:limit, 100_000}]

  # Client

  @spec start_link([], String.t()) :: {:error, any()} | {:ok, pid()}
  def start_link([], stub_path) do
    GenServer.start_link(__MODULE__, stub_path, name: {:global, stub_path})
  end

  @spec stub(String.t(), String.t(), String.t(), Response.headers(), binary) :: Response.t()
  def stub(method, stub_path, query_string \\ "", headers \\ [], body \\ "") do
    GenServer.call(
      {:global, stub_path},
      {:stub, method, query_string, headers, body},
      @timeout_ms
    )
  end

  def validations(conn, stub_path) do
    GenServer.call(
      {:global, stub_path},
      {:validations, conn, Path.join([@stubs_dir, stub_path, "**", "*.{json,json.eex}"])},
      @timeout_ms
    )
  end

  # Server

  @spec init(String.t()) :: {:ok, {String.t(), mappings}}
  @impl true
  def init(stub_path) do
    Process.flag(:trap_exit, true)
    {:ok, {stub_path, %{}}}
  end

  @impl true
  def handle_call(
        {:stub, method, query_string, headers, body},
        _from,
        {stub_path, mappings}
      ) do
    headers = real_host(headers, stub_path)

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
      [@stubs_dir, stub_path, md5 <> ".json"]
      |> Path.join()
      |> String.replace("//", "/")

    file_path_eex = file_path <> ".eex"

    cond do
      File.exists?(file_path_eex) ->
        url = path_to_url(stub_path)

        %{"response" => response} =
          Stub.get_stub(File.read!(file_path_eex), Map.put(md5_input, :url, url))

        {:reply, Response.decode_eex(response), {stub_path, mappings}, @timeout_ms}

      Map.has_key?(mappings, md5_input) ->
        {
          :reply,
          Map.get(mappings, md5_input),
          {stub_path, mappings},
          @timeout_ms
        }

      File.exists?(file_path) ->
        %{"response" => response} = Stub.get_stub(File.read!(file_path))
        reply_update(Response.decode(response), stub_path, mappings, md5_input)

      true ->
        response = real_request(method, stub_path, query_string, headers, body)

        with {:ok, file_body} <-
               md5_input
               |> Map.put(:response, Response.encode(response))
               |> Poison.encode_to_iodata(@pretty_opts),
             :ok <- "." |> Path.join(stub_path) |> File.mkdir_p(),
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

        reply_update(response, stub_path, mappings, md5_input)
    end
  end

  @impl true
  def handle_call({:validations, conn, path_glob}, _from, state) do
    conn =
      path_glob
      |> Path.wildcard()
      |> Enum.reduce_while(conn, fn stub_file, conn ->
        contents = File.read!(stub_file)
        url_path = Path.dirname(stub_file)

        %{
          "response" => response,
          "query_string" => query_string,
          "method" => method,
          "headers" => headers,
          "body" => body
        } =
          if String.ends_with?(stub_file, "eex") do
            %{
              "query_string" => query_string,
              "method" => method,
              "headers" => headers,
              "body" => body
            } =
              Stub.get_stub(contents, %{
                url: "",
                query_string: "",
                method: "",
                headers: %{},
                body: ""
              })

            url = path_to_url(url_path)

            Stub.get_stub(contents, %{
              url: url,
              query_string: query_string,
              method: method,
              headers: headers,
              body: body
            })
          else
            Stub.get_stub(contents)
          end

        real_response =
          method
          |> real_request(url_path, query_string, headers, body)
          |> Response.encode()
          |> Poison.encode!(@pretty_opts)

        header = [
          :inverse,
          " ",
          url_query(url_path, query_string),
          " ",
          :reset,
          "\n"
        ]

        validation =
          response
          |> Poison.encode!(@pretty_opts)
          |> String.myers_difference(real_response)
          |> diff_color

        case Plug.Conn.chunk(conn, IO.ANSI.format([header | validation])) do
          {:ok, conn} -> {:cont, conn}
          {:error, :closed} -> {:halt, conn}
        end
      end)

    {:reply, conn, state, @timeout_ms}
  end

  defp diff_color(myers) do
    myers
    |> Enum.flat_map(fn
      {:eq, text} -> [:reset, text]
      {:del, text} -> [:red, text]
      {:ins, text} -> [:green, text]
    end)
  end

  @doc "Go out with an explanation."
  @impl true
  def handle_info(:timeout, _state) do
    {:stop, :timeout, "This stub is now dormant due to inactivity."}
  end

  defp reply_update(response, stub_path, mappings, md5_input) do
    {
      :reply,
      response,
      {stub_path, Map.put(mappings, md5_input, response)},
      @timeout_ms
    }
  end

  defp real_request(method, stub_path, query_string, headers, body) do
    Logger.debug(["Headers: ", inspect(headers)])

    %HTTPoison.Response{
      body: body,
      headers: headers,
      status_code: status_code
    } =
      HTTPoison.request!(
        method,
        url_query(stub_path, query_string),
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

  defp url_query(stub_path, ""), do: path_to_url(stub_path)

  defp url_query(stub_path, query_string) do
    path_to_url(stub_path) <> "?" <> query_string
  end

  defp path_to_url("/stubs/" <> path) do
    String.replace(path, "/", "://", global: false)
  end

  defp path_to_url("stubs/" <> _path = path) do
    path_to_url("/" <> path)
  end

  # Stubbex needs to call real requests with the "Host" header set
  # correctly, because clients calling it set Stubbex as the "Host", e.g.
  # `localhost:4000`.
  defp real_host(headers, stub_path) do
    %URI{host: host} = stub_path |> path_to_url |> URI.parse()

    Enum.map(headers, fn
      {"host", _host} -> {"host", host}
      header -> header
    end)
  end
end
