import Config

# For development, we disable any cache and enable
# debugging and code reloading.
config :marketing_agent, MarketingAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "+Nak/M1iy8YZcWacH+j+7S0M5+6tiIJcb13Jj3uWBHvPMqHbu0w1UAnfVP4CXfw3",
  watchers: []

# Enable dev routes for dashboard and mailbox
config :marketing_agent, dev_routes: true

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"

# Set a higher stacktrace during development
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Use local adapter for Swoosh in development (no actual emails sent)
config :marketing_agent, MarketingAgent.Mailer,
  adapter: Swoosh.Adapters.Local

# Disable Swoosh API client in development
config :swoosh, :api_client, false

# Oban in development - inline mode for testing
config :marketing_agent, Oban,
  engine: Oban.Engines.Lite,
  testing: :inline
