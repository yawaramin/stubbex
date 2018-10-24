defmodule Stubbex.Response do
  @moduledoc """
  Transform HTTPoison responses between their original formats and a
  JSON-suitable storage format.
  """

  @content_gzip {"content-encoding", "gzip"}

  def encode(%{status_code: status_code, headers: headers, body: body}) do
    %{
      status_code: status_code,
      headers: Enum.into(headers, %{}),
      body: if @content_gzip in headers do
        Base.encode64(body)
      else
        body
      end
    }
  end

  def decode(%{"status_code" => status_code, "headers" => headers, "body" => body}) do
    %{
      status_code: status_code,
      headers: Map.to_list(headers),
      body: if @content_gzip in headers do
        Base.decode64!(body)
      else
        body
      end
    }
  end
end
