defmodule GenswarmsWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :genswarms

  # WebSocket for real-time swarm communication
  socket "/swarm", GenswarmsWeb.SwarmSocket,
    websocket: true,
    longpoll: false

  # Code reloading in development
  if code_reloading? do
    plug Phoenix.CodeReloader
  end

  # Telemetry
  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Request parsing
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # Router
  plug GenswarmsWeb.Router
end
