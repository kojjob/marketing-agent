defmodule MarketingAgent.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      MarketingAgent.Repo,
      # HTTP client for Swoosh
      {Finch, name: Swoosh.Finch},
      # Telemetry
      MarketingAgentWeb.Telemetry,
      # PubSub
      {Phoenix.PubSub, name: MarketingAgent.PubSub},
      # Background job processing (Oban)
      {Oban, Application.fetch_env!(:marketing_agent, Oban)},
      # Web endpoint (start last)
      MarketingAgentWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MarketingAgent.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MarketingAgentWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
