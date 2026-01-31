import Config

# Configure your database for testing
config :marketing_agent, MarketingAgent.Repo,
  database: Path.expand("../marketing_agent_test.db", Path.dirname(__ENV__.file)),
  pool: Ecto.Adapters.SQL.Sandbox

# We don't run a server during test.
config :marketing_agent, MarketingAgentWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9wWbb3H+7zdm8bUJg5Iz4vqudyL3rGOq/Eqlwx62pYjnpqcptyam3HAGpsWox5e0",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix, sort_verified_routes_query_params: true

# Use mock adapters for testing
config :marketing_agent, MarketingAgent.Mailer,
  adapter: Swoosh.Adapters.Test

# Disable Oban in tests
config :marketing_agent, Oban, testing: :manual

# Mock API keys for tests
config :marketing_agent, MarketingAgent.Services.SendGrid,
  api_key: "test_sendgrid_key"

config :marketing_agent, MarketingAgent.Services.Apollo,
  api_key: "test_apollo_key"

# Test config
config :marketing_agent, MarketingAgent.Config,
  from_email: "test@example.com",
  from_name: "Test Sender",
  unsubscribe_url: "https://example.com/unsubscribe",
  company_address: "123 Test St"
