defmodule GenswarmsWeb.SwarmSocket do
  @moduledoc """
  WebSocket for real-time swarm communication.

  Clients can:
  - Subscribe to swarm events
  - Send tasks to agents
  - Receive agent output in real-time
  """

  use Phoenix.Socket

  channel "swarm:*", GenswarmsWeb.SwarmChannel

  @impl true
  def connect(_params, socket, _connect_info) do
    {:ok, socket}
  end

  @impl true
  def id(_socket), do: nil
end
