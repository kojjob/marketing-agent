defmodule MarketingAgent.AI.OpenAICompatible do
  @moduledoc """
  OpenAI-compatible API client.

  Works with providers that implement the OpenAI API spec:
  - OpenAI
  - DeepSeek
  - Kimi (Moonshot)
  - Qwen (Alibaba)
  - Mistral
  - Groq
  - Together AI
  - Ollama
  - LM Studio
  - LocalAI
  - vLLM
  - Baichuan
  - GLM (Zhipu)

  Configuration via environment variables:
  - AI_PROVIDER: Provider name (e.g., "deepseek", "kimi", "ollama")
  - AI_API_KEY: API key (not needed for local providers)
  - AI_MODEL: Model to use (optional, uses provider default)
  - AI_BASE_URL: Custom base URL (optional, uses provider default)
  """

  @behaviour MarketingAgent.AI.Provider

  alias MarketingAgent.AI.Provider

  @impl true
  def name do
    provider = System.get_env("AI_PROVIDER") || "openai"
    String.capitalize(provider)
  end

  @impl true
  def available? do
    config = get_config()

    # For local providers, just check if base_url is set
    # For cloud providers, check if API key is set
    cond do
      config.provider in ["ollama", "lmstudio", "localai", "vllm"] ->
        config.base_url != nil

      true ->
        config.api_key != nil && config.api_key != ""
    end
  end

  @impl true
  def chat(messages, opts \\ []) do
    config = get_config()

    unless available?() do
      {:error, :provider_not_configured}
    else
      do_chat(messages, opts, config)
    end
  end

  defp do_chat(messages, opts, config) do
    model = Keyword.get(opts, :model, config.model)
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 1024)
    system_prompt = Keyword.get(opts, :system)

    # Build messages with optional system prompt
    messages = if system_prompt do
      [%{role: "system", content: system_prompt} | messages]
    else
      messages
    end

    body = %{
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }

    headers = build_headers(config)
    url = "#{config.base_url}/chat/completions"

    case Req.post(url, json: body, headers: headers, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: response_body}} ->
        extract_response(response_body)

      {:ok, %{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_config do
    provider = String.downcase(System.get_env("AI_PROVIDER") || "openai")
    provider_defaults = Provider.provider_config(provider)

    %{
      provider: provider,
      api_key: get_api_key(provider, provider_defaults),
      base_url: System.get_env("AI_BASE_URL") || Map.get(provider_defaults, :base_url),
      model: System.get_env("AI_MODEL") || Map.get(provider_defaults, :default_model)
    }
  end

  defp get_api_key(_provider, provider_defaults) do
    # Check for generic AI_API_KEY first, then provider-specific
    System.get_env("AI_API_KEY") ||
      (provider_defaults[:env_key] && System.get_env(provider_defaults[:env_key]))
  end

  defp build_headers(config) do
    base_headers = [
      {"Content-Type", "application/json"}
    ]

    if config.api_key do
      [{"Authorization", "Bearer #{config.api_key}"} | base_headers]
    else
      base_headers
    end
  end

  defp extract_response(%{"choices" => [%{"message" => %{"content" => content}} | _]}) do
    {:ok, String.trim(content)}
  end

  defp extract_response(%{"choices" => [%{"text" => content} | _]}) do
    # Some providers return text instead of message
    {:ok, String.trim(content)}
  end

  defp extract_response(response) do
    {:error, {:unexpected_response, response}}
  end
end
