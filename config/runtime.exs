import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables.

if System.get_env("PHX_SERVER") do
  config :marketing_agent, MarketingAgentWeb.Endpoint, server: true
end

config :marketing_agent, MarketingAgentWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT") || "4000")]

# API Keys from environment variables (all environments)
if sendgrid_key = System.get_env("SENDGRID_API_KEY") do
  config :marketing_agent, MarketingAgent.Services.SendGrid,
    api_key: sendgrid_key

  config :marketing_agent, MarketingAgent.Mailer,
    adapter: Swoosh.Adapters.SendGrid,
    api_key: sendgrid_key
else
  # No SendGrid configured - use Local adapter for testing
  # Emails will be captured and can be viewed in the mailbox
  config :marketing_agent, MarketingAgent.Mailer,
    adapter: Swoosh.Adapters.Local

  config :swoosh, :api_client, false
end

if apollo_key = System.get_env("APOLLO_API_KEY") do
  config :marketing_agent, MarketingAgent.Services.Apollo,
    api_key: apollo_key
end

# Email configuration
config :marketing_agent, MarketingAgent.Config,
  from_email: System.get_env("FROM_EMAIL") || "hello@example.com",
  from_name: System.get_env("FROM_NAME") || "Marketing Team",
  reply_to: System.get_env("REPLY_TO"),
  unsubscribe_url: System.get_env("UNSUBSCRIBE_URL") || "https://example.com/unsubscribe",
  company_address: System.get_env("COMPANY_ADDRESS") || "123 Main St, City, State 12345"

if config_env() == :prod do
  # Default database path: ~/.marketing_agent/marketing_agent.db
  default_db_path =
    Path.join([System.user_home!(), ".marketing_agent", "marketing_agent.db"])

  database_path = System.get_env("DATABASE_PATH") || default_db_path

  # Ensure the directory exists
  database_path |> Path.dirname() |> File.mkdir_p!()

  config :marketing_agent, MarketingAgent.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # Templates directory - check multiple locations
  templates_dir =
    System.get_env("TEMPLATES_DIR") ||
      cond do
        File.dir?(Path.join([System.user_home!(), ".marketing_agent", "templates"])) ->
          Path.join([System.user_home!(), ".marketing_agent", "templates"])
        File.dir?("priv/templates") ->
          Path.expand("priv/templates")
        true ->
          Path.join([System.user_home!(), ".marketing_agent", "templates"])
      end

  config :marketing_agent, MarketingAgent.Config,
    templates_dir: templates_dir

  # Web endpoint config (only needed if running web server)
  if System.get_env("PHX_SERVER") do
    secret_key_base =
      System.get_env("SECRET_KEY_BASE") ||
        raise """
        environment variable SECRET_KEY_BASE is missing.
        You can generate one by calling: mix phx.gen.secret
        """

    host = System.get_env("PHX_HOST") || "example.com"

    config :marketing_agent, MarketingAgentWeb.Endpoint,
      url: [host: host, port: 443, scheme: "https"],
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0}
      ],
      secret_key_base: secret_key_base
  else
    # CLI-only mode: use a fixed secret (not for production web servers)
    config :marketing_agent, MarketingAgentWeb.Endpoint,
      secret_key_base: "cli-mode-secret-key-base-not-for-web-production-use-only"
  end
end
