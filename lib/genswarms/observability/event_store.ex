defmodule Genswarms.Observability.EventStore do
  @moduledoc """
  The durable, cross-process event store — behaviour + facade.

  `LogStore` keeps a fast in-node ETS ring buffer for live queries, but the
  durable log that every process shares (so a central monitor sees daemon swarms
  in other BEAMs) goes through this module. Everything that **persists**, **reads**
  or **tails** events does so via this facade, never the concrete backend — so the
  backend is a single swappable knob.

  ## Backends

  The implementation is configured (default: the SQLite-backed one):

      config :genswarms, :event_store, Genswarms.Observability.EventStore.Sqlite

  `Genswarms.Observability.EventStore.Sqlite` is the current backend. It is wired
  for swapping as load grows:

    * **Batching / pooling** — `persist/1` is fire-and-forget (returns `:ok`); a
      backend may buffer writes and bulk-flush them on a pooled connection. Such a
      backend is a process, so it declares it via `child_specs/0` and the app
      supervises it. The callers never change.
    * **Postgres** — a `…EventStore.Postgres` backend (Ecto/Postgrex pool, batched
      inserts, time-partitioned table). `LISTEN/NOTIFY` would let `EventRelay`
      switch from polling to push.
    * **Redis / streaming** — a backend publishing to Redis Streams / NATS for
      fan-out, with a relational sink for queryable history.

  None of those touch `LogStore`, the telemetry bridge, the controllers, the
  channel, or `EventRelay` — they all go through the four callbacks below.

  ## Event shape

  `persist/1` takes a map with `:level`, `:category`, `:event_type`, `:message`
  and optional `:swarm`, `:agent`, `:metadata`. Reads return maps additionally
  carrying `:id` and `:timestamp` (assigned by the backend).
  """

  @type event :: %{
          optional(:id) => term(),
          optional(:timestamp) => term(),
          level: atom(),
          category: atom(),
          event_type: atom(),
          message: String.t(),
          swarm: String.t() | nil,
          agent: atom() | nil,
          metadata: map()
        }

  @doc "Durably persist one event. Fire-and-forget; a backend may batch internally."
  @callback persist(event()) :: :ok

  @doc """
  Durably persist a batch of events in one operation.

  Optional: backends that can write efficiently in bulk (e.g. one transaction)
  implement it; otherwise the facade falls back to N× `persist/1`.
  """
  @callback persist_many([event()]) :: :ok

  @doc "Query persisted events (filters: :level/:category/:swarm/:agent/:event_type/:minutes/:limit)."
  @callback query(keyword()) :: [event()]

  @doc "Events with id strictly greater than `since_id`, oldest first (for tailing)."
  @callback events_since(since_id :: non_neg_integer(), limit :: pos_integer()) :: [event()]

  @doc "Highest persisted event id (0 if none)."
  @callback max_event_id() :: non_neg_integer()

  @doc """
  Child specs the backend needs supervised (e.g. a write-batching buffer or a
  connection pool). Defaults to none for stateless backends like SQLite.
  """
  @callback child_specs() :: [:supervisor.child_spec() | {module(), term()} | module()]

  @optional_callbacks child_specs: 0, persist_many: 1

  @default_backend Genswarms.Observability.EventStore.Sqlite

  # ── facade ───────────────────────────────────────────────────────────────────

  @doc "The configured backend module."
  @spec backend() :: module()
  def backend, do: Application.get_env(:genswarms, :event_store, @default_backend)

  @spec persist(event()) :: :ok
  def persist(event), do: backend().persist(event)

  @spec persist_many([event()]) :: :ok
  def persist_many(events) do
    mod = backend()

    if function_exported?(mod, :persist_many, 1) do
      mod.persist_many(events)
    else
      Enum.each(events, &mod.persist/1)
      :ok
    end
  end

  @spec query(keyword()) :: [event()]
  def query(opts \\ []), do: backend().query(opts)

  @spec events_since(non_neg_integer(), pos_integer()) :: [event()]
  def events_since(since_id, limit \\ 500), do: backend().events_since(since_id, limit)

  @spec max_event_id() :: non_neg_integer()
  def max_event_id, do: backend().max_event_id()

  @doc "Supervisor children the configured backend needs (none for stateless backends)."
  @spec child_specs() :: [term()]
  def child_specs do
    mod = backend()

    if function_exported?(mod, :child_specs, 0) do
      mod.child_specs()
    else
      []
    end
  end
end
