defmodule Stubbex.Endpoint do
  use GenServer
  require Logger
  alias Stubbex.Response
  alias Stubbex.Stub

  @typedoc """
  Adds a cookie to the actual response so that clients can coordinate
  test scenarios with Stubbex.
  """
  @type stub :: %{
          body: binary,
          headers: Response.headers(),
          cookie: md5,
          status_code: Response.status_code()
        }
  @type md5 :: String.t()
  @typep state :: {String.t(), mappings}
  @typep mappings :: %{required(md5) => Response.t()}

  @pretty_opts [{:pretty, true}, {:limit, 100_000}]
  @n "\n"
  @json ".json"

  # Client

  @spec start_link([], String.t()) :: {:error, any()} | {:ok, pid()}
  def start_link([], stub_path) do
    GenServer.start_link(__MODULE__, stub_path, name: {:global, stub_path})
  end

  @spec stub(String.t(), String.t(), String.t(), Response.headers(), String.t()) :: stub
  def stub(method, stub_path, query_string \\ "", headers \\ [], body \\ "") do
    GenServer.call(
      {:global, stub_path},
      {:stub, method, query_string, headers, body},
      Application.get_env(:stubbex, :timeout_ms)
    )
  end

  @spec validations(Plug.Conn.t(), String.t()) :: Plug.Conn.t()
  def validations(conn, stub_path) do
    GenServer.call(
      {:global, stub_path},
      {:validations, conn,
       Path.join([
         Application.get_env(:stubbex, :stubs_dir),
         stub_path,
         "**",
         "*.{json,json.eex,json.schema}"
       ])},
      Application.get_env(:stubbex, :timeout_ms)
    )
  end

  # Server

  @impl true
  @spec init(String.t()) :: {:ok, state}
  def init(stub_path) do
    Process.flag(:trap_exit, true)

    {:ok, watcher} =
      FileSystem.start_link(
        dirs: [Path.join(Application.get_env(:stubbex, :stubs_dir), stub_path)]
      )

    FileSystem.subscribe(watcher)
    {:ok, {stub_path, %{}}}
  end

  @impl true
  @spec handle_call(
          {:stub, String.t(), String.t(), Response.headers(), binary},
          GenServer.from(),
          state
        ) :: {:reply, Response.t(), state, pos_integer}
  def handle_call(
        {:stub, method, query_string, headers, body},
        _from,
        {stub_path, mappings}
      ) do
    timeout_ms = Application.get_env(:stubbex, :timeout_ms)
    headers = real_host(headers, stub_path)
    url = path_to_url(stub_path)

    md5_input = %{
      method: method,
      url: url,
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
      [Application.get_env(:stubbex, :stubs_dir), stub_path, md5 <> @json]
      |> Path.join()
      |> String.replace("//", "/")

    file_path_eex = file_path <> ".eex"

    cond do
      File.exists?(file_path_eex) ->
        %{"response" => response} = file_path_eex |> File.read!() |> Stub.get_stub(md5_input)

        {
          :reply,
          response |> Response.decode() |> Map.put(:cookie, md5),
          {stub_path, mappings},
          timeout_ms
        }

      Map.has_key?(mappings, md5) ->
        {
          :reply,
          mappings |> Map.get(md5) |> Map.put(:cookie, md5),
          {stub_path, mappings},
          timeout_ms
        }

      File.exists?(file_path) ->
        %{"response" => response} = file_path |> File.read!() |> Stub.get_stub()
        reply_update(Response.decode(response), stub_path, mappings, md5)

      true ->
        response =
          method
          |> real_request(stub_path, query_string, headers, body)
          |> case do
            {:ok, response} ->
              response

            {:error, %HTTPoison.Error{}} ->
              %{
                body: "",
                headers: [],
                status_code: 501
              }
          end

        with {:ok, file_body} <-
               md5_input
               |> Map.put(:response, Response.encode(response))
               |> Poison.encode_to_iodata(@pretty_opts),
             :ok <-
               Application.get_env(:stubbex, :stubs_dir) |> Path.join(stub_path) |> File.mkdir_p(),
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

        reply_update(response, stub_path, mappings, md5)
    end
  end

  @impl true
  @spec handle_call(
          {:validations, Plug.Conn.t(), String.t()},
          GenServer.from(),
          state
        ) :: {:reply, Plug.Conn.t(), state, pos_integer}
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
              "url" => url,
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

        header = [
          :inverse,
          " ",
          url_query(url_path, query_string),
          " ",
          :reset,
          @n
        ]

        validation =
          case real_request(method, url_path, query_string, headers, body) do
            {:ok, real_response} ->
              real_response = Response.encode(real_response)

              {response, real_response} =
                if String.ends_with?(stub_file, "schema") do
                  Response.inject_schema_validation(response, real_response)
                else
                  {response, real_response}
                end

              response
              |> Poison.encode!(@pretty_opts)
              |> String.myers_difference(Poison.encode!(real_response))
              |> diff_color

            {:error, %HTTPoison.Error{reason: :nxdomain}} ->
              [:red, "(Could not validate: connection failed)", :reset, @n]
          end

        case Plug.Conn.chunk(conn, IO.ANSI.format([header | validation])) do
          {:ok, conn} -> {:cont, conn}
          {:error, :closed} -> {:halt, conn}
        end
      end)

    {:reply, conn, state, Application.get_env(:stubbex, :timeout_ms)}
  end

  @impl true
  @spec handle_info({:file_event, pid, {String.t(), [atom, ...]}}, state) ::
          {:noreply, state, pos_integer}
  def handle_info({:file_event, _pid, {file_path, events}}, {stub_path, mappings}) do
    mappings =
      if :modified in events and String.ends_with?(file_path, @json) do
        Map.delete(mappings, Path.basename(file_path, @json))
      else
        mappings
      end

    {:noreply, {stub_path, mappings}, Application.get_env(:stubbex, :timeout_ms)}
  end

  @impl true
  @spec handle_info(:timeout, state) :: {:stop, :shutdown, nil}
  def handle_info(:timeout, _state), do: {:stop, :shutdown, nil}

  defp diff_color(myers) do
    myers
    |> Enum.flat_map(fn
      {:eq, text} -> [:reset, text]
      {:del, text} -> [:red, text]
      {:ins, text} -> [:green, text]
    end)
  end

  defp reply_update(response, stub_path, mappings, md5) do
    {
      :reply,
      Map.put(response, :cookie, md5),
      {stub_path, Map.put(mappings, md5, response)},
      Application.get_env(:stubbex, :timeout_ms)
    }
  end

  defp real_request(method, stub_path, query_string, headers, body) do
    Logger.debug(["Headers: ", inspect(headers)])

    with {:ok, %HTTPoison.Response{body: body, headers: headers, status_code: status_code}} <-
           HTTPoison.request(
             method,
             url_query(stub_path, query_string),
             body,
             headers,
             recv_timeout: Application.get_env(:stubbex, :timeout_ms),
             # See https://github.com/edgurgel/httpoison/issues/294 for
             # more
             ssl: [cacertfile: Application.get_env(:stubbex, :cert_pem)]
           ) do
      headers =
        Enum.flat_map(headers, fn
          # Get rid of "Transfer-Encoding: chunked" header because
          # HTTPoison is accumulating the entire response body anyway, so
          # it wouldn't be correct to send an entire response body with
          # this header back to our client.
          {"Transfer-Encoding", "chunked"} ->
            []

          # Need to ensure all header names are lowercased, otherwise
          # Phoenix will put in its own values for some of the headers,
          # like "Server".
          {header, value} ->
            [{String.downcase(header), value}]
        end)

      {:ok, %{body: body, headers: headers, status_code: status_code}}
    end
  end

  defp url_query(stub_path, ""), do: path_to_url(stub_path)

  defp url_query(stub_path, query_string) do
    path_to_url(stub_path) <> "?" <> query_string
  end

  defp path_to_url(path) do
    path =
      case String.split(path, Application.fetch_env!(:stubbex, :stubs_dir) <> "/stubs/") do
        ["", path] -> path
        ["/stubs/" <> path] -> path
      end

    String.replace(path, "/", "://", global: false)
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
