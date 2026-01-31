defmodule MarketingAgent.AI.Gemini do
  @moduledoc """
  Google Gemini API client.

  Gemini uses a different API format than OpenAI, so needs a dedicated client.

  Configuration via environment variables:
  - AI_PROVIDER: "gemini" or "google"
  - AI_API_KEY or GEMINI_API_KEY or GOOGLE_API_KEY: Your API key
  - AI_MODEL: Model to use (default: gemini-1.5-flash)

  Available models:
  - gemini-1.5-pro (most capable)
  - gemini-1.5-flash (fast, efficient)
  - gemini-1.0-pro (legacy)
  """

  @behaviour MarketingAgent.AI.Provider

  @default_model "gemini-2.0-flash"

  @impl true
  def name, do: "Gemini"

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

    # Convert messages to Gemini format
    {system_instruction, contents} = prepare_contents(messages, system_prompt)

    # For Gemini 2.5 models with thinking, we need more output tokens
    # since thinking consumes tokens from the budget
    adjusted_max_tokens = if String.contains?(model, "2.5") do
      max(max_tokens * 3, 2048)
    else
      max_tokens
    end

    body = %{
      contents: contents,
      generationConfig: %{
        temperature: temperature,
        maxOutputTokens: adjusted_max_tokens
      }
    }

    # Add system instruction if present
    body = if system_instruction do
      Map.put(body, :systemInstruction, %{parts: [%{text: system_instruction}]})
    else
      body
    end

    url = "#{base_url()}/models/#{model}:generateContent?key=#{api_key()}"

    case Req.post(url, json: body, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_response(response_body)

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp prepare_contents(messages, explicit_system) do
    # Separate system messages from conversation
    {system_msgs, other_msgs} = Enum.split_with(messages, fn
      %{role: "system"} -> true
      %{"role" => "system"} -> true
      _ -> false
    end)

    system_instruction = case {explicit_system, system_msgs} do
      {nil, []} -> nil
      {explicit, _} when is_binary(explicit) -> explicit
      {nil, [msg | _]} -> get_content(msg)
    end

    # Convert to Gemini format (user/model roles, parts structure)
    contents = Enum.map(other_msgs, fn msg ->
      role = case get_role(msg) do
        "assistant" -> "model"
        r -> r
      end

      %{
        role: role,
        parts: [%{text: get_content(msg)}]
      }
    end)

    {system_instruction, contents}
  end

  defp get_content(%{content: content}), do: content
  defp get_content(%{"content" => content}), do: content

  defp get_role(%{role: role}), do: role
  defp get_role(%{"role" => role}), do: role

  defp extract_response(%{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]}) do
    {:ok, String.trim(text)}
  end

  defp extract_response(response) do
    {:error, {:unexpected_response, response}}
  end

  defp api_key do
    System.get_env("AI_API_KEY") ||
      System.get_env("GEMINI_API_KEY") ||
      System.get_env("GOOGLE_API_KEY")
  end

  defp base_url do
    System.get_env("AI_BASE_URL") || "https://generativelanguage.googleapis.com/v1beta"
  end

  defp model do
    System.get_env("AI_MODEL") || @default_model
  end
end
