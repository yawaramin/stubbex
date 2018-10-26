# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

config :stubbex,
  # Apparently HTTPoison and hackney don't ship with root SSL
  # certificates, so we need to reach out to the system's root cert.
  cert_pem: System.get_env("stubbex_cert_pem") || "/etc/ssl/cert.pem",
  # How long should Stubbex wait for requests and responses?
  timeout_ms: String.to_integer(System.get_env("stubbex_timeout_ms") || "600000")

# Configures the endpoint
config :stubbex, StubbexWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "A1C55DyMLk5ITysZtg4KieA09+eb90Iwhu6aDg1ZDd+We+6cpLOqZEJMI8GjliZw",
  render_errors: [view: StubbexWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Stubbex.PubSub, adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:user_id]

# Cloudflare and others use 520 as a 'catch-all' error response.
config :plug, :statuses, %{520 => "Unknown error"}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
