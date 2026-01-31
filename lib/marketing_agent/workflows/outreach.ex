defmodule MarketingAgent.Workflows.Outreach do
  @moduledoc """
  Workflow for sending email campaigns.
  """
  require Logger

  alias MarketingAgent.{Contacts, Campaigns, Templates}
  alias MarketingAgent.Services.SendGrid

  @doc """
  Send a campaign to a list of contacts.

  Returns %{sent: count, failed: count, errors: []}
  """
  def send_campaign(campaign, contacts, opts \\ []) do
    delay_ms = Keyword.get(opts, :delay_ms, 200)

    # Start the campaign
    {:ok, campaign} = Campaigns.start_campaign(campaign, length(contacts))

    # Load template
    template = Templates.load_template!(campaign.template_name)

    results =
      contacts
      |> Enum.with_index()
      |> Enum.map(fn {contact, index} ->
        # Rate limiting
        if index > 0, do: Process.sleep(delay_ms)

        send_to_contact(campaign, template, contact)
      end)

    sent = Enum.count(results, &match?({:ok, _}, &1))
    failed = Enum.count(results, &match?({:error, _}, &1))

    # Complete the campaign
    Campaigns.complete_campaign(campaign)
    Campaigns.update_campaign_metrics(campaign)

    %{
      sent: sent,
      failed: failed,
      errors: Enum.filter(results, &match?({:error, _}, &1))
    }
  end

  @doc """
  Send a single email to a contact.
  """
  def send_to_contact(campaign, template, contact) do
    Logger.info("Sending email to #{contact.email} (#{contact.company})")

    # Render the template
    case Templates.render(template, contact) do
      {:ok, rendered} ->
        # Create email log
        {:ok, email_log} =
          Campaigns.create_email_log(%{
            contact_id: contact.id,
            campaign_id: campaign.id,
            to_email: contact.email,
            subject: rendered.subject,
            template_name: campaign.template_name,
            status: "queued"
          })

        # Send via SendGrid
        case SendGrid.send_email(
               contact.email,
               rendered.subject,
               rendered.html_body,
               categories: [campaign.template_name],
               custom_args: %{
                 contact_id: contact.id,
                 campaign_id: campaign.id,
                 email_log_id: email_log.id
               }
             ) do
          {:ok, %{message_id: message_id}} ->
            # Update email log with message ID
            Campaigns.record_email_event(email_log.id, :sent, %{})

            # Update contact engagement
            Contacts.record_email_sent(contact)

            # Schedule first follow-up
            schedule_next_followup(contact)

            {:ok, %{contact_id: contact.id, message_id: message_id}}

          {:error, reason} ->
            Logger.error("Failed to send to #{contact.email}: #{inspect(reason)}")
            {:error, %{contact_id: contact.id, reason: reason}}
        end

      {:error, reason} ->
        Logger.error("Failed to render template for #{contact.email}: #{inspect(reason)}")
        {:error, %{contact_id: contact.id, reason: :template_render_failed}}
    end
  end

  @doc """
  Send a single email outside of a campaign (ad-hoc).
  """
  def send_single(contact, template_name, opts \\ []) do
    template = Templates.load_template!(template_name)

    case Templates.render(template, contact) do
      {:ok, rendered} ->
        SendGrid.send_email(
          contact.email,
          rendered.subject,
          rendered.html_body,
          opts
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp schedule_next_followup(contact) do
    followup_schedule =
      Application.get_env(:marketing_agent, MarketingAgent.Config)[:followup_schedule] || [3, 7, 14]

    next_followup_days = Enum.at(followup_schedule, contact.followup_count, nil)

    if next_followup_days do
      Contacts.schedule_followup(contact, next_followup_days)
    end
  end
end
