defmodule Farmbot.Ext do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    Farmbot.Config.update_config_value(:string, "authorization", "email", "connor@farmbot.io")
    Farmbot.Config.update_config_value(:string, "authorization", "password", "password1234")
    Farmbot.Config.update_config_value(:string, "authorization", "server", "https://my.farmbot.io")
    Farmbot.Config.update_config_value(:bool, "settings", "first_boot", true)
    # List all child processes to be supervised
    children = [
      {Farmbot.Bootstrap.Supervisor, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Farmbot.Ext.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
