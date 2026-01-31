defmodule MarketingAgent.Contacts do
  @moduledoc """
  Context module for managing marketing contacts.
  """
  import Ecto.Query
  alias MarketingAgent.Repo
  alias MarketingAgent.Contacts.Contact

  # ============================================================================
  # CRUD Operations
  # ============================================================================

  def list_contacts(opts \\ []) do
    Contact
    |> apply_filters(opts)
    |> apply_sorting(opts)
    |> Repo.all()
  end

  def get_contact(id), do: Repo.get(Contact, id)

  def get_contact!(id), do: Repo.get!(Contact, id)

  def get_contact_by_email(email) do
    Repo.get_by(Contact, email: String.downcase(email))
  end

  def create_contact(attrs) do
    %Contact{}
    |> Contact.changeset(normalize_attrs(attrs))
    |> Repo.insert()
  end

  def create_contact!(attrs) do
    %Contact{}
    |> Contact.changeset(normalize_attrs(attrs))
    |> Repo.insert!()
  end

  def update_contact(%Contact{} = contact, attrs) do
    contact
    |> Contact.changeset(attrs)
    |> Repo.update()
  end

  def delete_contact(%Contact{} = contact) do
    Repo.delete(contact)
  end

  # ============================================================================
  # Bulk Operations
  # ============================================================================

  def import_from_csv(file_path) do
    file_path
    |> File.stream!()
    |> NimbleCSV.RFC4180.parse_stream(skip_headers: false)
    |> Stream.transform(nil, fn
      row, nil ->
        # First row is headers
        headers = Enum.map(row, &String.downcase(&1) |> String.trim())
        {[], headers}

      row, headers ->
        attrs =
          headers
          |> Enum.zip(row)
          |> Enum.into(%{})
          |> normalize_csv_attrs()

        {[attrs], headers}
    end)
    |> Enum.reduce({0, 0, []}, fn attrs, {success, failed, errors} ->
      case create_contact(attrs) do
        {:ok, _contact} ->
          {success + 1, failed, errors}

        {:error, changeset} ->
          error = "#{attrs["company"]}: #{inspect(changeset.errors)}"
          {success, failed + 1, [error | errors]}
      end
    end)
  end

  defp normalize_csv_attrs(attrs) do
    %{
      "company" => attrs["company"],
      "first_name" => attrs["first_name"] || attrs["firstname"],
      "last_name" => attrs["last_name"] || attrs["lastname"],
      "email" => attrs["email"],
      "title" => attrs["title"] || attrs["job_title"],
      "phone" => attrs["phone"],
      "linkedin_url" => attrs["linkedin_url"] || attrs["linkedin"],
      "website" => attrs["website"],
      "segment" => attrs["segment"],
      "personalization" => attrs["personalization"],
      "notes" => attrs["notes"],
      "consent_source" => attrs["consent_source"] || "csv_import"
    }
  end

  # ============================================================================
  # Query Helpers
  # ============================================================================

  def count_by_status do
    Contact
    |> group_by([c], c.status)
    |> select([c], {c.status, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  def count_by_segment do
    Contact
    |> group_by([c], c.segment)
    |> select([c], {c.segment, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
  end

  def contacts_needing_enrichment(limit \\ 50) do
    Contact
    |> where([c], is_nil(c.email) or c.status == "new")
    |> where([c], is_nil(c.enriched_at))
    |> limit(^limit)
    |> Repo.all()
  end

  def contacts_for_followup do
    now = DateTime.utc_now()

    Contact
    |> where([c], c.status in ["contacted", "opened"])
    |> where([c], not is_nil(c.next_followup_at))
    |> where([c], c.next_followup_at <= ^now)
    |> where([c], is_nil(c.unsubscribed_at))
    |> Repo.all()
  end

  def contacts_by_segment(segment) do
    Contact
    |> where([c], c.segment == ^segment)
    |> where([c], is_nil(c.unsubscribed_at))
    |> Repo.all()
  end

  def enriched_contacts do
    Contact
    |> where([c], c.status == "enriched")
    |> where([c], not is_nil(c.email))
    |> where([c], is_nil(c.unsubscribed_at))
    |> Repo.all()
  end

  def contactable_contacts do
    Contact
    |> where([c], not is_nil(c.email))
    |> where([c], c.status in ["enriched", "new"])
    |> where([c], is_nil(c.unsubscribed_at))
    |> Repo.all()
  end

  # ============================================================================
  # Engagement Updates
  # ============================================================================

  def record_email_sent(%Contact{} = contact) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    contact
    |> Contact.engagement_changeset(%{
      emails_sent: (contact.emails_sent || 0) + 1,
      last_contacted_at: now,
      status: "contacted"
    })
    |> Repo.update()
  end

  def record_email_opened(%Contact{} = contact) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    contact
    |> Contact.engagement_changeset(%{
      emails_opened: (contact.emails_opened || 0) + 1,
      last_opened_at: now,
      status: if(contact.status in ["new", "enriched", "contacted"], do: "opened", else: contact.status)
    })
    |> Repo.update()
  end

  def record_email_clicked(%Contact{} = contact) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    contact
    |> Contact.engagement_changeset(%{
      emails_clicked: (contact.emails_clicked || 0) + 1,
      last_clicked_at: now,
      status: if(contact.status in ["new", "enriched", "contacted", "opened"], do: "clicked", else: contact.status)
    })
    |> Repo.update()
  end

  def record_reply(%Contact{} = contact) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    contact
    |> Contact.engagement_changeset(%{
      last_replied_at: now,
      status: "replied"
    })
    |> Repo.update()
  end

  def mark_unsubscribed(%Contact{} = contact) do
    contact
    |> Contact.changeset(%{
      status: "unsubscribed",
      unsubscribed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  def schedule_followup(%Contact{} = contact, days_from_now) do
    followup_at =
      DateTime.utc_now()
      |> DateTime.add(days_from_now * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    contact
    |> Contact.engagement_changeset(%{
      followup_count: (contact.followup_count || 0) + 1,
      next_followup_at: followup_at
    })
    |> Repo.update()
  end

  def update_enrichment(%Contact{} = contact, enrichment_data) do
    contact
    |> Contact.enrichment_changeset(enrichment_data)
    |> Repo.update()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp normalize_attrs(attrs) when is_map(attrs) do
    attrs
    |> Enum.map(fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {String.to_existing_atom(key), value}
    end)
    |> Enum.into(%{})
    |> Map.update(:email, nil, fn
      nil -> nil
      email -> String.downcase(String.trim(email))
    end)
  rescue
    ArgumentError -> attrs
  end

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, q -> where(q, [c], c.status == ^status)
      {:segment, segment}, q -> where(q, [c], c.segment == ^segment)
      {:has_email, true}, q -> where(q, [c], not is_nil(c.email))
      {:has_email, false}, q -> where(q, [c], is_nil(c.email))
      {:enriched, true}, q -> where(q, [c], not is_nil(c.enriched_at))
      {:enriched, false}, q -> where(q, [c], is_nil(c.enriched_at))
      {:search, term}, q ->
        term = "%#{term}%"
        where(q, [c], ilike(c.company, ^term) or ilike(c.email, ^term) or ilike(c.first_name, ^term))
      {:limit, limit}, q -> limit(q, ^limit)
      _, q -> q
    end)
  end

  defp apply_sorting(query, opts) do
    case Keyword.get(opts, :order_by, :inserted_at) do
      :inserted_at -> order_by(query, [c], desc: c.inserted_at)
      :company -> order_by(query, [c], asc: c.company)
      :last_contacted -> order_by(query, [c], desc: c.last_contacted_at)
      _ -> query
    end
  end
end
