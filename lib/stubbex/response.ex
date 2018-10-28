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

  @doc """
  Updates the given response with its correct content length. Used when
  the response stub is in a template and we don't know what the final
  exact response length will be. The content length needs to be exactly
  correct, otherwise the HTTP client will stop reading the content body
  at the wrong time.
  """
  @spec correct_content_length(json_map) :: json_map
  def correct_content_length(%{"headers" => headers, "body" => body} = response) do
    length = body |> String.length() |> Integer.to_string()
    %{response | "headers" => %{headers | "content-length" => length}}
  end

  @spec decode(json_map) :: t
  def decode(%{"status_code" => status_code, "headers" => headers, "body" => body}) do
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
