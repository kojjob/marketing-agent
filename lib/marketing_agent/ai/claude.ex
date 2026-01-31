defmodule MarketingAgent.AI.Claude do
  @moduledoc """
  Anthropic Claude API client.

  Claude uses a different API format than OpenAI, so needs a dedicated client.

  Configuration via environment variables:
  - AI_PROVIDER: "claude" or "anthropic"
  - AI_API_KEY or ANTHROPIC_API_KEY: Your API key
  - AI_MODEL: Model to use (default: claude-3-haiku-20240307)

  Available models:
  - claude-3-5-sonnet-20241022 (most capable)
  - claude-3-opus-20240229 (highest quality)
  - claude-3-sonnet-20240229 (balanced)
  - claude-3-haiku-20240307 (fastest, cheapest)
  """

  @behaviour MarketingAgent.AI.Provider

  @default_model "claude-3-haiku-20240307"
  @api_version "2023-06-01"

  @impl true
  def name, do: "Claude"

  @impl true
  def available? do
    api_key() != nil && api_key() != ""
  end

  @impl true
  def chat(messages, opts \\ []) do
    unless available?() do
      {:error, :provider_not_configured}
    else
      do_chat(messages, opts)
    end
  end

  defp do_chat(messages, opts) do
    model = Keyword.get(opts, :model, model())
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1024)
    system_prompt = Keyword.get(opts, :system)

    # Claude API expects messages without system role in messages array
    # System prompt goes in a separate field
    {system, messages} = extract_system_message(messages, system_prompt)

    body = %{
      model: model,
      messages: format_messages(messages),
      max_tokens: max_tokens,
      temperature: temperature
    }

    # Add system prompt if present
    body = if system, do: Map.put(body, :system, system), else: body

    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", api_key()},
      {"anthropic-version", @api_version}
    ]

    url = "#{base_url()}/messages"

    case Req.post(url, json: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_response(response_body)

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_system_message(messages, explicit_system) do
    # Extract any system message from the messages list
    {system_msgs, other_msgs} = Enum.split_with(messages, fn
      %{role: "system"} -> true
      %{"role" => "system"} -> true
      _ -> false
    end)

    system_content = case {explicit_system, system_msgs} do
      {nil, []} -> nil
      {explicit, _} when is_binary(explicit) -> explicit
      {nil, [msg | _]} -> get_content(msg)
    end

    {system_content, other_msgs}
  end

  defp get_content(%{content: content}), do: content
  defp get_content(%{"content" => content}), do: content

  defp format_messages(messages) do
    Enum.map(messages, fn msg ->
      %{
        role: get_role(msg),
        content: get_content(msg)
      }
    end)
  end

  defp get_role(%{role: role}), do: role
  defp get_role(%{"role" => role}), do: role

  defp extract_response(%{"content" => [%{"text" => text} | _]}) do
    {:ok, String.trim(text)}
  end

  defp extract_response(%{"content" => [%{"type" => "text", "text" => text} | _]}) do
    {:ok, String.trim(text)}
  end

  defp extract_response(response) do
    {:error, {:unexpected_response, response}}
  end

  defp api_key do
    System.get_env("AI_API_KEY") || System.get_env("ANTHROPIC_API_KEY")
  end

  defp base_url do
    System.get_env("AI_BASE_URL") || "https://api.anthropic.com/v1"
  end

  defp model do
    System.get_env("AI_MODEL") || @default_model
  end
end
