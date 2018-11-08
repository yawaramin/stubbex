defmodule Stubbex.ResponseTest do
  use ExUnit.Case, async: true
  alias Stubbex.Response

  @status_code 200
  @body "a"
  @headers []
  @response %{status_code: @status_code, headers: @headers, body: @body}

  @encoded_headers []
  @encoded_response %{
    "status_code" => @status_code,
    "headers" => @encoded_headers,
    "body" => @body
  }
  @content_encoding "content-encoding"
  @real_body_completed ~s({"userId": 1, "id": 1, "title": "Title", "completed": )
  @stub_response %{
    "body" => %{
      "$schema" => "http://json-schema.org/draft-04/schema#",
      "title" => "Todo",
      "description" => "A reminder.",
      "type" => "object",
      "properties" => %{
        "userId" => %{"type" => "integer"},
        "id" => %{"type" => "integer"},
        "title" => %{"type" => "string"},
        "completed" => %{"type" => "boolean"}
      },
      "required" => ["userId", "id", "title", "completed"]
    }
  }

  describe "encode" do
    test "preserves status code" do
      assert Response.encode(@response).status_code === @status_code
    end

    test "preserves body if Content-Encoding is not gzip" do
      assert Response.encode(@response).body === @body
    end

    test "transforms body if Content-Encoding is gzip" do
      response = Response.encode(%{@response | headers: [{@content_encoding, "gzip"}]})
      assert response.body !== @body
    end
  end

  describe "decode" do
    test "preserves headers if body is empty" do
      assert Response.decode(%{@encoded_response | "body" => ""}).headers === @headers
    end

    test "corrects Content-Length header if body is not empty" do
      content_length =
        Enum.find_value(
          Response.decode(@encoded_response).headers,
          fn
            {"content-length", length} -> String.to_integer(length)
            _header -> nil
          end
        )

      assert content_length === 1
    end

    test "preserves status code" do
      assert Response.decode(@encoded_response).status_code === @status_code
    end

    test "preserves body if Content-Encoding is not gzip" do
      assert Response.decode(@encoded_response).body === @body
    end

    test "transforms body if Content-Encoding is gzip" do
      gzipped_body = Base.encode64(@body)

      response =
        Response.decode(%{
          @encoded_response
          | "headers" => [[@content_encoding, "gzip"]],
            "body" => gzipped_body
        })

      assert response.body === @body
    end
  end

  test "encode / decode roundtrip preserves entire response" do
    response = %{
      @response
      | headers: [
          {"set-cookie", "a=1"},
          {"set-cookie", "b=2"},
          {"content-length", "1"}
        ]
    }

    assert response
           |> Response.encode()
           |> Poison.encode_to_iodata!()
           |> Poison.decode!()
           |> Response.decode() === response
  end

  describe "inject_schema_validation" do
    test "returns :ok in real response body if schema validation succeeds" do
      real_response = %{body: @real_body_completed <> "true}"}

      assert {_stub_response, %{body: ":ok"}} =
               Response.inject_schema_validation(@stub_response, real_response)
    end

    test "returns error message in stub response body if schema validation fails" do
      real_response = %{body: @real_body_completed <> ~s("true"})}
      error_msg = ~s([{"Type mismatch. Expected Boolean but got String.", "#/completed"}])

      assert {%{"body" => ^error_msg}, _real_response} =
               Response.inject_schema_validation(@stub_response, real_response)
    end
  end
end
