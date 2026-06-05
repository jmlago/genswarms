defmodule Genswarms.Observability.EventRelayTest do
  use ExUnit.Case, async: false

  alias Genswarms.CLI.SwarmRegistry
  alias Genswarms.Observability.{EventRelay, LogStore}

  setup do
    SwarmRegistry.init()
    :ok
  end

  describe "SwarmRegistry tail helpers" do
    test "events_since returns only newer events, oldest first" do
      base = SwarmRegistry.max_event_id()

      SwarmRegistry.log_event(:info, :agent, :one, "first", swarm: "relay-a")
      SwarmRegistry.log_event(:info, :agent, :two, "second", swarm: "relay-a")

      rows = SwarmRegistry.events_since(base)
      types = Enum.map(rows, & &1.event_type)

      assert :one in types
      assert :two in types
      # ascending by id
      assert rows == Enum.sort_by(rows, & &1.id)
      # nothing at/below the baseline leaks in
      assert Enum.all?(rows, &(&1.id > base))
    end

    test "max_event_id grows as events are written" do
      before = SwarmRegistry.max_event_id()
      SwarmRegistry.log_event(:info, :swarm, :tick, "x", swarm: "relay-b")
      assert SwarmRegistry.max_event_id() > before
    end
  end

  describe "relay" do
    test "re-broadcasts newly persisted events onto the LogStore PubSub topics" do
      # Subscribe to the same topics SwarmChannel listens on.
      LogStore.subscribe()
      Phoenix.PubSub.subscribe(Genswarms.PubSub, "log_store:events:relay-c")
      on_exit(fn -> LogStore.unsubscribe() end)

      # Relay starts at the current tip, then a fresh event is written.
      start_supervised!({EventRelay, interval: 30})
      SwarmRegistry.log_event(:warning, :routing, :invalid_route, "nope", swarm: "relay-c")

      # Arrives on the general topic...
      assert_receive {:log_event, %{swarm: "relay-c", event_type: :invalid_route} = event}, 1_000
      assert event.level == :warning
      # ...and on the per-swarm topic.
      assert_receive {:log_event, %{swarm: "relay-c", event_type: :invalid_route}}, 1_000
    end

    test "does not replay events that predate the relay" do
      SwarmRegistry.log_event(:info, :agent, :old_event, "before", swarm: "relay-d")

      LogStore.subscribe()
      on_exit(fn -> LogStore.unsubscribe() end)

      start_supervised!({EventRelay, interval: 30})

      refute_receive {:log_event, %{event_type: :old_event}}, 300
    end
  end
end
