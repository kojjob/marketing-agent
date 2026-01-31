defmodule MarketingAgent.AI.Personalization do
  @moduledoc """
  AI-powered email personalization service.

  Generates personalized email content based on contact and company data.
  Works with any configured AI provider (Claude, OpenAI, DeepSeek, Kimi, Qwen, etc.)

  ## Usage

      # Generate a personalized intro for a contact
      {:ok, intro} = Personalization.generate_intro(contact)

      # Generate a full personalized email
      {:ok, email} = Personalization.generate_email(contact, template: "cold-outreach")

      # Batch personalize contacts
      results = Personalization.personalize_batch(contacts)
  """

  alias MarketingAgent.AI.Provider
  alias MarketingAgent.Contacts
  alias MarketingAgent.Contacts.Contact

  @doc """
  Generate a personalized intro/opening line for a contact.

  Returns a 1-2 sentence personalized opening based on the contact's
  company, role, industry, and any available personalization notes.
  """
  def generate_intro(contact, opts \\ []) do
    unless Provider.available?() do
      {:error, :ai_not_configured}
    else
      do_generate_intro(contact, opts)
    end
  end

  @doc """
  Generate a personalized email body for a contact.

  Options:
    - :template - Template style ("cold-outreach", "follow-up", "demo-request")
    - :tone - Tone of voice ("professional", "casual", "friendly")
    - :max_length - Maximum length in words
  """
  def generate_email(contact, opts \\ []) do
    unless Provider.available?() do
      {:error, :ai_not_configured}
    else
      do_generate_email(contact, opts)
    end
  end

  @doc """
  Generate personalized subject line variations.

  Returns a list of 3-5 subject line options.
  """
  def generate_subject_lines(contact, opts \\ []) do
    unless Provider.available?() do
      {:error, :ai_not_configured}
    else
      do_generate_subject_lines(contact, opts)
    end
  end

  @doc """
  Batch personalize multiple contacts.

  Returns a map of contact_id => personalization result.
  Includes progress reporting via optional callback.
  """
  def personalize_batch(contacts, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress, fn _ -> :ok end)
    total = length(contacts)

    contacts
    |> Enum.with_index(1)
    |> Enum.reduce(%{success: 0, failed: 0, results: %{}}, fn {contact, idx}, acc ->
      on_progress.(%{current: idx, total: total, contact: contact})

      result = generate_intro(contact, opts)

      case result do
        {:ok, intro} ->
          # Save the personalization to the contact
          save_personalization(contact, intro)

          %{acc |
            success: acc.success + 1,
            results: Map.put(acc.results, contact.id, {:ok, intro})
          }

        {:error, reason} ->
          %{acc |
            failed: acc.failed + 1,
            results: Map.put(acc.results, contact.id, {:error, reason})
          }
      end
    end)
  end

  @doc """
  Check if AI personalization is available.
  """
  def available? do
    Provider.available?()
  end

  @doc """
  Get the current AI provider name.
  """
  def provider_name do
    if Provider.available?() do
      Provider.current().name()
    else
      "Not configured"
    end
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp do_generate_intro(contact, opts) do
    context = build_contact_context(contact)
    tone = Keyword.get(opts, :tone, "professional")

    system_prompt = """
    You are an expert B2B sales copywriter. Generate a personalized email opening line.

    Requirements:
    - 1-2 sentences maximum
    - Reference something specific about their company, role, or industry
    - Be #{tone} but not pushy
    - Focus on their potential needs or challenges
    - Do NOT include greetings like "Hi" or "Hello" - just the personalized hook
    - Do NOT mention that you're an AI or that this is AI-generated

    Be concise and impactful.
    """

    messages = [
      %{role: "user", content: """
      Generate a personalized email opening for this contact:

      #{context}

      Write only the personalized opening line (1-2 sentences). No greeting, no signature.
      """}
    ]

    Provider.chat(messages, system: system_prompt, max_tokens: 150, temperature: 0.8)
  end

  defp do_generate_email(contact, opts) do
    context = build_contact_context(contact)
    template = Keyword.get(opts, :template, "cold-outreach")
    tone = Keyword.get(opts, :tone, "professional")
    max_length = Keyword.get(opts, :max_length, 150)
    product_context = Keyword.get(opts, :product, "a B2B software solution")

    system_prompt = """
    You are an expert B2B sales copywriter. Generate a personalized outreach email.

    Email type: #{template}
    Tone: #{tone}
    Maximum length: #{max_length} words

    Requirements:
    - Personalize based on their company, role, and industry
    - Focus on value and solving their problems
    - Include a clear but soft call-to-action
    - Be #{tone} and respectful of their time
    - Do NOT be pushy or use aggressive sales tactics
    - Do NOT mention that you're an AI

    Product/Service context: #{product_context}
    """

    messages = [
      %{role: "user", content: """
      Generate a personalized #{template} email for this contact:

      #{context}

      Write the complete email body. Start with "Hi [First Name]," and end with a soft CTA.
      """}
    ]

    case Provider.chat(messages, system: system_prompt, max_tokens: 500, temperature: 0.7) do
      {:ok, email} ->
        # Replace placeholder with actual name
        first_name = contact.first_name || "there"
        email = String.replace(email, "[First Name]", first_name)
        {:ok, email}

      error -> error
    end
  end

  defp do_generate_subject_lines(contact, opts) do
    context = build_contact_context(contact)
    template = Keyword.get(opts, :template, "cold-outreach")

    system_prompt = """
    You are an expert email copywriter specializing in B2B subject lines.

    Generate 5 different subject line options that would have high open rates.

    Requirements:
    - Each subject line should be under 50 characters
    - Personalize when possible (company name, industry, etc.)
    - Vary the approach: curiosity, value prop, question, personalization, urgency
    - Avoid spam trigger words
    - Do NOT use all caps or excessive punctuation
    """

    messages = [
      %{role: "user", content: """
      Generate 5 subject line options for a #{template} email to this contact:

      #{context}

      Return ONLY the 5 subject lines, one per line, numbered 1-5.
      """}
    ]

    case Provider.chat(messages, system: system_prompt, max_tokens: 200, temperature: 0.9) do
      {:ok, response} ->
        subjects = response
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.map(&clean_subject_line/1)
          |> Enum.reject(&(&1 == ""))

        {:ok, subjects}

      error -> error
    end
  end

  defp clean_subject_line(line) do
    line
    |> String.replace(~r/^\d+[\.\)]\s*/, "")  # Remove numbering
    |> String.replace(~r/^["']|["']$/, "")     # Remove quotes
    |> String.trim()
  end

  defp build_contact_context(contact) do
    parts = [
      "Company: #{contact.company || "Unknown"}",
      if(contact.first_name, do: "Name: #{Contact.full_name(contact)}", else: nil),
      if(contact.title, do: "Title: #{contact.title}", else: nil),
      if(contact.industry, do: "Industry: #{contact.industry}", else: nil),
      if(contact.company_size, do: "Company Size: #{contact.company_size}", else: nil),
      if(contact.location, do: "Location: #{contact.location}", else: nil),
      if(contact.website, do: "Website: #{contact.website}", else: nil),
      if(contact.personalization, do: "Notes: #{contact.personalization}", else: nil)
    ]

    parts
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp save_personalization(contact, intro) do
    # Only update if contact doesn't already have personalization
    if is_nil(contact.personalization) or contact.personalization == "" do
      Contacts.update_contact(contact, %{personalization: intro})
    else
      {:ok, contact}
    end
  end
end
