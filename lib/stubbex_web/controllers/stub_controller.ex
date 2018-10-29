defmodule StubbexWeb.StubController do
  use StubbexWeb, :controller
  alias Stubbex.Dispatcher

  @spec stub(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def stub(conn, _params) do
    {:ok, body, conn} = read_body(conn)

    %{body: body, headers: headers, status_code: status_code} =
      Dispatcher.stub(
        conn.method,
        conn.request_path,
        conn.query_string,
        conn.req_headers,
        body
      )

    conn
    |> merge_resp_headers(headers)
    |> send_resp(status_code, body)
  end

  def validations(conn, _params) do
    conn = send_chunked(conn, 200)
    Dispatcher.validations(conn)
  end
end
