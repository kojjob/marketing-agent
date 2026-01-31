defmodule MarketingAgent.Services.SendGrid do
  @moduledoc """
  SendGrid API integration for sending emails and tracking engagement.
  """
  require Logger

  @base_url "https://api.sendgrid.com/v3"

  # ============================================================================
  # Email Sending
  # ============================================================================

  @doc """
  Send a single email via SendGrid.

  ## Options
  - :track_opens - Enable open tracking (default: true)
  - :track_clicks - Enable click tracking (default: true)
  - :categories - List of categories for analytics
  - :custom_args - Custom arguments for webhooks
  """
  def send_email(to, subject, html_body, opts \\ []) do
    from_email = get_config(:from_email)
    from_name = get_config(:from_name)
    reply_to = get_config(:reply_to)

    personalizations = [
      %{
        to: [%{email: to}],
        subject: subject
      }
    ]

    body =
      %{
        personalizations: personalizations,
        from: %{email: from_email, name: from_name},
        content: [
          %{type: "text/html", value: add_unsubscribe_footer(html_body)}
        ],
        tracking_settings: %{
          click_tracking: %{enable: Keyword.get(opts, :track_clicks, true)},
          open_tracking: %{enable: Keyword.get(opts, :track_opens, true)}
        }
      }
      |> maybe_add_reply_to(reply_to)
      |> maybe_add_categories(Keyword.get(opts, :categories))
      |> maybe_add_custom_args(Keyword.get(opts, :custom_args))

    case post("/mail/send", body) do
      {:ok, %{status: status, headers: headers}} when status in [200, 201, 202] ->
        message_id = get_message_id(headers)
        {:ok, %{message_id: message_id, status: status}}

      {:ok, %{status: status, body: body}} ->
        Logger.error("SendGrid error: #{status} - #{inspect(body)}")
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        Logger.error("SendGrid request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Send a batch of emails (up to 1000 recipients per API call).
  """
  def send_batch(recipients, subject, html_body, _opts \\ []) when is_list(recipients) do
    from_email = get_config(:from_email)
    from_name = get_config(:from_name)

    personalizations =
      Enum.map(recipients, fn recipient ->
        %{
          to: [%{email: recipient.email}],
          subject: render_subject(subject, recipient),
          dynamic_template_data: Map.take(recipient, [:first_name, :last_name, :company, :personalization])
        }
      end)

    body = %{
      personalizations: personalizations,
      from: %{email: from_email, name: from_name},
      content: [
        %{type: "text/html", value: add_unsubscribe_footer(html_body)}
      ],
      tracking_settings: %{
        click_tracking: %{enable: true},
        open_tracking: %{enable: true}
      }
    }

    case post("/mail/send", body) do
      {:ok, %{status: status}} when status in [200, 201, 202] ->
        {:ok, %{sent: length(recipients)}}

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, message: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ============================================================================
  # Webhook Event Processing
  # ============================================================================

  @doc """
  Process SendGrid webhook events.

  Expected event types:
  - processed, dropped, delivered, deferred, bounce, open, click, unsubscribe, spamreport
  """
  def process_webhook_event(%{"event" => event_type, "sg_message_id" => message_id} = event) do
    case event_type do
      "delivered" -> {:delivered, message_id, %{}}
      "open" -> {:opened, message_id, %{}}
      "click" -> {:clicked, message_id, %{link: event["url"]}}
      "bounce" -> {:bounced, message_id, %{bounce_type: event["type"], reason: event["reason"]}}
      "dropped" -> {:dropped, message_id, %{reason: event["reason"]}}
      "unsubscribe" -> {:unsubscribed, message_id, %{}}
      "spamreport" -> {:spam_reported, message_id, %{}}
      _ -> {:unknown, message_id, event}
    end
  end

  def process_webhook_event(_), do: {:error, :invalid_event}

  # ============================================================================
  # Account Stats
  # ============================================================================

  @doc """
  Get SendGrid account statistics.
  """
  def get_stats(start_date, end_date \\ nil) do
    end_date = end_date || Date.utc_today()
    query = "?start_date=#{start_date}&end_date=#{end_date}"

    case get("/stats#{query}") do
      {:ok, %{status: 200, body: body}} -> {:ok, body}
      {:ok, %{status: status, body: body}} -> {:error, %{status: status, message: body}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp post(path, body) do
    url = @base_url <> path
    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, json: body, headers: headers) do
      {:ok, response} ->
        {:ok, %{
          status: response.status,
          headers: response.headers,
          body: response.body
        }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get(path) do
    url = @base_url <> path
    headers = [
      {"Authorization", "Bearer #{api_key()}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers) do
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
      raise "SendGrid API key not configured. Set SENDGRID_API_KEY environment variable."
  end

  defp get_config(key) do
    Application.get_env(:marketing_agent, MarketingAgent.Config)[key]
  end

  defp get_message_id(headers) do
    headers
    |> Enum.find(fn {key, _} -> String.downcase(key) == "x-message-id" end)
    |> case do
      {_, value} -> value
      nil -> nil
    end
  end

  defp add_unsubscribe_footer(html) do
    unsubscribe_url = get_config(:unsubscribe_url)
    company_address = get_config(:company_address)

    footer = """
    <br><br>
    <hr style="border: none; border-top: 1px solid #e0e0e0; margin: 20px 0;">
    <p style="font-size: 12px; color: #666;">
      #{company_address}<br>
      <a href="#{unsubscribe_url}" style="color: #666;">Unsubscribe</a>
    </p>
    """

    html <> footer
  end

  defp maybe_add_reply_to(body, nil), do: body
  defp maybe_add_reply_to(body, reply_to) do
    Map.put(body, :reply_to, %{email: reply_to})
  end

  defp maybe_add_categories(body, nil), do: body
  defp maybe_add_categories(body, categories) when is_list(categories) do
    Map.put(body, :categories, categories)
  end

  defp maybe_add_custom_args(body, nil), do: body
  defp maybe_add_custom_args(body, args) when is_map(args) do
    updated_personalizations =
      Enum.map(body.personalizations, fn p ->
        Map.put(p, :custom_args, args)
      end)

    Map.put(body, :personalizations, updated_personalizations)
  end

  defp render_subject(subject, recipient) do
    subject
    |> String.replace("{{first_name}}", recipient[:first_name] || "")
    |> String.replace("{{last_name}}", recipient[:last_name] || "")
    |> String.replace("{{company}}", recipient[:company] || "")
    |> String.trim()
  end
end
