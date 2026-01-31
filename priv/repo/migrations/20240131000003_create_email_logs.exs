defmodule MarketingAgent.Repo.Migrations.CreateEmailLogs do
  use Ecto.Migration

  def change do
    create table(:email_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :contact_id, :binary_id, null: false
      add :campaign_id, :binary_id
      add :to_email, :string, null: false
      add :subject, :string
      add :template_name, :string

      # SendGrid tracking
      add :sendgrid_message_id, :string
      add :status, :string, default: "queued"

      # Event timestamps
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :opened_at, :utc_datetime
      add :clicked_at, :utc_datetime
      add :bounced_at, :utc_datetime

      # Tracking
      add :open_count, :integer, default: 0
      add :click_count, :integer, default: 0
      add :clicked_links, {:array, :string}, default: []

      # Error tracking
      add :error_message, :text
      add :bounce_type, :string

      # Follow-up tracking
      add :is_followup, :boolean, default: false
      add :followup_number, :integer, default: 0

      timestamps(type: :utc_datetime)
    end

    create index(:email_logs, [:contact_id])
    create index(:email_logs, [:campaign_id])
    create index(:email_logs, [:sendgrid_message_id])
    create index(:email_logs, [:status])
    create index(:email_logs, [:sent_at])
  end
end
