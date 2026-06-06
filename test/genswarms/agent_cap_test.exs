defmodule Genswarms.AgentCapTest do
  @moduledoc """
  Per-swarm agent cap (CWE-770): add_agent and scale_agent_group must refuse to
  spawn beyond max_agents_per_swarm, and scale must reject an oversized count
  before building the target list.
  """
  use ExUnit.Case, async: false

  alias Genswarms.SwarmManager
  alias Genswarms.CLI.SwarmRegistry

  @cap 3

  setup do
    original = Application.get_env(:genswarms, :max_agents_per_swarm)
    Application.put_env(:genswarms, :max_agents_per_swarm, @cap)

    swarm = "cap-test-#{System.unique_integer([:positive])}"
    config = %{name: swarm, agents: [%{name: :a1, backend: :mock}], topology: []}
    {:ok, ^swarm} = SwarmManager.start_from_config(config)
    SwarmRegistry.clear_overlay(swarm)

    on_exit(fn ->
      SwarmManager.stop(swarm)
      SwarmRegistry.clear_overlay(swarm)

      if original,
        do: Application.put_env(:genswarms, :max_agents_per_swarm, original),
        else: Application.delete_env(:genswarms, :max_agents_per_swarm)
    end)

    {:ok, swarm: swarm}
  end

  test "add_agent is refused once the swarm is at the cap", %{swarm: swarm} do
    # Seed has 1 agent (a1); add up to the cap of 3.
    {:ok, :a2} = SwarmManager.add_agent(swarm, %{name: :a2, backend: :mock})
    {:ok, :a3} = SwarmManager.add_agent(swarm, %{name: :a3, backend: :mock})

    # The 4th would exceed the cap.
    assert {:error, {:agent_limit_reached, @cap}} =
             SwarmManager.add_agent(swarm, %{name: :a4, backend: :mock})

    assert [] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :a4})
  end

  test "scale rejects a count above the cap before spawning", %{swarm: swarm} do
    assert {:error, {:scale_limit_exceeded, @cap}} =
             SwarmManager.scale_agent_group(swarm, :a1, 100_000)

    # No replica atoms/processes were created.
    assert [] = Registry.lookup(Genswarms.AgentRegistry, {swarm, :a1_1})
  end

  test "scale within the cap still works", %{swarm: swarm} do
    assert {:ok, %{added: added}} = SwarmManager.scale_agent_group(swarm, :a1, @cap)
    assert added == [:a1_1, :a1_2, :a1_3]
  end
end
