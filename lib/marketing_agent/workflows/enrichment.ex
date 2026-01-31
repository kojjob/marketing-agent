defmodule MarketingAgent.Workflows.Enrichment do
  @moduledoc """
  Workflow for enriching contacts using Apollo.io.
  """
  require Logger

  alias MarketingAgent.Contacts
  alias MarketingAgent.Services.Apollo

  @doc """
  Enrich a batch of contacts.

  Returns %{success: count, failed: count, results: []}
  """
  def enrich_batch(contacts, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 500)

    results =
      contacts
      |> Enum.with_index()
      |> Enum.map(fn {contact, index} ->
        # Rate limiting
        if index > 0, do: Process.sleep(delay_ms)

        enrich_single(contact)
      end)

    success = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    %{
      success: success,
      failed: failed,
      results: results
    }
  end

  @doc """
  Enrich a single contact.
  """
  def enrich_single(contact) do
    Logger.info("Enriching contact: #{contact.company}")

    opts = [
      first_name: contact.first_name,
      last_name: contact.last_name,
      domain: extract_domain(contact.website),
      linkedin_url: contact.linkedin_url
    ]

    case Apollo.enrich_contact(contact.company, opts) do
      {:ok, enriched_data} when is_map(enriched_data) ->
        update_contact_with_enrichment(contact, enriched_data)

      {:ok, [first | _]} ->
        # Got a list of results, use the first one
        update_contact_with_enrichment(contact, first)

      {:ok, []} ->
        Logger.info("No enrichment data found for #{contact.company}")
        {:error, :no_data}

      {:error, :insufficient_data} ->
        Logger.info("Insufficient data for enrichment: #{contact.company}")
        {:error, :insufficient_data}

      {:error, :not_found} ->
        Logger.info("Contact not found in Apollo: #{contact.company}")
        {:error, :not_found}

      {:error, reason} ->
        Logger.error("Enrichment failed for #{contact.company}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Search for contacts at a company and enrich.
  Useful when you only have company name but need to find key contacts.
  """
  def find_and_enrich_at_company(company, opts \\ []) do
    title_keywords = Keyword.get(opts, :title_keywords, ["CTO", "VP Engineering", "Director", "Head of"])
    seniority = Keyword.get(opts, :seniority, ["director", "vp", "c_suite"])
    limit = Keyword.get(opts, :limit, 3)

    search_opts = [
      title_keywords: title_keywords,
      seniority: seniority,
      limit: limit
    ]

    case Apollo.search_people_at_company(company, nil, search_opts) do
      {:ok, people} when is_list(people) and people != [] ->
        # Create contacts for each found person
        results =
          Enum.map(people, fn person ->
            attrs = %{
              company: company,
              email: person.email,
              first_name: person.first_name,
              last_name: person.last_name,
              title: person.title,
              phone: person.phone,
              linkedin_url: person.linkedin_url,
              company_size: person.company_size,
              industry: person.industry,
              location: person.location,
              status: "enriched",
              enriched_at: DateTime.utc_now() |> DateTime.truncate(:second),
              consent_source: "apollo_search"
            }

            case Contacts.create_contact(attrs) do
              {:ok, contact} -> {:ok, contact}
              {:error, _} = error -> error
            end
          end)

        success = Enum.count(results, &match?({:ok, _}, &1))
        {:ok, %{found: length(people), created: success}}

      {:ok, []} ->
        {:error, :no_contacts_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp update_contact_with_enrichment(contact, enriched_data) do
    attrs = %{
      email: enriched_data[:email] || contact.email,
      first_name: enriched_data[:first_name] || contact.first_name,
      last_name: enriched_data[:last_name] || contact.last_name,
      title: enriched_data[:title] || contact.title,
      phone: enriched_data[:phone] || contact.phone,
      linkedin_url: enriched_data[:linkedin_url] || contact.linkedin_url,
      company_size: enriched_data[:company_size] || contact.company_size,
      industry: enriched_data[:industry] || contact.industry,
      location: enriched_data[:location] || contact.location
    }

    case Contacts.update_enrichment(contact, attrs) do
      {:ok, updated} ->
        Logger.info("Successfully enriched #{contact.company}: #{updated.email}")
        {:ok, updated}

      {:error, changeset} ->
        Logger.error("Failed to update contact: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  defp extract_domain(nil), do: nil
  defp extract_domain(url) when is_binary(url) do
    url
    |> String.replace(~r/^https?:\/\//, "")
    |> String.replace(~r/^www\./, "")
    |> String.split("/")
    |> List.first()
  end
end
