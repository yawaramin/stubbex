defmodule Stubbex.Response do
  @moduledoc """
  Transform HTTPoison responses between their original formats and a
  JSON-suitable storage format.
  """

  @type t :: %{body: binary, headers: Plug.Conn.headers(), status_code: status_code()}

  @typedoc """
  Actually this is a list of pairs of strings (each pair being a two-
  element list), but the typespec doesn't allow expressing that.
  """
  @type headers_list :: [[String.t()]]

  @type status_code :: 100..599
  @typep json_map :: %{required(String.t()) => String.t()}
  @typep response_body :: %{:body => binary, optional(any) => any}

  @content_gzip {"content-encoding", "gzip"}

  @spec encode(t) :: %{body: binary, headers: Plug.Conn.headers(), status_code: status_code}
  def encode(%{headers: headers, body: body} = response) do
    %{
      response
      | headers: Enum.map(headers, &Tuple.to_list/1),
        body:
          if @content_gzip in headers do
            Base.encode64(body)
          else
            body
          end
    }
  end

  @spec decode(json_map) :: t
  def decode(%{
        "status_code" => status_code,
        "headers" => headers,
        "body" => body
      }) do
    headers = Enum.map(headers, &List.to_tuple/1)

    body =
      if @content_gzip in headers do
        Base.decode64!(body)
      else
        body
      end

    headers =
      if body === "" do
        headers
      else
        length = body |> byte_size |> Integer.to_string()
        List.keystore(headers, "content-length", 0, {"content-length", length})
      end

    %{status_code: status_code, headers: headers, body: body}
  end

  @doc """
  The way this works is by taking advantage of the fact that a string
  body present in the stub but not in the real response will be coloured
  red, and a string body in the real response but not in the stub
  response will be coloured green. So we put the error message in the
  stub response body and clear out the real response body, and vice-
  versa.
  """
  @spec inject_schema_validation(json_map, response_body) :: {json_map, response_body}
  def inject_schema_validation(
        %{"body" => schema} = stub_response,
        %{body: json} = real_response
      ) do
    json_schema = ExJsonSchema.Schema.resolve(schema)
    json = Poison.decode!(json)

    case ExJsonSchema.Validator.validate(json_schema, json) do
      :ok ->
        {%{stub_response | "body" => ""}, %{real_response | body: ":ok"}}

      {:error, errors} ->
        {%{stub_response | "body" => inspect(errors)}, %{real_response | body: ""}}
    end
  end
end
