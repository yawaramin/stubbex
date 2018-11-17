defmodule Stubbex.Application do
  use Application

  def start(_type, _args) do
    children = [Stubbex.Dispatcher, StubbexWeb.Endpoint]

    config()
    Supervisor.start_link(children, strategy: :one_for_one, name: Stubbex.Supervisor)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    StubbexWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp config() do
    # We need to read the system's SSL root cert, because the Erlang/
    # Elixir HTTP stack may not ship with paths to certain signing certs.
    config(:cert_pem, System.get_env("stubbex_cert_pem") || "/etc/ssl/cert.pem")

    # Where should Stubbex put its `stubs/...` directory hierarchy?
    config(:stubs_dir, System.get_env("stubbex_stubs_dir") || ".")

    # How long should Stubbex wait for requests and responses?
    timeout_ms = System.get_env("stubbex_timeout_ms")
    config(:timeout_ms, timeout_ms || "600000", &String.to_integer/1)

    # Should Stubbex not make network requests?
    config(:offline, System.get_env("stubbex_offline") || "false", &String.to_existing_atom/1)
  end

  defp config(key, value, transform \\ nil) do
    value =
      if transform do
        transform.(value)
      else
        value
      end

    Application.put_env(:stubbex, key, value)
  end
end
