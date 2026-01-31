defmodule MarketingAgent.CLI do
  @moduledoc """
  Command-line interface for the Marketing Agent.
  """

  alias MarketingAgent.{Contacts, Campaigns, Templates, CsvHandler}
  alias MarketingAgent.Services.Apollo
  alias MarketingAgent.Workflows.{Enrichment, Outreach, Followup}
  alias MarketingAgent.AI.Personalization
  alias MarketingAgent.Email.SendGrid

  def main(args) do
    # Load environment variables from user config
    load_user_env()

    # Ensure application is started
    Application.ensure_all_started(:marketing_agent)

    # Auto-migrate database if needed
    ensure_database_ready()

    args
    |> parse_args()
    |> run()
  end

  defp load_user_env do
    user_env_path = Path.join([System.user_home!(), ".marketing_agent", ".env"])

    if File.exists?(user_env_path) do
      Dotenvy.source!(user_env_path)
    end
  end

  defp ensure_database_ready do
    # Run migrations silently if database exists
    try do
      Ecto.Migrator.run(
        MarketingAgent.Repo,
        :up,
        all: true,
        log: false
      )
    rescue
      _ -> :ok
    end
  end

  defp parse_args(args) do
    {opts, commands, _} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          segment: :string,
          template: :string,
          campaign: :integer,
          limit: :integer,
          confirm: :boolean,
          email: :string,
          company: :string,
          name: :string,
          title: :string,
          days: :integer,
          # CSV import/export options
          mode: :string,
          dry_run: :boolean,
          upsert: :boolean,
          output: :string,
          status: :string,
          columns: :string,
          format: :string,
          # AI personalization options
          tone: :string
        ],
        aliases: [
          h: :help,
          s: :segment,
          t: :template,
          c: :campaign,
          l: :limit,
          o: :output,
          m: :mode
        ]
      )

    {commands, opts}
  end

  # ============================================================================
  # Commands
  # ============================================================================

  defp run({["help"], _opts}), do: print_help()
  defp run({[], _opts}), do: print_help()

  # --- Database ---
  defp run({["init"], _opts}) do
    IO.puts("Initializing database...")
    Mix.Task.run("ecto.create", [])
    Mix.Task.run("ecto.migrate", [])
    IO.puts("✓ Database initialized successfully!")
  end

  # --- CSV Import/Export ---
  defp run({["import", file], opts}) do
    import_contacts(file, opts)
  end

  # Alias for backward compatibility
  defp run({["add-contacts", file], opts}) do
    import_contacts(file, opts)
  end

  defp run({["export"], opts}) do
    export_contacts(opts)
  end

  defp run({["export", file], opts}) do
    export_contacts(Keyword.put(opts, :output, file))
  end

  defp run({["csv-template"], _opts}) do
    IO.puts("Sample CSV template:")
    IO.puts("")
    IO.puts(CsvHandler.sample_template())
    IO.puts("")
    IO.puts("Save this to a file and fill in your data.")
    IO.puts("Required column: company")
    IO.puts("Recommended: email, first_name, last_name, title, segment")
  end

  defp run({["validate-csv", file], opts}) do
    IO.puts("Validating CSV file: #{file}\n")

    result = CsvHandler.validate(file, build_import_opts(opts))

    print_import_result(result, dry_run: true)
  end

  # --- Contacts ---

  defp run({["add-contact"], opts}) do
    attrs = %{
      company: opts[:company],
      email: opts[:email],
      first_name: extract_first_name(opts[:name]),
      last_name: extract_last_name(opts[:name]),
      title: opts[:title],
      segment: opts[:segment]
    }

    case Contacts.create_contact(attrs) do
      {:ok, contact} ->
        IO.puts("✓ Created contact: #{contact.company}")

      {:error, changeset} ->
        IO.puts("✗ Failed to create contact:")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("  - #{field}: #{msg}")
        end)
    end
  end

  defp run({["list-contacts"], opts}) do
    contacts = Contacts.list_contacts(opts)
    print_contacts_table(contacts)
  end

  defp run({["show-contact", id], _opts}) do
    case Contacts.get_contact(id) do
      nil -> IO.puts("Contact not found")
      contact -> print_contact_details(contact)
    end
  end

  # --- Enrichment ---
  defp run({["enrich"], opts}) do
    limit = opts[:limit] || 10
    segment = opts[:segment]

    IO.puts("Enriching contacts...")
    IO.puts("This will use Apollo API credits. Continue? [y/N]")

    if confirm?() do
      contacts =
        if segment do
          Contacts.contacts_by_segment(segment)
        else
          Contacts.contacts_needing_enrichment(limit)
        end

      IO.puts("Found #{length(contacts)} contacts to enrich")

      results = Enrichment.enrich_batch(contacts)

      IO.puts("\n✓ Enriched #{results.success} contacts")
      IO.puts("✗ Failed: #{results.failed}")
    else
      IO.puts("Cancelled")
    end
  end

  defp run({["credits"], _opts}) do
    case Apollo.get_credits() do
      {:ok, info} ->
        IO.puts("Apollo Credits:")
        IO.puts("  Remaining: #{info.credits_remaining}")
        IO.puts("  Used: #{info.credits_used}")

      {:error, _} ->
        IO.puts("✗ Failed to fetch credit info. Check API key.")
    end
  end

  # --- Templates ---
  defp run({["templates"], _opts}) do
    templates = Templates.list_templates()
    print_templates_table(templates)
  end

  defp run({["preview-template", name], opts}) do
    contact =
      if opts[:email] do
        Contacts.get_contact_by_email(opts[:email])
      else
        # Use sample contact
        %{
          first_name: "John",
          last_name: "Doe",
          company: "Acme Corp",
          title: "VP Engineering",
          personalization: "your innovative RTB platform"
        }
      end

    case Templates.preview(name, contact) do
      {:ok, rendered} ->
        IO.puts("\n--- Subject ---")
        IO.puts(rendered.subject)
        IO.puts("\n--- Body ---")
        IO.puts(rendered.body)

      {:error, :not_found} ->
        IO.puts("✗ Template '#{name}' not found")
    end
  end

  # --- Campaigns ---
  defp run({["create-campaign"], opts}) do
    template = opts[:template] || raise "Template required (--template)"
    segment = opts[:segment]
    name = "Campaign #{Date.utc_today()}"

    # Load template to get subject
    template_data = Templates.load_template!(template)

    case Campaigns.create_campaign(%{
      name: name,
      template_name: template,
      subject: template_data.subject,
      segment: segment,
      status: "draft"
    }) do
      {:ok, campaign} ->
        IO.puts("✓ Created campaign: #{campaign.id}")
        IO.puts("  Template: #{template}")
        IO.puts("  Segment: #{segment || "all"}")
        IO.puts("  Status: draft")
        IO.puts("\nUse 'preview --campaign #{campaign.id}' to review")
        IO.puts("Then 'send --campaign #{campaign.id} --confirm' to send")

      {:error, changeset} ->
        IO.puts("✗ Failed to create campaign:")
        Enum.each(changeset.errors, fn {field, {msg, _}} ->
          IO.puts("  - #{field}: #{msg}")
        end)
    end
  end

  defp run({["list-campaigns"], opts}) do
    campaigns = Campaigns.list_campaigns(opts)
    print_campaigns_table(campaigns)
  end

  defp run({["preview"], opts}) do
    campaign_id = opts[:campaign] || raise "Campaign ID required (--campaign)"

    case Campaigns.get_campaign(campaign_id) do
      nil ->
        IO.puts("Campaign not found")

      campaign ->
        contacts =
          if campaign.segment do
            Contacts.contacts_by_segment(campaign.segment)
          else
            Contacts.contactable_contacts()
          end

        IO.puts("\n=== Campaign Preview ===")
        IO.puts("Name: #{campaign.name}")
        IO.puts("Template: #{campaign.template_name}")
        IO.puts("Segment: #{campaign.segment || "all"}")
        IO.puts("Recipients: #{length(contacts)}")
        IO.puts("Status: #{campaign.status}")

        if length(contacts) > 0 do
          IO.puts("\n--- Sample Email (first recipient) ---")
          sample = List.first(contacts)

          case Templates.preview(campaign.template_name, sample) do
            {:ok, rendered} ->
              IO.puts("To: #{sample.email}")
              IO.puts("Subject: #{rendered.subject}")
              IO.puts("\n#{rendered.body}")

            {:error, _} ->
              IO.puts("✗ Failed to render template")
          end
        end
    end
  end

  defp run({["send"], opts}) do
    campaign_id = opts[:campaign] || raise "Campaign ID required (--campaign)"
    confirm = opts[:confirm] || false

    case Campaigns.get_campaign(campaign_id) do
      nil ->
        IO.puts("Campaign not found")

      %{status: status} when status not in ["draft", "approved"] ->
        IO.puts("Campaign cannot be sent (status: #{status})")

      campaign ->
        contacts =
          if campaign.segment do
            Contacts.contacts_by_segment(campaign.segment)
          else
            Contacts.contactable_contacts()
          end

        IO.puts("\n=== Send Campaign ===")
        IO.puts("Campaign: #{campaign.name}")
        IO.puts("Recipients: #{length(contacts)}")

        # Check daily limit
        today_count = Campaigns.today_send_count()
        daily_limit = Application.get_env(:marketing_agent, MarketingAgent.Config)[:daily_send_limit] || 100

        IO.puts("Today's sends: #{today_count}/#{daily_limit}")

        remaining = daily_limit - today_count
        to_send = min(length(contacts), remaining)

        if to_send == 0 do
          IO.puts("\n✗ Daily limit reached. Try again tomorrow.")
        else
          IO.puts("\nWill send #{to_send} emails.")

          if confirm do
            IO.puts("\nSending...")
            result = Outreach.send_campaign(campaign, Enum.take(contacts, to_send))
            IO.puts("\n✓ Sent #{result.sent} emails")
            IO.puts("✗ Failed: #{result.failed}")
          else
            IO.puts("\nTo confirm, run: send --campaign #{campaign_id} --confirm")
          end
        end
    end
  end

  # --- Follow-ups ---
  defp run({["send-followups"], opts}) do
    confirm = opts[:confirm] || false
    contacts = Contacts.contacts_for_followup()

    IO.puts("Found #{length(contacts)} contacts due for follow-up")

    if length(contacts) > 0 && confirm do
      result = Followup.send_due_followups()
      IO.puts("✓ Sent #{result.sent} follow-up emails")
      IO.puts("✗ Failed: #{result.failed}")
    else
      IO.puts("\nTo send, run: send-followups --confirm")
    end
  end

  # --- SendGrid Email ---
  defp run({["email-status"], _opts}) do
    IO.puts("\n=== SendGrid Email Status ===\n")

    status = SendGrid.status()

    if status.configured do
      IO.puts("  Status: ✓ Configured")
      IO.puts("  From: #{status.from_name} <#{status.from_email}>")
      IO.puts("  Daily Limit: #{status.daily_limit}")
      IO.puts("  API Key: #{if status.api_key_set, do: "✓ Set", else: "✗ Not set"}")
    else
      IO.puts("  Status: ✗ Not configured")
      IO.puts("\n  To configure SendGrid, set environment variables:")
      IO.puts("    SENDGRID_API_KEY=your-api-key")
      IO.puts("    SENDGRID_FROM_EMAIL=sender@yourdomain.com")
      IO.puts("    SENDGRID_FROM_NAME=\"Your Name\"")
      IO.puts("\n  Add these to ~/.marketing_agent/.env")
    end
  end

  defp run({["send-email", contact_id], opts}) do
    template = opts[:template] || "cold-email-1"
    dry_run = opts[:dry_run] || false

    IO.puts("\n=== Send Email ===\n")

    case SendGrid.send_email(contact_id, template, dry_run: dry_run) do
      {:ok, result} ->
        if dry_run do
          IO.puts("  Mode: DRY RUN (no email sent)")
        else
          IO.puts("  Status: ✓ Email sent!")
        end
        IO.puts("  To: #{result.contact_email}")
        IO.puts("  Template: #{template}")
        IO.puts("  Message ID: #{result.message_id}")

      {:error, :not_configured} ->
        IO.puts("  ✗ SendGrid not configured")
        IO.puts("  Run: email-status for setup instructions")

      {:error, :no_email} ->
        IO.puts("  ✗ Contact has no email address")

      {:error, :unsubscribed} ->
        IO.puts("  ✗ Contact is unsubscribed")

      {:error, :bounced} ->
        IO.puts("  ✗ Contact email has bounced")

      {:error, :not_found} ->
        IO.puts("  ✗ Contact not found")

      {:error, reason} ->
        IO.puts("  ✗ Failed to send: #{inspect(reason)}")
    end
  end

  defp run({["send-email-batch"], opts}) do
    template = opts[:template] || "cold-email-1"
    segment = opts[:segment]
    limit = opts[:limit] || 10
    confirm = opts[:confirm] || false
    dry_run = opts[:dry_run] || false

    IO.puts("\n=== Batch Email Send ===\n")

    unless SendGrid.configured?() do
      IO.puts("  ✗ SendGrid not configured")
      IO.puts("  Run: email-status for setup instructions")
    else
      # Count eligible contacts
      contacts = get_batch_contacts_preview(segment, limit)
      total = length(contacts)

      IO.puts("  Template: #{template}")
      IO.puts("  Segment: #{segment || "all"}")
      IO.puts("  Eligible contacts: #{total}")

      if dry_run do
        IO.puts("  Mode: DRY RUN")
      end

      cond do
        total == 0 ->
          IO.puts("\n  No eligible contacts found.")
          IO.puts("  (Contacts must have email and status 'new' or 'enriched')")

        !confirm && !dry_run ->
          IO.puts("\n  Preview of first 5 contacts:")
          contacts
          |> Enum.take(5)
          |> Enum.each(fn c ->
            IO.puts("    • #{c.email} (#{c.company})")
          end)

          IO.puts("\n  To send, run:")
          IO.puts("    send-email-batch --template #{template}#{if segment, do: " --segment #{segment}", else: ""} --limit #{limit} --confirm")
          IO.puts("\n  To preview without sending:")
          IO.puts("    send-email-batch --template #{template}#{if segment, do: " --segment #{segment}", else: ""} --limit #{limit} --dry-run")

        true ->
          IO.puts("\n  Sending emails...")

          progress_callback = fn current, total ->
            percent = round(current / total * 100)
            IO.write("\r  Progress: #{current}/#{total} (#{percent}%)")
          end

          result = SendGrid.send_batch(template,
            segment: segment,
            status: "new",
            limit: limit,
            dry_run: dry_run,
            on_progress: progress_callback
          )

          {:ok, stats} = result

          IO.puts("\n\n  Results:")
          IO.puts("    ✓ Sent: #{stats.sent}")
          IO.puts("    ✗ Failed: #{stats.failed}")

          if length(stats.errors) > 0 do
            IO.puts("\n  Errors:")
            Enum.each(stats.errors, fn {id, reason} ->
              IO.puts("    #{String.slice(id, 0, 8)}: #{inspect(reason)}")
            end)
          end
      end
    end
  end

  defp run({["preview-send", contact_id], opts}) do
    template = opts[:template] || "cold-email-1"

    IO.puts("\n=== Email Preview ===\n")

    case SendGrid.preview_email(contact_id, template) do
      {:ok, preview} ->
        IO.puts("To: #{preview.to}")
        IO.puts("From: #{preview.from}")
        IO.puts("Subject: #{preview.subject}")
        IO.puts("\n--- Text Body ---\n")
        IO.puts(preview.text_body)
        IO.puts("\n-----------------")

      {:error, :not_found} ->
        IO.puts("  ✗ Contact not found")

      {:error, reason} ->
        IO.puts("  ✗ Failed to generate preview: #{inspect(reason)}")
    end
  end

  # --- AI Personalization ---
  defp run({["ai-status"], _opts}) do
    IO.puts("\n=== AI Provider Status ===\n")

    if Personalization.available?() do
      provider = Personalization.provider_name()
      IO.puts("  Status: ✓ Available")
      IO.puts("  Provider: #{provider}")
      IO.puts("\n  Configuration via environment variables:")
      IO.puts("    AI_PROVIDER=#{System.get_env("AI_PROVIDER") || "(not set)"}")
      IO.puts("    AI_MODEL=#{System.get_env("AI_MODEL") || "(using default)"}")
      IO.puts("    AI_BASE_URL=#{System.get_env("AI_BASE_URL") || "(using default)"}")
    else
      IO.puts("  Status: ✗ Not configured")
      IO.puts("\n  To enable AI personalization, set environment variables:")
      IO.puts("    AI_PROVIDER=deepseek|kimi|qwen|claude|gemini|openai|ollama|...")
      IO.puts("    AI_API_KEY=your-api-key")
      IO.puts("    AI_MODEL=model-name (optional)")
      IO.puts("\n  Supported providers:")
      IO.puts("    Cloud: deepseek, kimi, qwen, claude, gemini, openai, mistral, groq")
      IO.puts("    Local: ollama, lmstudio, localai, vllm")
    end
  end

  defp run({["personalize", id], opts}) do
    case Contacts.get_contact(id) do
      nil ->
        IO.puts("Contact not found")

      contact ->
        IO.puts("Generating personalized intro for: #{contact.company}")

        tone = opts[:tone] || "professional"
        case Personalization.generate_intro(contact, tone: tone) do
          {:ok, intro} ->
            IO.puts("\n--- Generated Intro ---")
            IO.puts(intro)
            IO.puts("\nSave this personalization? [y/N]")

            if confirm?() do
              Contacts.update_contact(contact, %{personalization: intro})
              IO.puts("✓ Saved to contact")
            end

          {:error, :ai_not_configured} ->
            IO.puts("✗ AI not configured. Run 'ai-status' for setup instructions.")

          {:error, reason} ->
            IO.puts("✗ Failed to generate: #{inspect(reason)}")
        end
    end
  end

  defp run({["personalize-batch"], opts}) do
    unless Personalization.available?() do
      IO.puts("✗ AI not configured. Run 'ai-status' for setup instructions.")
    else
      segment = opts[:segment]
      limit = opts[:limit] || 10
      confirm = opts[:confirm] || false

      contacts =
        if segment do
          Contacts.contacts_by_segment(segment)
        else
          Contacts.list_contacts(limit: limit)
        end
        |> Enum.filter(&(is_nil(&1.personalization) or &1.personalization == ""))
        |> Enum.take(limit)

      if length(contacts) == 0 do
        IO.puts("No contacts found needing personalization.")
      else
        IO.puts("Found #{length(contacts)} contacts to personalize")
        IO.puts("Provider: #{Personalization.provider_name()}")
        IO.puts("\nThis will use API credits. Continue? [y/N]")

        if confirm or confirm?() do
          IO.puts("\nGenerating personalizations...")

          progress_fn = fn %{current: current, total: total} ->
            percent = if total > 0, do: round(current / total * 100), else: 0
            IO.write("\r  Progress: #{current}/#{total} (#{percent}%)")
          end

          result = Personalization.personalize_batch(contacts, on_progress: progress_fn)

          IO.puts("\n\n=== Results ===")
          IO.puts("  ✓ Success: #{result.success}")
          IO.puts("  ✗ Failed: #{result.failed}")

          # Show sample results
          if result.success > 0 do
            IO.puts("\n--- Sample Generated Intros ---")
            result.results
            |> Enum.filter(fn {_id, res} -> match?({:ok, _}, res) end)
            |> Enum.take(3)
            |> Enum.each(fn {id, {:ok, intro}} ->
              contact = Contacts.get_contact(id)
              IO.puts("\n#{contact.company}:")
              IO.puts("  #{String.slice(intro, 0, 150)}...")
            end)
          end
        else
          IO.puts("Cancelled")
        end
      end
    end
  end

  defp run({["generate-email", id], opts}) do
    case Contacts.get_contact(id) do
      nil ->
        IO.puts("Contact not found")

      contact ->
        IO.puts("Generating personalized email for: #{contact.company}")

        template = opts[:template] || "cold-outreach"
        tone = opts[:tone] || "professional"

        case Personalization.generate_email(contact, template: template, tone: tone) do
          {:ok, email} ->
            IO.puts("\n--- Generated Email ---")
            IO.puts(email)

          {:error, :ai_not_configured} ->
            IO.puts("✗ AI not configured. Run 'ai-status' for setup instructions.")

          {:error, reason} ->
            IO.puts("✗ Failed to generate: #{inspect(reason)}")
        end
    end
  end

  defp run({["generate-subjects", id], opts}) do
    case Contacts.get_contact(id) do
      nil ->
        IO.puts("Contact not found")

      contact ->
        IO.puts("Generating subject lines for: #{contact.company}")

        template = opts[:template] || "cold-outreach"

        case Personalization.generate_subject_lines(contact, template: template) do
          {:ok, subjects} ->
            IO.puts("\n--- Subject Line Options ---")
            Enum.with_index(subjects, 1)
            |> Enum.each(fn {subject, idx} ->
              IO.puts("  #{idx}. #{subject}")
            end)

          {:error, :ai_not_configured} ->
            IO.puts("✗ AI not configured. Run 'ai-status' for setup instructions.")

          {:error, reason} ->
            IO.puts("✗ Failed to generate: #{inspect(reason)}")
        end
    end
  end

  # --- Stats ---
  defp run({["stats"], _opts}) do
    contact_stats = Contacts.count_by_status()
    campaign_stats = Campaigns.overall_stats()

    IO.puts("\n=== Marketing Agent Stats ===\n")

    IO.puts("Contacts by Status:")
    Enum.each(contact_stats, fn {status, count} ->
      IO.puts("  #{status}: #{count}")
    end)

    IO.puts("\nCampaign Performance:")
    IO.puts("  Total campaigns: #{campaign_stats.total_campaigns}")
    IO.puts("  Total sent: #{campaign_stats.total_sent}")
    IO.puts("  Open rate: #{Float.round(campaign_stats.avg_open_rate, 1)}%")
    IO.puts("  Click rate: #{Float.round(campaign_stats.avg_click_rate, 1)}%")
    IO.puts("  Reply rate: #{Float.round(campaign_stats.avg_reply_rate, 1)}%")
  end

  defp run({["report"], opts}) do
    campaign_id = opts[:campaign] || raise "Campaign ID required (--campaign)"

    case Campaigns.campaign_stats(campaign_id) do
      %{campaign: campaign} = stats ->
        IO.puts("\n=== Campaign Report ===")
        IO.puts("Name: #{campaign.name}")
        IO.puts("Template: #{campaign.template_name}")
        IO.puts("Status: #{campaign.status}")
        IO.puts("\nMetrics:")
        IO.puts("  Sent: #{campaign.emails_sent}")
        IO.puts("  Opened: #{campaign.emails_opened} (#{Float.round(stats.open_rate, 1)}%)")
        IO.puts("  Clicked: #{campaign.emails_clicked} (#{Float.round(stats.click_rate, 1)}%)")
        IO.puts("  Bounced: #{campaign.emails_bounced} (#{Float.round(stats.bounce_rate, 1)}%)")
        IO.puts("  Replies: #{campaign.replies_received} (#{Float.round(stats.reply_rate, 1)}%)")
    end
  end

  defp run({[cmd | _], _opts}) do
    IO.puts("Unknown command: #{cmd}")
    print_help()
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp print_help do
    IO.puts("""

    Marketing Agent CLI

    Usage: marketing <command> [options]

    CSV IMPORT/EXPORT:
      import <file>             Import contacts from CSV
        --segment SEGMENT       Assign segment to all imports
        --upsert                Update existing contacts (match by email)
        --dry-run               Validate without importing

      export [file]             Export contacts to CSV (stdout if no file)
        --segment SEGMENT       Filter by segment
        --status STATUS         Filter by status
        --limit N               Limit results
        --columns COLS          Comma-separated columns to include

      validate-csv <file>       Validate CSV without importing
      csv-template              Show sample CSV template

    CONTACTS:
      add-contact               Add single contact
        --company COMPANY       Company name (required)
        --email EMAIL           Email address
        --name NAME             Full name
        --title TITLE           Job title
        --segment SEGMENT       Segment name

      list-contacts             List all contacts
        --segment SEGMENT       Filter by segment
        --limit N               Limit results

      show-contact <id>         Show contact details

    ENRICHMENT:
      enrich                    Enrich contacts (find emails via Apollo)
        --segment SEGMENT       Enrich specific segment
        --limit N               Limit to N contacts

      credits                   Show Apollo API credits

    TEMPLATES:
      templates                 List available templates
      preview-template NAME     Preview a template

    CAMPAIGNS:
      create-campaign           Create new campaign
        --template NAME         Template to use (required)
        --segment SEGMENT       Target segment

      list-campaigns            List all campaigns
      preview --campaign ID     Preview campaign
      send --campaign ID        Send campaign
        --confirm               Required to actually send

      send-followups            Send scheduled follow-ups
        --confirm               Required to actually send

    REPORTING:
      stats                     Show overall statistics
      report --campaign ID      Show campaign report

    AI PERSONALIZATION:
      ai-status                 Check AI provider status
      personalize <id>          Generate personalized intro for contact
        --tone TONE             Tone: professional, casual, friendly
      personalize-batch         Batch personalize contacts
        --segment SEGMENT       Filter by segment
        --limit N               Limit to N contacts
        --confirm               Skip confirmation prompt
      generate-email <id>       Generate full personalized email
        --template TEMPLATE     Email type: cold-outreach, follow-up, demo-request
        --tone TONE             Tone: professional, casual, friendly
      generate-subjects <id>    Generate subject line variations

      Supported AI Providers:
        Cloud: deepseek, kimi, qwen, claude, gemini, openai, mistral, groq
        Local: ollama, lmstudio, localai, vllm

      Configuration (environment variables):
        AI_PROVIDER=deepseek    Provider name
        AI_API_KEY=sk-xxx       API key (not needed for local)
        AI_MODEL=model-name     Model override (optional)
        AI_BASE_URL=url         Custom API URL (optional)

    Examples:
      # Import contacts
      marketing import prospects.csv --segment "tech-companies"
      marketing import leads.csv --upsert --segment "conference-2024"
      marketing validate-csv myfile.csv

      # Export contacts
      marketing export contacts.csv --segment "enriched"
      marketing export --status "replied" --columns "company,email,status"

      # Full workflow
      marketing import prospects.csv --segment "q1-outreach"
      marketing enrich --segment "q1-outreach" --limit 50
      marketing create-campaign --template cold-email-1 --segment "q1-outreach"
      marketing preview --campaign 1
      marketing send --campaign 1 --confirm

      # AI Personalization (set AI_PROVIDER and AI_API_KEY first)
      marketing ai-status
      marketing personalize abc123 --tone friendly
      marketing personalize-batch --segment "q1-outreach" --limit 20
      marketing generate-email abc123 --template cold-outreach
      marketing generate-subjects abc123

    SENDGRID EMAIL:
      email-status              Check SendGrid configuration
      send-email <id>           Send email to single contact
        --template TEMPLATE     Template name (default: cold-email-1)
        --dry-run               Preview without sending
      send-email-batch          Send emails to multiple contacts
        --template TEMPLATE     Template name (default: cold-email-1)
        --segment SEGMENT       Filter by segment
        --limit N               Max emails to send (default: 10)
        --confirm               Required to actually send
        --dry-run               Simulate sending
      preview-send <id>         Preview email before sending
        --template TEMPLATE     Template name (default: cold-email-1)

      Configuration (environment variables):
        SENDGRID_API_KEY        Your SendGrid API key
        SENDGRID_FROM_EMAIL     Sender email address
        SENDGRID_FROM_NAME      Sender display name

    Examples:
      # Check SendGrid configuration
      marketing email-status

      # Preview an email
      marketing preview-send abc123 --template cold-email-1

      # Send to single contact
      marketing send-email abc123 --template cold-email-1

      # Dry run batch (preview without sending)
      marketing send-email-batch --segment "tech-companies" --limit 5 --dry-run

      # Send batch
      marketing send-email-batch --segment "tech-companies" --limit 10 --confirm
    """)
  end

  defp get_batch_contacts_preview(segment, limit) do
    Contacts.list_contacts()
    |> Enum.filter(fn c ->
      c.email != nil &&
        c.email != "" &&
        c.status in ["new", "enriched"] &&
        (segment == nil || c.segment == segment)
    end)
    |> Enum.take(limit)
  end

  defp print_contacts_table(contacts) do
    headers = ["ID", "Company", "Name", "Email", "Status", "Segment"]

    rows =
      Enum.map(contacts, fn c ->
        [
          String.slice(c.id, 0, 8),
          c.company || "-",
          Contacts.Contact.full_name(c) || "-",
          c.email || "-",
          c.status,
          c.segment || "-"
        ]
      end)

    TableRex.quick_render!(rows, headers)
    |> IO.puts()

    IO.puts("\nTotal: #{length(contacts)} contacts")
  end

  defp print_contact_details(contact) do
    IO.puts("""

    Contact Details
    ===============
    ID: #{contact.id}
    Company: #{contact.company}
    Name: #{Contacts.Contact.full_name(contact) || "-"}
    Email: #{contact.email || "-"}
    Title: #{contact.title || "-"}
    Status: #{contact.status}
    Segment: #{contact.segment || "-"}

    Engagement:
      Emails sent: #{contact.emails_sent}
      Emails opened: #{contact.emails_opened}
      Emails clicked: #{contact.emails_clicked}
      Last contacted: #{contact.last_contacted_at || "Never"}

    Enrichment:
      Enriched: #{if contact.enriched_at, do: "Yes (#{contact.enriched_at})", else: "No"}
      Industry: #{contact.industry || "-"}
      Company size: #{contact.company_size || "-"}
      Location: #{contact.location || "-"}
    """)
  end

  defp print_templates_table(templates) do
    headers = ["Name", "Subject", "Variables"]

    rows =
      Enum.map(templates, fn t ->
        [t.name, t.subject, Enum.join(t.variables, ", ")]
      end)

    TableRex.quick_render!(rows, headers)
    |> IO.puts()
  end

  defp print_campaigns_table(campaigns) do
    headers = ["ID", "Name", "Template", "Status", "Sent", "Opens", "Clicks"]

    rows =
      Enum.map(campaigns, fn c ->
        [
          String.slice(c.id, 0, 8),
          c.name,
          c.template_name,
          c.status,
          c.emails_sent,
          c.emails_opened,
          c.emails_clicked
        ]
      end)

    TableRex.quick_render!(rows, headers)
    |> IO.puts()
  end

  defp confirm? do
    IO.gets("") |> String.trim() |> String.downcase() == "y"
  end

  defp extract_first_name(nil), do: nil
  defp extract_first_name(name), do: name |> String.split() |> List.first()

  defp extract_last_name(nil), do: nil
  defp extract_last_name(name), do: name |> String.split() |> Enum.drop(1) |> Enum.join(" ")

  # ============================================================================
  # CSV Import/Export Helpers
  # ============================================================================

  defp import_contacts(file, opts) do
    IO.puts("Importing contacts from: #{file}\n")

    import_opts = build_import_opts(opts)
    dry_run = opts[:dry_run] || false

    if dry_run do
      IO.puts("🔍 DRY RUN MODE - No changes will be made\n")
    end

    # Progress callback
    progress_callback = fn %{current: current, total: total} ->
      if rem(current, 10) == 0 or current == total do
        percent = if total > 0, do: round(current / total * 100), else: 0
        IO.write("\r  Processing: #{current}/#{total} (#{percent}%)")
      end
    end

    import_opts = Keyword.put(import_opts, :on_progress, progress_callback)

    result = CsvHandler.import_contacts(file, import_opts)

    IO.puts("\n")
    print_import_result(result, dry_run: dry_run)
  end

  defp build_import_opts(opts) do
    import_opts = []

    # Segment
    import_opts = if opts[:segment] do
      Keyword.put(import_opts, :segment, opts[:segment])
    else
      import_opts
    end

    # Mode (upsert or insert)
    import_opts = cond do
      opts[:upsert] -> Keyword.put(import_opts, :mode, :upsert)
      opts[:mode] == "upsert" -> Keyword.put(import_opts, :mode, :upsert)
      true -> import_opts
    end

    # Dry run
    import_opts = if opts[:dry_run] do
      Keyword.put(import_opts, :dry_run, true)
    else
      import_opts
    end

    import_opts
  end

  defp print_import_result(result, opts) do
    dry_run = Keyword.get(opts, :dry_run, false)
    action = if dry_run, do: "Would import", else: "Imported"
    update_action = if dry_run, do: "Would update", else: "Updated"

    IO.puts("=== Import Results ===\n")
    IO.puts("  Total rows:    #{result.total}")
    IO.puts("  ✓ #{action}:   #{result.success}")

    if result.updated > 0 do
      IO.puts("  ✓ #{update_action}: #{result.updated}")
    end

    if result.skipped > 0 do
      IO.puts("  ⊘ Skipped:     #{result.skipped}")
    end

    if result.failed > 0 do
      IO.puts("  ✗ Failed:      #{result.failed}")
    end

    # Show errors (limit to first 10)
    if length(result.errors) > 0 do
      IO.puts("\n--- Errors ---")
      result.errors
      |> Enum.take(10)
      |> Enum.each(fn error ->
        company = get_in(error, [:data, :company]) || "Unknown"
        IO.puts("  Row #{error.row} (#{company}): #{error.error}")
      end)

      if length(result.errors) > 10 do
        IO.puts("  ... and #{length(result.errors) - 10} more errors")
      end
    end

    # Summary
    IO.puts("")
    if result.failed == 0 and result.success > 0 do
      if dry_run do
        IO.puts("✓ Validation passed! Run without --dry-run to import.")
      else
        IO.puts("✓ Import completed successfully!")
      end
    else
      if result.success > 0 do
        IO.puts("⚠ Import completed with #{result.failed} errors.")
      else
        IO.puts("✗ Import failed. Please check your CSV file.")
      end
    end
  end

  defp export_contacts(opts) do
    output_file = opts[:output]

    export_opts = []
    export_opts = if opts[:segment], do: Keyword.put(export_opts, :segment, opts[:segment]), else: export_opts
    export_opts = if opts[:status], do: Keyword.put(export_opts, :status, opts[:status]), else: export_opts
    export_opts = if opts[:limit], do: Keyword.put(export_opts, :limit, opts[:limit]), else: export_opts

    # Custom columns
    export_opts = if opts[:columns] do
      columns = opts[:columns]
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&String.to_atom/1)
      Keyword.put(export_opts, :columns, columns)
    else
      export_opts
    end

    contacts = Contacts.list_contacts(export_opts)

    if length(contacts) == 0 do
      IO.puts("No contacts found matching criteria.")
    else
      csv_content = CsvHandler.export(export_opts)

      if output_file do
        case File.write(output_file, csv_content) do
          :ok ->
            IO.puts("✓ Exported #{length(contacts)} contacts to: #{output_file}")
          {:error, reason} ->
            IO.puts("✗ Failed to write file: #{inspect(reason)}")
        end
      else
        # Print to stdout
        IO.puts(csv_content)
      end
    end
  end
end
