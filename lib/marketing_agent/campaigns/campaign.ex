defmodule MarketingAgent.Campaigns.Campaign do
  @moduledoc """
  Schema for email campaigns.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "campaigns" do
    field :name, :string
    field :template_name, :string
    field :subject, :string
    field :segment, :string
    field :status, :string, default: "draft"
    # Status values: draft, approved, sending, sent, paused, cancelled

    # Metrics
    field :total_recipients, :integer, default: 0
    field :emails_sent, :integer, default: 0
    field :emails_delivered, :integer, default: 0
    field :emails_opened, :integer, default: 0
    field :emails_clicked, :integer, default: 0
    field :emails_bounced, :integer, default: 0
    field :emails_unsubscribed, :integer, default: 0
    field :replies_received, :integer, default: 0

    # Timing
    field :scheduled_at, :utc_datetime
    field :started_at, :utc_datetime
    field :completed_at, :utc_datetime

    # Configuration
    field :is_followup, :boolean, default: false
    field :followup_days, :integer
    field :parent_campaign_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :template_name]
  @optional_fields [
    :subject,
    :segment,
    :status,
    :total_recipients,
    :emails_sent,
    :emails_delivered,
    :emails_opened,
    :emails_clicked,
    :emails_bounced,
    :emails_unsubscribed,
    :replies_received,
    :scheduled_at,
    :started_at,
    :completed_at,
    :is_followup,
    :followup_days,
    :parent_campaign_id
  ]

  def changeset(campaign, attrs) do
    campaign
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ["draft", "approved", "sending", "sent", "paused", "cancelled"])
  end

  def metrics_changeset(campaign, attrs) do
    campaign
    |> cast(attrs, [
      :emails_sent,
      :emails_delivered,
      :emails_opened,
      :emails_clicked,
      :emails_bounced,
      :emails_unsubscribed,
      :replies_received
    ])
  end

  # Calculated metrics
  def open_rate(%__MODULE__{emails_sent: 0}), do: 0.0
  def open_rate(%__MODULE__{emails_opened: opened, emails_sent: sent}), do: opened / sent * 100

  def click_rate(%__MODULE__{emails_sent: 0}), do: 0.0
  def click_rate(%__MODULE__{emails_clicked: clicked, emails_sent: sent}), do: clicked / sent * 100

  def bounce_rate(%__MODULE__{emails_sent: 0}), do: 0.0
  def bounce_rate(%__MODULE__{emails_bounced: bounced, emails_sent: sent}), do: bounced / sent * 100

  def reply_rate(%__MODULE__{emails_sent: 0}), do: 0.0
  def reply_rate(%__MODULE__{replies_received: replies, emails_sent: sent}), do: replies / sent * 100
end
