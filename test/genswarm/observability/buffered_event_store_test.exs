defmodule Genswarm.Observability.BufferedEventStoreTest do
  use ExUnit.Case, async: false

  alias Genswarm.CLI.SwarmRegistry
  alias Genswarm.Observability.EventStore.Buffered

  setup do
    SwarmRegistry.init()
    :ok
  end

  defp ev(type, swarm, extra \\ %{}) do
    Map.merge(
      %{level: :info, category: :agent, event_type: type, message: "m", swarm: swarm},
      extra
    )
  end

  describe "SwarmRegistry.log_events_bulk/1" do
    test "writes a whole batch in one transaction" do
      base = SwarmRegistry.max_event_id()

      :ok =
        SwarmRegistry.log_events_bulk([
          ev(:bulk_one, "bulk-x"),
          ev(:bulk_two, "bulk-x", %{agent: :a1, metadata: %{n: 1}})
        ])

      rows = SwarmRegistry.events_since(base, 100)
      types = Enum.map(rows, & &1.event_type)
      assert :bulk_one in types
      assert :bulk_two in types

      two = Enum.find(rows, &(&1.event_type == :bulk_two))
      assert two.agent == :a1
      assert two.metadata["n"] == 1
    end

    test "empty batch is a no-op" do
      assert SwarmRegistry.log_events_bulk([]) == :ok
    end
  end

  describe "Buffered.Writer" do
    defp configure_writer(opts) do
      prev = Application.get_env(:genswarm, Buffered)

      Application.put_env(
        :genswarm,
        Buffered,
        Keyword.merge([inner: Genswarm.Observability.EventStore.Sqlite], opts)
      )

      ExUnit.Callbacks.on_exit(fn -> Application.put_env(:genswarm, Buffered, prev) end)
      ExUnit.Callbacks.start_supervised!(Buffered.Writer)
    end

    test "buffers writes and flushes them after the interval" do
      configure_writer(interval_ms: 60, max_buffer: 1_000)
      base = SwarmRegistry.max_event_id()

      :ok = Buffered.persist(ev(:buffered_late, "buf-a"))

      # Not yet flushed (interval is 60ms, max_buffer not reached).
      assert SwarmRegistry.events_since(base, 100) == []

      Process.sleep(150)

      rows = SwarmRegistry.events_since(base, 100)
      assert Enum.any?(rows, &(&1.event_type == :buffered_late))
    end

    test "flushes early once max_buffer is reached, before the interval" do
      # Long interval: if events show up quickly it can only be the overflow flush.
      configure_writer(interval_ms: 5_000, max_buffer: 3)
      base = SwarmRegistry.max_event_id()

      Buffered.persist(ev(:over_1, "buf-b"))
      Buffered.persist(ev(:over_2, "buf-b"))
      Buffered.persist(ev(:over_3, "buf-b"))

      Process.sleep(100)

      types = SwarmRegistry.events_since(base, 100) |> Enum.map(& &1.event_type)
      assert :over_1 in types and :over_2 in types and :over_3 in types
    end
  end
end
