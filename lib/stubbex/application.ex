defmodule Stubbex.Application do
  use Application

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Stubbex.Dispatcher, []),
      supervisor(StubbexWeb.Endpoint, [])
    ]

    opts = [strategy: :one_for_one, name: Stubbex.Supervisor]
    config()
    Supervisor.start_link(children, opts)
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
    config(:cert_pem, System.get_env("stubbex_cert_pem"), "/etc/ssl/cert.pem")

    # Where should Stubbex put its `stubs/...` directory hierarchy?
    config(:stubs_dir, System.get_env("stubbex_stubs_dir"), ".")

    # How long should Stubbex wait for requests and responses?
    timeout_ms = System.get_env("stubbex_timeout_ms")
    config_int(:timeout_ms, timeout_ms, "600000")
  end

  defp config(key, value, default) do
    Application.put_env(:stubbex, key, value || default, persistent: true)
  end

  defp config_int(key, value, default) do
    Application.put_env(:stubbex, key, String.to_integer(value || default), persistent: true)
  end
end
