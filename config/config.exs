# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# General application configuration
config :marketing_agent,
  generators: [timestamp_type: :utc_datetime],
  ecto_repos: [MarketingAgent.Repo]

# Database configuration
config :marketing_agent, MarketingAgent.Repo,
  database: Path.expand("../priv/marketing_agent.db", Path.dirname(__ENV__.file)),
  pool_size: 5,
  show_sensitive_data_on_connection_error: true

# Configure the endpoint
config :marketing_agent, MarketingAgentWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MarketingAgentWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MarketingAgent.PubSub,
  live_view: [signing_salt: "JKyRJ6FF"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Swoosh API client - use Finch instead of hackney
config :swoosh, :api_client, Swoosh.ApiClient.Finch

# Swoosh mailer configuration
config :marketing_agent, MarketingAgent.Mailer,
  adapter: Swoosh.Adapters.SendGrid

# Oban job processing (configured for SQLite)
config :marketing_agent, Oban,
  engine: Oban.Engines.Lite,
  repo: MarketingAgent.Repo,
  queues: [default: 10, emails: 5, enrichment: 3]

# Marketing Agent configuration
config :marketing_agent, MarketingAgent.Config,
  # Follow-up schedule (days after initial email)
  followup_schedule: [3, 7, 14],
  # Daily sending limits
  daily_send_limit: 100,
  # Default timezone
  timezone: "America/New_York",
  # Templates directory
  templates_dir: Path.expand("../priv/templates", Path.dirname(__ENV__.file))

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
