defmodule MarketingAgent.Campaigns do
  @moduledoc """
  Context module for managing email campaigns.
  """
  import Ecto.Query
  alias MarketingAgent.Repo
  alias MarketingAgent.Campaigns.{Campaign, EmailLog}

  # ============================================================================
  # Campaign CRUD
  # ============================================================================

  def list_campaigns(opts \\ []) do
    Campaign
    |> apply_filters(opts)
    |> order_by([c], desc: c.inserted_at)
    |> Repo.all()
  end

  def get_campaign(id), do: Repo.get(Campaign, id)

  def get_campaign!(id), do: Repo.get!(Campaign, id)

  def create_campaign(attrs) do
    %Campaign{}
    |> Campaign.changeset(attrs)
    |> Repo.insert()
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign
    |> Campaign.changeset(attrs)
    |> Repo.update()
  end

  def delete_campaign(%Campaign{} = campaign) do
    Repo.delete(campaign)
  end

  def approve_campaign(%Campaign{status: "draft"} = campaign) do
    update_campaign(campaign, %{status: "approved"})
  end

  def approve_campaign(%Campaign{}), do: {:error, :invalid_status}

  def start_campaign(%Campaign{status: "approved"} = campaign, total_recipients) do
    update_campaign(campaign, %{
      status: "sending",
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      total_recipients: total_recipients
    })
  end

  def start_campaign(%Campaign{}), do: {:error, :invalid_status}

  def complete_campaign(%Campaign{} = campaign) do
    update_campaign(campaign, %{
      status: "sent",
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end

  def pause_campaign(%Campaign{status: "sending"} = campaign) do
    update_campaign(campaign, %{status: "paused"})
  end

  def pause_campaign(%Campaign{}), do: {:error, :invalid_status}

  # ============================================================================
  # Email Log Operations
  # ============================================================================

  def create_email_log(attrs) do
    %EmailLog{}
    |> EmailLog.changeset(attrs)
    |> Repo.insert()
  end

  def get_email_log(id), do: Repo.get(EmailLog, id)

  def get_email_log_by_message_id(message_id) do
    Repo.get_by(EmailLog, sendgrid_message_id: message_id)
  end

  def list_email_logs_for_campaign(campaign_id) do
    EmailLog
    |> where([e], e.campaign_id == ^campaign_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def list_email_logs_for_contact(contact_id) do
    EmailLog
    |> where([e], e.contact_id == ^contact_id)
    |> order_by([e], desc: e.inserted_at)
    |> Repo.all()
  end

  def record_email_event(email_log_id, event_type, attrs \\ %{}) do
    case Repo.get(EmailLog, email_log_id) do
      nil -> {:error, :not_found}
      email_log ->
        email_log
        |> EmailLog.event_changeset(event_type, attrs)
        |> Repo.update()
    end
  end

  # ============================================================================
  # Campaign Metrics
  # ============================================================================

  def update_campaign_metrics(%Campaign{} = campaign) do
    metrics =
      EmailLog
      |> where([e], e.campaign_id == ^campaign.id)
      |> select([e], %{
        sent: count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", e.sent_at)),
        delivered: count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", e.delivered_at)),
        opened: count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", e.opened_at)),
        clicked: count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", e.clicked_at)),
        bounced: count(fragment("CASE WHEN ? IS NOT NULL THEN 1 END", e.bounced_at))
      })
      |> Repo.one()

    update_campaign(campaign, %{
      emails_sent: metrics.sent,
      emails_delivered: metrics.delivered,
      emails_opened: metrics.opened,
      emails_clicked: metrics.clicked,
      emails_bounced: metrics.bounced
    })
  end

  def campaign_stats(campaign_id) do
    campaign = get_campaign!(campaign_id)

    %{
      campaign: campaign,
      open_rate: Campaign.open_rate(campaign),
      click_rate: Campaign.click_rate(campaign),
      bounce_rate: Campaign.bounce_rate(campaign),
      reply_rate: Campaign.reply_rate(campaign)
    }
  end

  def overall_stats do
    campaigns = list_campaigns()

    total_sent = Enum.sum(Enum.map(campaigns, & &1.emails_sent))
    total_opened = Enum.sum(Enum.map(campaigns, & &1.emails_opened))
    total_clicked = Enum.sum(Enum.map(campaigns, & &1.emails_clicked))
    total_bounced = Enum.sum(Enum.map(campaigns, & &1.emails_bounced))
    total_replies = Enum.sum(Enum.map(campaigns, & &1.replies_received))

    %{
      total_campaigns: length(campaigns),
      total_sent: total_sent,
      total_opened: total_opened,
      total_clicked: total_clicked,
      total_bounced: total_bounced,
      total_replies: total_replies,
      avg_open_rate: if(total_sent > 0, do: total_opened / total_sent * 100, else: 0.0),
      avg_click_rate: if(total_sent > 0, do: total_clicked / total_sent * 100, else: 0.0),
      avg_bounce_rate: if(total_sent > 0, do: total_bounced / total_sent * 100, else: 0.0),
      avg_reply_rate: if(total_sent > 0, do: total_replies / total_sent * 100, else: 0.0)
    }
  end

  def today_send_count do
    today = Date.utc_today()
    start_of_day = DateTime.new!(today, ~T[00:00:00], "Etc/UTC")

    EmailLog
    |> where([e], e.sent_at >= ^start_of_day)
    |> select([e], count(e.id))
    |> Repo.one()
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp apply_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, q -> where(q, [c], c.status == ^status)
      {:segment, segment}, q -> where(q, [c], c.segment == ^segment)
      {:limit, limit}, q -> limit(q, ^limit)
      _, q -> q
    end)
  end
end
