defmodule MarketingAgent.Campaigns.EmailLog do
  @moduledoc """
  Schema for tracking individual email sends.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "email_logs" do
    field :contact_id, :binary_id
    field :campaign_id, :binary_id
    field :to_email, :string
    field :subject, :string
    field :template_name, :string

    # SendGrid tracking
    field :sendgrid_message_id, :string
    field :status, :string, default: "queued"
    # Status: queued, sent, delivered, opened, clicked, bounced, dropped, deferred

    # Event timestamps
    field :sent_at, :utc_datetime
    field :delivered_at, :utc_datetime
    field :opened_at, :utc_datetime
    field :clicked_at, :utc_datetime
    field :bounced_at, :utc_datetime

    # Tracking
    field :open_count, :integer, default: 0
    field :click_count, :integer, default: 0
    field :clicked_links, {:array, :string}, default: []

    # Error tracking
    field :error_message, :string
    field :bounce_type, :string

    # Follow-up tracking
    field :is_followup, :boolean, default: false
    field :followup_number, :integer, default: 0

    timestamps(type: :utc_datetime)
  end

  @required_fields [:contact_id, :to_email]
  @optional_fields [
    :campaign_id,
    :subject,
    :template_name,
    :sendgrid_message_id,
    :status,
    :sent_at,
    :delivered_at,
    :opened_at,
    :clicked_at,
    :bounced_at,
    :open_count,
    :click_count,
    :clicked_links,
    :error_message,
    :bounce_type,
    :is_followup,
    :followup_number
  ]

  def changeset(email_log, attrs) do
    email_log
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:to_email, ~r/^[^\s]+@[^\s]+$/)
  end

  def event_changeset(email_log, event_type, attrs \\ %{}) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changes =
      case event_type do
        :sent -> %{status: "sent", sent_at: now}
        :delivered -> %{status: "delivered", delivered_at: now}
        :opened -> %{status: "opened", opened_at: now, open_count: (email_log.open_count || 0) + 1}
        :clicked ->
          links = Map.get(attrs, :link, nil)
          %{
            status: "clicked",
            clicked_at: now,
            click_count: (email_log.click_count || 0) + 1,
            clicked_links: if(links, do: [links | (email_log.clicked_links || [])], else: email_log.clicked_links)
          }
        :bounced -> %{status: "bounced", bounced_at: now, bounce_type: Map.get(attrs, :bounce_type)}
        :dropped -> %{status: "dropped", error_message: Map.get(attrs, :reason)}
        _ -> %{}
      end

    email_log
    |> cast(changes, [:status, :sent_at, :delivered_at, :opened_at, :clicked_at, :bounced_at,
                      :open_count, :click_count, :clicked_links, :error_message, :bounce_type])
  end
end
