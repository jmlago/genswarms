import Config

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration
config :genswarms, GenswarmsWeb.Endpoint, server: true
