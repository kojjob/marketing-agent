defmodule MarketingAgent.Repo.Migrations.CreateContacts do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string
      add :first_name, :string
      add :last_name, :string
      add :company, :string, null: false
      add :title, :string
      add :phone, :string
      add :linkedin_url, :string
      add :website, :string
      add :segment, :string
      add :personalization, :text

      # Enrichment data
      add :company_size, :string
      add :industry, :string
      add :location, :string
      add :enriched_at, :utc_datetime

      # Status tracking
      add :status, :string, default: "new"

      # Engagement tracking
      add :emails_sent, :integer, default: 0
      add :emails_opened, :integer, default: 0
      add :emails_clicked, :integer, default: 0
      add :last_contacted_at, :utc_datetime
      add :last_opened_at, :utc_datetime
      add :last_clicked_at, :utc_datetime
      add :last_replied_at, :utc_datetime

      # Follow-up tracking
      add :followup_count, :integer, default: 0
      add :next_followup_at, :utc_datetime

      # Consent tracking
      add :consent_source, :string
      add :consent_date, :utc_datetime
      add :unsubscribed_at, :utc_datetime

      # Metadata
      add :notes, :text
      add :tags, {:array, :string}, default: []
      add :custom_fields, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create unique_index(:contacts, [:email])
    create index(:contacts, [:status])
    create index(:contacts, [:segment])
    create index(:contacts, [:company])
    create index(:contacts, [:next_followup_at])
  end
end
