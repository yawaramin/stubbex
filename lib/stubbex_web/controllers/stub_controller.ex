defmodule StubbexWeb.StubController do
  use StubbexWeb, :controller

  def stub(conn, _params) do
    alias Stubbex.Dispatcher

    {:ok, body, conn} = read_body(conn)
    request_path = request_query(conn.request_path, conn.query_string)
    %{body: body, headers: headers, status_code: status_code} =
      Dispatcher.dispatch(
        conn.method,
        request_path,
        conn.req_headers,
        body)

    conn
    |> merge_resp_headers(headers)
    |> send_resp(status_code, body)
  end

  defp request_query(request_path, ""), do: request_path
  defp request_query(request_path, query_string) do
    request_path <> "?" <> query_string
  end
end
