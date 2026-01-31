defmodule MarketingAgent.Email.SendGrid do
  @moduledoc """
  SendGrid email sending service.

  Handles:
  - Single email sending
  - Batch email sending with rate limiting
  - Email tracking updates
  - Unsubscribe management

  Configuration via environment variables:
  - SENDGRID_API_KEY: Your SendGrid API key
  - SENDGRID_FROM_EMAIL: Sender email address
  - SENDGRID_FROM_NAME: Sender name
  """

  alias MarketingAgent.{Contacts, Templates, Mailer}
  import Swoosh.Email

  @daily_limit Application.compile_env(:marketing_agent, [MarketingAgent.Config, :daily_send_limit]) || 100

  # ============================================================================
  # Configuration
  # ============================================================================

  @doc """
  Check if email sending is configured and ready.
  Returns true if SendGrid is configured OR if running in local test mode.
  """
  def configured? do
    test_mode?() || (api_key() != nil && api_key() != "" &&
      from_email() != nil && from_email() != "")
  end

  @doc """
  Check if running in local test mode (no real emails sent).
  """
  def test_mode? do
    mailer_config = Application.get_env(:marketing_agent, MarketingAgent.Mailer, [])
    mailer_config[:adapter] == Swoosh.Adapters.Local
  end

  @doc """
  Get current configuration status.
  """
  def status do
    %{
      configured: configured?(),
      test_mode: test_mode?(),
      from_email: from_email(),
      from_name: from_name(),
      daily_limit: @daily_limit,
      api_key_set: api_key() != nil && api_key() != ""
    }
  end

  # ============================================================================
  # Single Email Sending
  # ============================================================================

  @doc """
  Send an email to a single contact using a template.

  ## Options
  - `:dry_run` - If true, don't actually send (default: false)
  - `:track` - If true, update contact tracking (default: true)
  """
  def send_email(contact_id, template_name, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    track = Keyword.get(opts, :track, true)

    with {:ok, contact} <- get_sendable_contact(contact_id),
         {:ok, rendered} <- Templates.render(template_name, contact_to_map(contact)),
         {:ok, result} <- do_send(contact, rendered, dry_run) do
      if track && !dry_run do
        update_contact_sent(contact)
      end

      {:ok, Map.merge(result, %{contact_id: contact.id, contact_email: contact.email})}
    end
  end

  @doc """
  Send a custom email (not from template) to a contact.
  """
  def send_custom_email(contact_id, subject, html_body, text_body \\ nil, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, false)
    track = Keyword.get(opts, :track, true)

    with {:ok, contact} <- get_sendable_contact(contact_id) do
      rendered = %{
        subject: subject,
        html_body: html_body,
        text_body: text_body || strip_html(html_body)
      }

      case do_send(contact, rendered, dry_run) do
        {:ok, result} ->
          if track && !dry_run do
            update_contact_sent(contact)
          end
          {:ok, Map.merge(result, %{contact_id: contact.id, contact_email: contact.email})}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ============================================================================
  # Batch Email Sending
  # ============================================================================

  @doc """
  Send emails to multiple contacts using a template.

  ## Options
  - `:segment` - Filter by segment
  - `:status` - Filter by status (default: contacts that haven't been contacted)
  - `:limit` - Max emails to send (default: daily_limit)
  - `:dry_run` - If true, don't actually send
  - `:delay_ms` - Delay between emails in milliseconds (default: 100)
  - `:on_progress` - Callback function for progress updates
  """
  def send_batch(template_name, opts \\ []) do
    segment = Keyword.get(opts, :segment)
    status = Keyword.get(opts, :status, "new")
    limit = min(Keyword.get(opts, :limit, @daily_limit), @daily_limit)
    dry_run = Keyword.get(opts, :dry_run, false)
    delay_ms = Keyword.get(opts, :delay_ms, 100)
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)

    # Get sendable contacts
    contacts = get_batch_contacts(segment, status, limit)
    total = length(contacts)

    if total == 0 do
      {:ok, %{sent: 0, failed: 0, total: 0, errors: []}}
    else
      results =
        contacts
        |> Enum.with_index(1)
        |> Enum.map(fn {contact, index} ->
          result = send_email(contact.id, template_name, dry_run: dry_run)
          on_progress.(index, total)

          # Rate limiting
          unless dry_run, do: Process.sleep(delay_ms)

          {contact.id, result}
        end)

      summarize_batch_results(results, total)
    end
  end

  @doc """
  Send follow-up emails to contacts who haven't responded.

  Follows the configured follow-up schedule.
  """
  def send_followups(opts \\ []) do
    limit = Keyword.get(opts, :limit, @daily_limit)
    dry_run = Keyword.get(opts, :dry_run, false)
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)

    followup_schedule = Application.get_env(:marketing_agent, MarketingAgent.Config)[:followup_schedule] || [3, 7, 14]

    # Get contacts due for follow-up
    contacts = Contacts.list_contacts()
    |> Enum.filter(fn c ->
      c.status == "contacted" &&
        c.last_contacted_at != nil &&
        !replied?(c) &&
        due_for_followup?(c, followup_schedule)
    end)
    |> Enum.take(limit)

    total = length(contacts)

    if total == 0 do
      {:ok, %{sent: 0, failed: 0, total: 0, errors: []}}
    else
      results =
        contacts
        |> Enum.with_index(1)
        |> Enum.map(fn {contact, index} ->
          template = get_followup_template(contact.followup_count)
          result = send_email(contact.id, template, dry_run: dry_run)

          if match?({:ok, _}, result) && !dry_run do
            Contacts.update_contact(contact, %{
              followup_count: contact.followup_count + 1
            })
          end

          on_progress.(index, total)
          Process.sleep(100)

          {contact.id, result}
        end)

      summarize_batch_results(results, total)
    end
  end

  # ============================================================================
  # Email Preview
  # ============================================================================

  @doc """
  Preview an email without sending.
  """
  def preview_email(contact_id, template_name) do
    case Contacts.get_contact(contact_id) do
      nil ->
        {:error, :not_found}

      contact ->
        case Templates.render(template_name, contact_to_map(contact)) do
          {:ok, rendered} ->
            {:ok, %{
              to: contact.email,
              from: "#{from_name()} <#{from_email()}>",
              subject: rendered.subject,
              html_body: rendered.html_body,
              text_body: rendered.text_body
            }}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  # ============================================================================
  # Tracking Updates
  # ============================================================================

  @doc """
  Record that an email was opened.
  """
  def record_open(contact_id) do
    case Contacts.get_contact(contact_id) do
      nil -> {:error, :not_found}
      contact ->
        Contacts.update_contact(contact, %{
          emails_opened: (contact.emails_opened || 0) + 1,
          last_opened_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: if(contact.status == "contacted", do: "opened", else: contact.status)
        })
    end
  end

  @doc """
  Record that a link was clicked.
  """
  def record_click(contact_id) do
    case Contacts.get_contact(contact_id) do
      nil -> {:error, :not_found}
      contact ->
        Contacts.update_contact(contact, %{
          emails_clicked: (contact.emails_clicked || 0) + 1,
          last_clicked_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: if(contact.status in ["contacted", "opened"], do: "clicked", else: contact.status)
        })
    end
  end

  @doc """
  Record that the contact replied.
  """
  def record_reply(contact_id) do
    case Contacts.get_contact(contact_id) do
      nil -> {:error, :not_found}
      contact ->
        Contacts.update_contact(contact, %{
          last_replied_at: DateTime.utc_now() |> DateTime.truncate(:second),
          status: "replied"
        })
    end
  end

  @doc """
  Record that an email bounced.
  """
  def record_bounce(contact_id) do
    case Contacts.get_contact(contact_id) do
      nil -> {:error, :not_found}
      contact ->
        Contacts.update_contact(contact, %{status: "bounced"})
    end
  end

  @doc """
  Record that the contact unsubscribed.
  """
  def record_unsubscribe(contact_id) do
    case Contacts.get_contact(contact_id) do
      nil -> {:error, :not_found}
      contact ->
        Contacts.update_contact(contact, %{
          status: "unsubscribed",
          unsubscribed_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp api_key do
    System.get_env("SENDGRID_API_KEY")
  end

  defp from_email do
    System.get_env("SENDGRID_FROM_EMAIL") || "noreply@example.com"
  end

  defp from_name do
    System.get_env("SENDGRID_FROM_NAME") || "Marketing Team"
  end

  defp get_sendable_contact(contact_id) do
    case Contacts.get_contact(contact_id) do
      nil ->
        {:error, :not_found}

      contact ->
        cond do
          contact.email == nil || contact.email == "" ->
            {:error, :no_email}

          contact.status == "unsubscribed" ->
            {:error, :unsubscribed}

          contact.status == "bounced" ->
            {:error, :bounced}

          true ->
            {:ok, contact}
        end
    end
  end

  defp get_batch_contacts(segment, status, limit) do
    Contacts.list_contacts()
    |> Enum.filter(fn c ->
      has_email?(c) &&
        !unsubscribed?(c) &&
        !bounced?(c) &&
        (segment == nil || c.segment == segment) &&
        (status == nil || c.status == status)
    end)
    |> Enum.take(limit)
  end

  defp has_email?(contact), do: contact.email != nil && contact.email != ""
  defp unsubscribed?(contact), do: contact.status == "unsubscribed"
  defp bounced?(contact), do: contact.status == "bounced"
  defp replied?(contact), do: contact.last_replied_at != nil

  defp due_for_followup?(contact, schedule) do
    days_since_contact = days_since(contact.last_contacted_at)
    followup_count = contact.followup_count || 0

    case Enum.at(schedule, followup_count) do
      nil -> false  # No more follow-ups scheduled
      days -> days_since_contact >= days
    end
  end

  defp days_since(nil), do: 0
  defp days_since(datetime) do
    DateTime.diff(DateTime.utc_now(), datetime, :day)
  end

  defp get_followup_template(followup_count) do
    case followup_count do
      0 -> "follow-up-1"
      1 -> "follow-up-2"
      _ -> "breakup"
    end
  end

  defp contact_to_map(contact) do
    %{
      id: contact.id,
      email: contact.email,
      first_name: contact.first_name,
      last_name: contact.last_name,
      company: contact.company,
      title: contact.title,
      personalization: contact.personalization,
      industry: contact.industry,
      company_size: contact.company_size
    }
  end

  defp do_send(_contact, _rendered, true) do
    # Dry run - don't actually send
    {:ok, %{status: :dry_run, message_id: "dry-run-#{System.unique_integer([:positive])}"}}
  end

  defp do_send(contact, rendered, false) do
    unless configured?() do
      {:error, :not_configured}
    else
      email =
        new()
        |> to({contact.first_name || "", contact.email})
        |> from({from_name(), from_email()})
        |> subject(rendered.subject)
        |> html_body(wrap_html(rendered.html_body, contact))
        |> text_body(rendered.text_body)

      case Mailer.deliver(email) do
        {:ok, metadata} ->
          {:ok, %{status: :sent, message_id: extract_message_id(metadata)}}

        {:error, reason} ->
          {:error, {:send_failed, reason}}
      end
    end
  end

  defp wrap_html(body, contact) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
    </head>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
      #{body}

      <hr style="border: none; border-top: 1px solid #eee; margin: 30px 0;">

      <p style="font-size: 12px; color: #666;">
        You received this email because you're on our mailing list.
        <a href="{{unsubscribe_url}}" style="color: #666;">Unsubscribe</a>
      </p>
      <p style="font-size: 11px; color: #999;">
        Contact ID: #{contact.id}
      </p>
    </body>
    </html>
    """
  end

  defp extract_message_id(%{id: id}), do: id
  defp extract_message_id(_), do: "unknown"

  defp update_contact_sent(contact) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Contacts.update_contact(contact, %{
      emails_sent: (contact.emails_sent || 0) + 1,
      last_contacted_at: now,
      status: "contacted"
    })
  end

  defp summarize_batch_results(results, total) do
    {successes, failures} = Enum.split_with(results, fn {_, result} ->
      match?({:ok, _}, result)
    end)

    errors = failures
    |> Enum.map(fn {id, {:error, reason}} -> {id, reason} end)

    {:ok, %{
      sent: length(successes),
      failed: length(failures),
      total: total,
      errors: errors
    }}
  end

  defp strip_html(html) do
    html
    |> String.replace(~r/<[^>]+>/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end
end
