defmodule Genswarms.Observability.EventStore.Buffered do
  @moduledoc """
  A write-batching `EventStore` decorator — engine-independent.

  Wraps any inner `EventStore` backend. Writes (`persist/1`) are enqueued into an
  in-memory buffer and flushed in one batched operation every `:interval_ms`
  (or sooner if `:max_buffer` is reached) via the inner backend's `persist_many/1`.
  Reads (`query/1`, `events_since/2`, `max_event_id/0`) pass straight through.

  This decouples persistence from the caller's critical path — `LogStore` no
  longer blocks on disk — and lets the inner backend amortize the write (with the
  SQLite backend, one `open → BEGIN → inserts → COMMIT → close` per flush instead
  of a connection per event).

  ## Config

      config :genswarms, :event_store, Genswarms.Observability.EventStore.Buffered

      config :genswarms, Genswarms.Observability.EventStore.Buffered,
        inner: Genswarms.Observability.EventStore.Sqlite,
        interval_ms: 100,
        max_buffer: 1_000

  ## Durability

  Events live in memory until the next flush, so a hard crash can lose up to one
  flush interval (~`:interval_ms`) of events. The live in-node path is unaffected
  (`LogStore`'s ETS insert and PubSub broadcast happen synchronously, before this);
  only the durable write is deferred. The buffer is flushed on graceful shutdown.

  The inner backend can itself be swapped (e.g. Postgres) without touching this.
  """

  @behaviour Genswarms.Observability.EventStore

  @default_inner Genswarms.Observability.EventStore.Sqlite

  defp config, do: Application.get_env(:genswarms, __MODULE__, [])
  defp inner, do: Keyword.get(config(), :inner, @default_inner)

  @impl true
  def persist(event) do
    GenServer.cast(__MODULE__.Writer, {:enqueue, [event]})
    :ok
  end

  @impl true
  def persist_many(events) do
    GenServer.cast(__MODULE__.Writer, {:enqueue, events})
    :ok
  end

  @impl true
  def query(opts), do: inner().query(opts)

  @impl true
  def events_since(since_id, limit), do: inner().events_since(since_id, limit)

  @impl true
  def max_event_id, do: inner().max_event_id()

  @impl true
  def child_specs do
    inner = inner()
    inner_specs = if function_exported?(inner, :child_specs, 0), do: inner.child_specs(), else: []
    [__MODULE__.Writer | inner_specs]
  end

  defmodule Writer do
    @moduledoc "GenServer holding the write buffer; flushes on a timer or on overflow."
    use GenServer
    require Logger

    alias Genswarms.Observability.EventStore.Buffered

    def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

    @impl true
    def init(_) do
      cfg = Application.get_env(:genswarms, Buffered, [])

      state = %{
        buffer: [],
        count: 0,
        inner: Keyword.get(cfg, :inner, Genswarms.Observability.EventStore.Sqlite),
        interval: Keyword.get(cfg, :interval_ms, 100),
        max: Keyword.get(cfg, :max_buffer, 1_000)
      }

      schedule(state.interval)
      {:ok, state}
    end

    @impl true
    # Buffer is reversed on flush, so prepend (O(1)) and keep insertion order.
    def handle_cast({:enqueue, events}, state) do
      buffer = Enum.reduce(events, state.buffer, fn e, acc -> [e | acc] end)
      count = state.count + length(events)
      state = %{state | buffer: buffer, count: count}

      if count >= state.max do
        {:noreply, flush(state)}
      else
        {:noreply, state}
      end
    end

    @impl true
    def handle_info(:flush, state) do
      state = flush(state)
      schedule(state.interval)
      {:noreply, state}
    end

    @impl true
    def terminate(_reason, state) do
      # Best-effort flush so a graceful shutdown doesn't drop the buffered tail.
      flush(state)
      :ok
    end

    defp flush(%{buffer: []} = state), do: state

    defp flush(state) do
      batch = Enum.reverse(state.buffer)

      try do
        state.inner.persist_many(batch)
      rescue
        e ->
          Logger.warning(
            "EventStore.Buffered dropped #{length(batch)} events on flush: #{inspect(e)}"
          )
      end

      %{state | buffer: [], count: 0}
    end

    defp schedule(interval), do: Process.send_after(self(), :flush, interval)
  end
end
