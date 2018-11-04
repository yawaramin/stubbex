defmodule Stubbex.EndpointTest do
  use ExUnit.Case, async: true
  alias Stubbex.Endpoint

  @stub_path ""
  @md5 "md5"
  @state {@stub_path, %{@md5 => %{body: "", headers: [], status_code: 200}}}
  @new_state {@stub_path, %{}}
  @file_path "/stubs/#{@md5}.json"
  @eex ".eex"

  describe "handle_info" do
    test "deletes entry from cache if receives file modified event for .json file" do
      assert {:noreply, @new_state, _timeout_ms} =
               Endpoint.handle_info({:file_event, nil, {@file_path, [:modified]}}, @state)
    end

    test "deletes entry from cache if receives file deleted event for .json file" do
      assert {:noreply, @new_state, _timeout_ms} =
               Endpoint.handle_info({:file_event, nil, {@file_path, [:deleted]}}, @state)
    end

    test "does not delete entry from cache if receives file modified event for .json.eex file" do
      assert {:noreply, @state, _timeout_ms} =
               Endpoint.handle_info({:file_event, nil, {@file_path <> @eex, [:modified]}}, @state)
    end

    test "does not delete entry from cache if receives file deleted event for .json.eex file" do
      assert {:noreply, @state, _timeout_ms} =
               Endpoint.handle_info({:file_event, nil, {@file_path <> @eex, [:deleted]}}, @state)
    end
  end
end
