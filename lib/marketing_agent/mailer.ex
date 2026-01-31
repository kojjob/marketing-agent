defmodule MarketingAgent.Mailer do
  @moduledoc """
  Swoosh mailer for sending emails via SendGrid.
  """
  use Swoosh.Mailer, otp_app: :marketing_agent
end
