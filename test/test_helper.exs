ExUnit.start()

# Configure Ecto for sandbox mode
Ecto.Adapters.SQL.Sandbox.mode(MarketingAgent.Repo, :manual)
