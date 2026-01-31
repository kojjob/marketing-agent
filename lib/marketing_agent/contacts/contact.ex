defmodule MarketingAgent.Contacts.Contact do
  @moduledoc """
  Schema for marketing contacts.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contacts" do
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :company, :string
    field :title, :string
    field :phone, :string
    field :linkedin_url, :string
    field :website, :string
    field :segment, :string
    field :personalization, :string

    # Enrichment data
    field :company_size, :string
    field :industry, :string
    field :location, :string
    field :enriched_at, :utc_datetime

    # Status tracking
    field :status, :string, default: "new"
    # Status values: new, enriched, contacted, opened, clicked, replied, converted, unsubscribed, bounced

    # Engagement tracking
    field :emails_sent, :integer, default: 0
    field :emails_opened, :integer, default: 0
    field :emails_clicked, :integer, default: 0
    field :last_contacted_at, :utc_datetime
    field :last_opened_at, :utc_datetime
    field :last_clicked_at, :utc_datetime
    field :last_replied_at, :utc_datetime

    # Follow-up tracking
    field :followup_count, :integer, default: 0
    field :next_followup_at, :utc_datetime

    # Consent tracking (GDPR/CAN-SPAM)
    field :consent_source, :string
    field :consent_date, :utc_datetime
    field :unsubscribed_at, :utc_datetime

    # Metadata
    field :notes, :string
    field :tags, {:array, :string}, default: []
    field :custom_fields, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields [:company]
  @optional_fields [
    :email,
    :first_name,
    :last_name,
    :title,
    :phone,
    :linkedin_url,
    :website,
    :segment,
    :personalization,
    :company_size,
    :industry,
    :location,
    :enriched_at,
    :status,
    :emails_sent,
    :emails_opened,
    :emails_clicked,
    :last_contacted_at,
    :last_opened_at,
    :last_clicked_at,
    :last_replied_at,
    :followup_count,
    :next_followup_at,
    :consent_source,
    :consent_date,
    :unsubscribed_at,
    :notes,
    :tags,
    :custom_fields
  ]

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> unique_constraint(:email)
    |> validate_inclusion(:status, [
      "new",
      "enriched",
      "contacted",
      "opened",
      "clicked",
      "replied",
      "converted",
      "unsubscribed",
      "bounced"
    ])
  end

  def enrichment_changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :email,
      :first_name,
      :last_name,
      :title,
      :phone,
      :linkedin_url,
      :company_size,
      :industry,
      :location,
      :enriched_at
    ])
    |> put_change(:status, "enriched")
    |> put_change(:enriched_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def engagement_changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :emails_sent,
      :emails_opened,
      :emails_clicked,
      :last_contacted_at,
      :last_opened_at,
      :last_clicked_at,
      :last_replied_at,
      :followup_count,
      :next_followup_at,
      :status
    ])
  end

  def full_name(%__MODULE__{first_name: first, last_name: last}) do
    [first, last]
    |> Enum.filter(& &1)
    |> Enum.join(" ")
    |> case do
      "" -> nil
      name -> name
    end
  end
end
