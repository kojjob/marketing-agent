defmodule MarketingAgent.Repo do
  use Ecto.Repo,
    otp_app: :marketing_agent,
    adapter: Ecto.Adapters.SQLite3
end
