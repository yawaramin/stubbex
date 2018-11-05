defmodule StubbexWeb.StubControllerTest do
  use StubbexWeb.ConnCase

  # Some of these tests require an internet connection. They can be
  # excluded by running
  # `stubbex_stubs_dir=test mix test --exclude network:true`

  test "a non-existent endpoint should return a 'not implemented' response", %{conn: conn} do
    conn = get conn, "/stubs/http/bla"
    assert response(conn, 501) === ""
  end

  @tag :network
  test "an existing endpoint should return an 'ok' response", %{conn: conn} do
    conn = get conn, "/stubs/https/jsonplaceholder.typicode.com/todos/1"

    assert json_response(conn, 200) === %{
             "id" => 1,
             "userId" => 1,
             "completed" => false,
             "title" => "delectus aut autem"
           }
  end
end
