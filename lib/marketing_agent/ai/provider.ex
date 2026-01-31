defmodule MarketingAgent.AI.Provider do
  @moduledoc """
  Behaviour for AI providers.

  Supports multiple providers with a unified interface:

  ## Western Providers
  - Claude (Anthropic)
  - OpenAI (GPT-4, GPT-3.5)
  - Gemini (Google)
  - Mistral

  ## Asian Providers
  - DeepSeek
  - Kimi (Moonshot AI)
  - Qwen (Alibaba)
  - Baichuan
  - GLM (Zhipu AI)

  ## Local/Self-hosted
  - Ollama
  - LM Studio
  - vLLM
  - LocalAI

  Most providers use OpenAI-compatible APIs, making integration straightforward.
  """

  @type message :: %{role: String.t(), content: String.t()}
  @type completion_opts :: [
    model: String.t(),
    temperature: float(),
    max_tokens: integer(),
    system: String.t()
  ]

  @doc """
  Generate a chat completion.
  """
  @callback chat(messages :: [message()], opts :: completion_opts()) ::
    {:ok, String.t()} | {:error, term()}

  @doc """
  Check if the provider is configured and available.
  """
  @callback available?() :: boolean()

  @doc """
  Get the provider name.
  """
  @callback name() :: String.t()

  @doc """
  Get the current provider module based on configuration.
  """
  def current do
    provider = get_provider_name()
    get_provider_module(provider)
  end

  @doc """
  Generate a completion using the configured provider.
  """
  def chat(messages, opts \\ []) do
    case current() do
      nil -> {:error, :no_provider_configured}
      provider -> provider.chat(messages, opts)
    end
  end

  @doc """
  Check if any AI provider is available.
  """
  def available? do
    case current() do
      nil -> false
      provider -> provider.available?()
    end
  end

  @doc """
  List all supported providers.
  """
  def supported_providers do
    %{
      # OpenAI-compatible providers
      "openai" => MarketingAgent.AI.OpenAICompatible,
      "deepseek" => MarketingAgent.AI.OpenAICompatible,
      "kimi" => MarketingAgent.AI.OpenAICompatible,
      "moonshot" => MarketingAgent.AI.OpenAICompatible,
      "qwen" => MarketingAgent.AI.OpenAICompatible,
      "mistral" => MarketingAgent.AI.OpenAICompatible,
      "groq" => MarketingAgent.AI.OpenAICompatible,
      "together" => MarketingAgent.AI.OpenAICompatible,
      "ollama" => MarketingAgent.AI.OpenAICompatible,
      "lmstudio" => MarketingAgent.AI.OpenAICompatible,
      "localai" => MarketingAgent.AI.OpenAICompatible,
      "vllm" => MarketingAgent.AI.OpenAICompatible,
      "baichuan" => MarketingAgent.AI.OpenAICompatible,
      "glm" => MarketingAgent.AI.OpenAICompatible,
      "zhipu" => MarketingAgent.AI.OpenAICompatible,

      # Native API providers
      "claude" => MarketingAgent.AI.Claude,
      "anthropic" => MarketingAgent.AI.Claude,
      "gemini" => MarketingAgent.AI.Gemini,
      "google" => MarketingAgent.AI.Gemini
    }
  end

  @doc """
  Get provider configuration with defaults.
  """
  def provider_config(provider_name) do
    defaults = %{
      "openai" => %{
        base_url: "https://api.openai.com/v1",
        default_model: "gpt-4o-mini",
        env_key: "OPENAI_API_KEY"
      },
      "deepseek" => %{
        base_url: "https://api.deepseek.com/v1",
        default_model: "deepseek-chat",
        env_key: "DEEPSEEK_API_KEY"
      },
      "kimi" => %{
        base_url: "https://api.moonshot.cn/v1",
        default_model: "moonshot-v1-8k",
        env_key: "KIMI_API_KEY"
      },
      "moonshot" => %{
        base_url: "https://api.moonshot.cn/v1",
        default_model: "moonshot-v1-8k",
        env_key: "MOONSHOT_API_KEY"
      },
      "qwen" => %{
        base_url: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        default_model: "qwen-turbo",
        env_key: "QWEN_API_KEY"
      },
      "mistral" => %{
        base_url: "https://api.mistral.ai/v1",
        default_model: "mistral-small-latest",
        env_key: "MISTRAL_API_KEY"
      },
      "groq" => %{
        base_url: "https://api.groq.com/openai/v1",
        default_model: "llama-3.1-70b-versatile",
        env_key: "GROQ_API_KEY"
      },
      "together" => %{
        base_url: "https://api.together.xyz/v1",
        default_model: "meta-llama/Llama-3-70b-chat-hf",
        env_key: "TOGETHER_API_KEY"
      },
      "ollama" => %{
        base_url: "http://localhost:11434/v1",
        default_model: "llama3.2",
        env_key: nil  # No API key needed for local
      },
      "lmstudio" => %{
        base_url: "http://localhost:1234/v1",
        default_model: "local-model",
        env_key: nil
      },
      "localai" => %{
        base_url: "http://localhost:8080/v1",
        default_model: "gpt-3.5-turbo",
        env_key: nil
      },
      "vllm" => %{
        base_url: "http://localhost:8000/v1",
        default_model: "default",
        env_key: nil
      },
      "baichuan" => %{
        base_url: "https://api.baichuan-ai.com/v1",
        default_model: "Baichuan2-Turbo",
        env_key: "BAICHUAN_API_KEY"
      },
      "glm" => %{
        base_url: "https://open.bigmodel.cn/api/paas/v4",
        default_model: "glm-4",
        env_key: "GLM_API_KEY"
      },
      "zhipu" => %{
        base_url: "https://open.bigmodel.cn/api/paas/v4",
        default_model: "glm-4",
        env_key: "ZHIPU_API_KEY"
      },
      "claude" => %{
        base_url: "https://api.anthropic.com/v1",
        default_model: "claude-3-haiku-20240307",
        env_key: "ANTHROPIC_API_KEY"
      },
      "anthropic" => %{
        base_url: "https://api.anthropic.com/v1",
        default_model: "claude-3-haiku-20240307",
        env_key: "ANTHROPIC_API_KEY"
      },
      "gemini" => %{
        base_url: "https://generativelanguage.googleapis.com/v1beta",
        default_model: "gemini-1.5-flash",
        env_key: "GEMINI_API_KEY"
      },
      "google" => %{
        base_url: "https://generativelanguage.googleapis.com/v1beta",
        default_model: "gemini-1.5-flash",
        env_key: "GOOGLE_API_KEY"
      }
    }

    Map.get(defaults, String.downcase(provider_name), %{})
  end

  # Private functions

  defp get_provider_name do
    System.get_env("AI_PROVIDER") ||
      Application.get_env(:marketing_agent, :ai_provider)
  end

  defp get_provider_module(nil), do: nil
  defp get_provider_module(provider_name) do
    provider_name
    |> String.downcase()
    |> then(&Map.get(supported_providers(), &1))
  end
end
