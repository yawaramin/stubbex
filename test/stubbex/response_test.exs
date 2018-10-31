defmodule Stubbex.ResponseTest do
  use ExUnit.Case, async: true
  alias Stubbex.Response

  @status_code 200
  @body "a"
  @headers []
  @response %{status_code: @status_code, headers: @headers, body: @body}

  @encoded_headers %{}
  @encoded_response %{
    "status_code" => @status_code,
    "headers" => @encoded_headers,
    "body" => @body
  }
  @content_encoding "content-encoding"

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
          | "headers" => %{@content_encoding => "gzip"},
            "body" => gzipped_body
        })

      assert response.body === @body
    end
  end
end
