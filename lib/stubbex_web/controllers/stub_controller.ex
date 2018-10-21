defmodule StubbexWeb.StubController do
  use StubbexWeb, :controller
  alias Stubbex.Dispatcher

  def stub(conn, _params) do
    {:ok, body, conn} = read_body(conn)
    url = request_to_url(conn.request_path, conn.query_string)
    %{body: body, headers: headers, status_code: status_code} =
      Dispatcher.request(conn.method, url, conn.req_headers, body)

    conn
    |> merge_resp_headers(headers)
    |> send_resp(status_code, body)
  end

  defp request_to_url("/stubs/" <> url, ""), do: url
  defp request_to_url("/stubs/" <> request_path, query_string) do
    request_path <> "?" <> query_string
  end
end
