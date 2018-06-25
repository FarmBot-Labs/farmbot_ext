defmodule Farmbot.AMQP.LogTransport do
  use GenServer
  use AMQP
  import Farmbot.Config, only: [get_config_value: 3]

  @exchange "amq.topic"
  @log_fetch_amnt 10

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
    worker_fun   = spawn(__MODULE__, :log_worker, [self()])
    Process.link(worker_fun)
    {:ok, struct(State, [conn: conn, chan: chan, bot: device])}
  end

  def handle_info({:log, log}, state) do
    if Farmbot.Logger.should_log?(log.module, log.verbosity) do
      fb = %{position: %{x: -1, y: -1, z: -1}}
      location_data = Map.get(state.state_cache || %{}, :location_data, fb)
      log_without_pos = %{
        type: log.level,
        x: nil, y: nil, z: nil,
        verbosity: log.verbosity,
        major_version: log.version.major,
        minor_version: log.version.minor,
        patch_version: log.version.patch,
        created_at: NaiveDateTime.to_iso8601(log.inserted_at),
        channels: log.meta[:channels] || [],
        message: log.message
      }
      log = add_position_to_log(log_without_pos, location_data)
      push_bot_log(state.chan, state.bot, log)
    end
    {:noreply, state}
  end

  def handle_info({Farmbot.Registry, {Farmbot.BotState, bot_state}}, state) do
    {:noreply, %{state | state_cache: bot_state}}
  end

  defp open_connection(token, device, mqtt_server, vhost) do
    opts = [
      host: mqtt_server,
      username: device,
      password: token,
      virtual_host: vhost]
    AMQP.Connection.open(opts)
  end

  @doc false
  def log_worker(pid) do
    for log <- Farmbot.Logger.get_logs(@log_fetch_amnt) do
      send(pid, {:log, log})
    end
    log_worker(pid)
  end

  defp push_bot_log(chan, bot, log) do
    json = Farmbot.JSON.encode!(log)
    :ok = AMQP.Basic.publish chan, @exchange, "bot.#{bot}.logs", json
  end

  defp add_position_to_log(%{} = log, %{position: pos}) do
    Map.merge(log, pos)
  end
end
