defmodule MarketingAgent.Workflows.Followup do
  @moduledoc """
  Workflow for automated follow-up emails.
  """
  require Logger

  alias MarketingAgent.{Contacts, Campaigns, Templates}
  alias MarketingAgent.Services.SendGrid

  @followup_templates %{
    1 => "follow-up-1",
    2 => "follow-up-2",
    3 => "breakup"
  }

  @doc """
  Send follow-up emails to all contacts due for follow-up.

  Returns %{sent: count, failed: count, skipped: count}
  """
  def send_due_followups(opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 200)
    contacts = Contacts.contacts_for_followup()

    Logger.info("Processing #{length(contacts)} contacts for follow-up")

    results =
      contacts
      |> Enum.with_index()
      |> Enum.map(fn {contact, index} ->
        if index > 0, do: Process.sleep(delay_ms)
        process_followup(contact)
      end)

    sent = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))
    skipped = Enum.count(results, &match?({:skipped, _}, &1))

    %{
      sent: sent,
      failed: failed,
      skipped: skipped
    }
  end

  @doc """
  Process a single contact's follow-up.
  """
  def process_followup(contact) do
    followup_number = (contact.followup_count || 0) + 1

    # Determine which template to use
    template_name = Map.get(@followup_templates, followup_number)

    cond do
      # No more follow-ups configured
      is_nil(template_name) ->
        Logger.info("No more follow-ups for #{contact.email}")
        {:skipped, :max_followups_reached}

      # Contact has already replied
      contact.status == "replied" ->
        Logger.info("Skipping #{contact.email} - already replied")
        {:skipped, :already_replied}

      # Contact has opened but we should send different template
      contact.status == "opened" && followup_number == 1 ->
        # Skip first follow-up if they opened - send second instead
        send_followup_email(contact, "follow-up-2", 2)

      # Standard follow-up
      true ->
        send_followup_email(contact, template_name, followup_number)
    end
  end

  @doc """
  Send a specific follow-up email.
  """
  def send_followup_email(contact, template_name, followup_number) do
    Logger.info("Sending follow-up ##{followup_number} to #{contact.email}")

    case Templates.load_template(template_name) do
      {:ok, template} ->
        case Templates.render(template, contact) do
          {:ok, rendered} ->
            # Create email log for follow-up
            {:ok, email_log} =
              Campaigns.create_email_log(%{
                contact_id: contact.id,
                to_email: contact.email,
                subject: rendered.subject,
                template_name: template_name,
                status: "queued",
                is_followup: true,
                followup_number: followup_number
              })

            # Send the email
            case SendGrid.send_email(
                   contact.email,
                   rendered.subject,
                   rendered.html_body,
                   categories: ["followup", "followup-#{followup_number}"],
                   custom_args: %{
                     contact_id: contact.id,
                     email_log_id: email_log.id,
                     followup_number: followup_number
                   }
                 ) do
              {:ok, _} ->
                # Update email log
                Campaigns.record_email_event(email_log.id, :sent)

                # Update contact
                Contacts.record_email_sent(contact)
                schedule_next_followup(contact, followup_number)

                {:ok, %{contact_id: contact.id, followup: followup_number}}

              {:error, reason} ->
                Logger.error("Follow-up failed for #{contact.email}: #{inspect(reason)}")
                {:error, %{contact_id: contact.id, reason: reason}}
            end

          {:error, reason} ->
            {:error, %{contact_id: contact.id, reason: :template_render_failed, details: reason}}
        end

      {:error, :not_found} ->
        Logger.warning("Follow-up template not found: #{template_name}")
        {:skipped, :template_not_found}
    end
  end

  # ============================================================================
  # Manual Follow-up Functions
  # ============================================================================

  @doc """
  Schedule a custom follow-up for a contact.
  """
  def schedule_custom_followup(contact, days_from_now) do
    Contacts.schedule_followup(contact, days_from_now)
  end

  @doc """
  Cancel scheduled follow-up for a contact.
  """
  def cancel_followup(contact) do
    Contacts.update_contact(contact, %{next_followup_at: nil})
  end

  @doc """
  Get all contacts with pending follow-ups.
  """
  def pending_followups do
    Contacts.contacts_for_followup()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp schedule_next_followup(contact, current_followup_number) do
    followup_schedule =
      Application.get_env(:marketing_agent, MarketingAgent.Config)[:followup_schedule] || [3, 7, 14]

    next_interval = Enum.at(followup_schedule, current_followup_number)

    if next_interval do
      Contacts.schedule_followup(contact, next_interval)
    else
      # No more follow-ups, clear the schedule
      Contacts.update_contact(contact, %{next_followup_at: nil})
    end
  end
end
