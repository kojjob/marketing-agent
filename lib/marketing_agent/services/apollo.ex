defmodule MarketingAgent.Services.Apollo do
  @moduledoc """
  Apollo.io API integration for contact enrichment and discovery.
  """
  require Logger

  @base_url "https://api.apollo.io/v1"

  # ============================================================================
  # Contact Enrichment
  # ============================================================================

  @doc """
  Enrich a contact by company name and optional person details.

  Returns enriched data including email, title, company info, etc.
  """
  def enrich_contact(company, opts \\ []) do
    first_name = Keyword.get(opts, :first_name)
    last_name = Keyword.get(opts, :last_name)
    domain = Keyword.get(opts, :domain)
    linkedin_url = Keyword.get(opts, :linkedin_url)

    # Try people enrichment first if we have enough info
    cond do
      linkedin_url ->
        enrich_by_linkedin(linkedin_url)

      first_name && last_name && (company || domain) ->
        enrich_person(first_name, last_name, company, domain)

      company || domain ->
        search_people_at_company(company, domain, opts)

      true ->
        {:error, :insufficient_data}
    end
  end

  @doc """
  Enrich a contact using their LinkedIn URL.
  """
  def enrich_by_linkedin(linkedin_url) do
    body = %{
      linkedin_url: linkedin_url,
      reveal_personal_emails: false
    }

    case post("/people/match", body) do
      {:ok, %{status: 200, body: %{"person" => person}}} when not is_nil(person) ->
        {:ok, normalize_person(person)}

      {:ok, %{status: 200}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Apollo enrich error: #{status} - #{inspect(body)}")
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Enrich a person by name and company.
  """
  def enrich_person(first_name, last_name, company, domain \\ nil) do
    body =
      %{
        first_name: first_name,
        last_name: last_name,
        reveal_personal_emails: false
      }
      |> maybe_add(:organization_name, company)
      |> maybe_add(:domain, domain)

    case post("/people/match", body) do
      {:ok, %{status: 200, body: %{"person" => person}}} when not is_nil(person) ->
        {:ok, normalize_person(person)}

      {:ok, %{status: 200}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Apollo enrich error: #{status} - #{inspect(body)}")
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Search for people at a company.

  ## Options
  - :title_keywords - Keywords to filter by job title
  - :seniority - List of seniority levels (e.g., ["director", "vp", "c_suite"])
  - :limit - Number of results (default: 5)
  """
  def search_people_at_company(company, domain \\ nil, opts \\ []) do
    title_keywords = Keyword.get(opts, :title_keywords, [])
    seniority = Keyword.get(opts, :seniority, [])
    limit = Keyword.get(opts, :limit, 5)

    body =
      %{
        page: 1,
        per_page: limit,
        reveal_personal_emails: false
      }
      |> maybe_add(:q_organization_name, company)
      |> maybe_add(:q_organization_domains, if(domain, do: [domain], else: nil))
      |> maybe_add(:person_titles, if(title_keywords != [], do: title_keywords, else: nil))
      |> maybe_add(:person_seniorities, if(seniority != [], do: seniority, else: nil))

    case post("/mixed_people/search", body) do
      {:ok, %{status: 200, body: %{"people" => people}}} when is_list(people) ->
        results = Enum.map(people, &normalize_person/1)
        {:ok, results}

      {:ok, %{status: 200}} ->
        {:ok, []}

      {:ok, %{status: status, body: body}} ->
        Logger.error("Apollo search error: #{status} - #{inspect(body)}")
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Company Enrichment
  # ============================================================================

  @doc """
  Enrich company data by domain or name.
  """
  def enrich_company(domain: domain) when is_binary(domain) do
    body = %{domain: domain}

    case post("/organizations/enrich", body) do
      {:ok, %{status: 200, body: %{"organization" => org}}} when not is_nil(org) ->
        {:ok, normalize_organization(org)}

      {:ok, %{status: 200}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def enrich_company(name: name) when is_binary(name) do
    # Search for company first
    body = %{
      q_organization_name: name,
      page: 1,
      per_page: 1
    }

    case post("/mixed_companies/search", body) do
      {:ok, %{status: 200, body: %{"organizations" => [org | _]}}} ->
        {:ok, normalize_organization(org)}

      {:ok, %{status: 200}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Email Finder
  # ============================================================================

  @doc """
  Find email address for a person.
  Uses credits - use sparingly!
  """
  def find_email(first_name, last_name, domain) do
    body = %{
      first_name: first_name,
      last_name: last_name,
      domain: domain,
      reveal_personal_emails: false
    }

    case post("/people/match", body) do
      {:ok, %{status: 200, body: %{"person" => %{"email" => email}}}} when is_binary(email) ->
        {:ok, email}

      {:ok, %{status: 200}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Account Info
  # ============================================================================

  @doc """
  Get Apollo account credits remaining.
  """
  def get_credits do
    case get("/auth/health") do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{
          credits_remaining: body["credits_remaining"],
          credits_used: body["credits_used"]
        }}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp post(path, body) do
    url = @base_url <> path
    body_with_key = Map.put(body, :api_key, api_key())

    case Req.post(url, json: body_with_key) do
      {:ok, response} ->
        {:ok, %{
          status: response.status,
          body: response.body
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get(path) do
    url = @base_url <> path <> "?api_key=#{api_key()}"

    case Req.get(url) do
      {:ok, response} ->
        {:ok, %{
          status: response.status,
          body: response.body
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_key do
    Application.get_env(:marketing_agent, __MODULE__)[:api_key] ||
      raise "Apollo API key not configured. Set APOLLO_API_KEY environment variable."
  end

  defp normalize_person(nil), do: nil

  defp normalize_person(person) do
    %{
      email: person["email"],
      first_name: person["first_name"],
      last_name: person["last_name"],
      title: person["title"],
      phone: get_in(person, ["phone_numbers", Access.at(0), "sanitized_number"]),
      linkedin_url: person["linkedin_url"],
      company: person["organization_name"],
      company_size: person["organization"][:estimated_num_employees] || person["organization_num_employees_ranges"],
      industry: person["industry"] || get_in(person, ["organization", "industry"]),
      location: [person["city"], person["state"], person["country"]]
                |> Enum.filter(& &1)
                |> Enum.join(", "),
      seniority: person["seniority"],
      departments: person["departments"]
    }
  end

  defp normalize_organization(org) do
    %{
      name: org["name"],
      domain: org["primary_domain"],
      industry: org["industry"],
      size: org["estimated_num_employees"],
      size_range: org["num_employees_ranges"],
      founded: org["founded_year"],
      location: [org["city"], org["state"], org["country"]]
                |> Enum.filter(& &1)
                |> Enum.join(", "),
      linkedin_url: org["linkedin_url"],
      twitter_url: org["twitter_url"],
      technologies: org["technologies"],
      revenue: org["annual_revenue"],
      description: org["short_description"]
    }
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)
end
