defmodule StubbexWeb.StubController do
  use StubbexWeb, :controller

  @spec stub(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def stub(conn, _params) do
    alias Stubbex.Dispatcher

    {:ok, body, conn} = read_body(conn)

    %{body: body, headers: headers, status_code: status_code} =
      Dispatcher.dispatch(
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
end
