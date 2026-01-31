defmodule MarketingAgentWeb.Router do
  use MarketingAgentWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", MarketingAgentWeb do
    pipe_through :api
  end
end
