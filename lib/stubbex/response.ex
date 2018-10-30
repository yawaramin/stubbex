defmodule Stubbex.Response do
  @moduledoc """
  Transform HTTPoison responses between their original formats and a
  JSON-suitable storage format.
  """

  @type t :: %{
          body: binary,
          headers: headers,
          status_code: status_code()
        }
  @type headers :: [{String.t(), String.t()}]
  @type headers_map :: %{required(String.t()) => String.t()}
  @type status_code :: 100..599
  @typep json_map :: %{required(String.t()) => String.t()}

  @content_gzip {"content-encoding", "gzip"}

  @spec encode(t) :: %{body: binary, headers: headers_map, status_code: status_code}
  def encode(%{headers: headers, body: body} = response) do
    %{
      response
      | headers: Map.new(headers),
        body:
          if @content_gzip in headers do
            Base.encode64(body)
          else
            body
          end
    }
  end

  @spec decode(json_map) :: t
  def decode(%{"status_code" => status_code, "headers" => headers, "body" => body}) do
    headers =
      if body == "" do
        headers
      else
        Map.put(headers, "content-length", body |> String.length() |> Integer.to_string())
      end

    %{
      status_code: status_code,
      headers: Map.to_list(headers),
      body:
        if @content_gzip in headers do
          Base.decode64!(body)
        else
          body
        end
    }
  end
end
