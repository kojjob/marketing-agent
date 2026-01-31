defmodule MarketingAgent.Repo.Migrations.CreateCampaigns do
  use Ecto.Migration

  def change do
    create table(:campaigns, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :template_name, :string, null: false
      add :subject, :string
      add :segment, :string
      add :status, :string, default: "draft"

      # Metrics
      add :total_recipients, :integer, default: 0
      add :emails_sent, :integer, default: 0
      add :emails_delivered, :integer, default: 0
      add :emails_opened, :integer, default: 0
      add :emails_clicked, :integer, default: 0
      add :emails_bounced, :integer, default: 0
      add :emails_unsubscribed, :integer, default: 0
      add :replies_received, :integer, default: 0

      # Timing
      add :scheduled_at, :utc_datetime
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime

      # Configuration
      add :is_followup, :boolean, default: false
      add :followup_days, :integer
      add :parent_campaign_id, :binary_id

      timestamps(type: :utc_datetime)
    end

    create index(:campaigns, [:status])
    create index(:campaigns, [:template_name])
    create index(:campaigns, [:segment])
  end
end
