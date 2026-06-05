# General application configuration
import Config

config :genswarms,
  ecto_repos: [],
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :genswarms, GenswarmsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: GenswarmsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Genswarms.PubSub

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :swarm, :agent]

# Use Jason for JSON parsing
config :phoenix, :json_library, Jason

# Durable cross-process event store backend (see Genswarms.Observability.EventStore).
# Default: batch writes every 100ms (one transaction per flush) on top of SQLite.
# Swap the inner backend to Postgres/Redis here as load grows.
config :genswarms, :event_store, Genswarms.Observability.EventStore.Buffered

config :genswarms, Genswarms.Observability.EventStore.Buffered,
  inner: Genswarms.Observability.EventStore.Sqlite,
  interval_ms: 100,
  max_buffer: 1_000

# Genswarms specific configuration
config :genswarms,
  # Default path to subzeroclaw binary
  subzeroclaw_path: System.get_env("SUBZEROCLAW_PATH", "subzeroclaw"),
  # Base directory for swarm data
  swarm_data_dir: System.get_env("SWARM_DATA_DIR", "~/.subzeroclaw/swarms"),
  # Default skills directory
  skills_dir: System.get_env("SKILLS_DIR", "priv/skills")

# Import environment specific config
import_config "#{config_env()}.exs"
