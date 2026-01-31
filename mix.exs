defmodule MarketingAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :marketing_agent,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      escript: escript()
    ]
  end

  def application do
    [
      mod: {MarketingAgent.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Escript configuration for CLI
  defp escript do
    [
      main_module: MarketingAgent.CLI,
      name: "marketing"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix (optional - for web UI)
      {:phoenix, "~> 1.8.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},

      # Database
      {:ecto_sql, "~> 3.10"},
      {:ecto_sqlite3, "~> 0.15"},

      # HTTP Client
      {:req, "~> 0.4"},
      {:finch, "~> 0.18"},

      # Email (SendGrid)
      {:swoosh, "~> 1.14"},

      # CSV handling
      {:nimble_csv, "~> 1.2"},

      # Environment variables
      {:dotenvy, "~> 0.8"},

      # CLI formatting
      {:table_rex, "~> 4.0"},

      # Scheduling
      {:oban, "~> 2.17"},

      # Testing
      {:mox, "~> 1.0", only: :test},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"]
    ]
  end
end
