defmodule Farmbot.AMQP.BotStateTransport do
  use GenServer
  use AMQP
  require Farmbot.Logger
  import Farmbot.Config, only: [get_config_value: 3, update_config_value: 4]

  @exchange "amq.topic"

  defstruct [:conn, :chan, :bot, :state_cache]
  alias __MODULE__, as: State

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [name: __MODULE__])
  end

  def init([]) do
    token = get_config_value(:string, "authorization", "token")
    %{bot: device, mqtt: mqtt_host, vhost: vhost} = Farmbot.Jwt.decode!(token)
    {:ok, conn}  = open_connection(token, device, mqtt_host, vhost)
    {:ok, chan}  = AMQP.Channel.open(conn)
    :ok          = Basic.qos(chan, [global: true])
    Farmbot.Registry.subscribe()
    {:ok, struct(State, [conn: conn, chan: chan, bot: device])}
  end

  def terminate(reason, state) do
    ok_reasons = [:normal, :shutdown, :token_refresh]
    update_config_value(:bool, "settings", "ignore_fbos_config", false)

    if reason not in ok_reasons do
      Farmbot.Logger.error 1, "BotState amqp client Died: #{inspect reason}"
      update_config_value(:bool, "settings", "log_amqp_connected", true)
    end

    # If a channel was still open, close it.
    if state.chan, do: AMQP.Channel.close(state.chan)

    # If the connection is still open, close it.
    if state.conn, do: AMQP.Connection.close(state.conn)
  end

  def handle_info({Farmbot.Registry, {Farmbot.BotState, bot_state}}, %{state_cache: bot_state} = state) do
    {:noreply, state}
  end

  def handle_info({Farmbot.Registry, {Farmbot.BotState, bot_state}}, state) do
    cache = push_bot_state(state.chan, state.bot, bot_state)
    {:noreply, %{state | state_cache: cache}}
  end

  def handle_info({Farmbot.Registry, _}, state), do: {:noreply, state}

  defp open_connection(token, device, mqtt_server, vhost) do
    opts = [
      host: mqtt_server,
      username: device,
      password: token,
      virtual_host: vhost]
    AMQP.Connection.open(opts)
  end

  defp push_bot_state(chan, bot, state) do
    json = Farmbot.JSON.encode!(state)
    :ok = AMQP.Basic.publish chan, @exchange, "bot.#{bot}.status", json
    # IO.inspect(json, label: "BOT STATE PUSH")
    state
  end
end
