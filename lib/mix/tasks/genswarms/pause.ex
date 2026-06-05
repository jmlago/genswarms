defmodule Mix.Tasks.Genswarms.Pause do
  @moduledoc """
  Pauses a running swarm (freezes all containers without stopping).

  ## Usage

      mix swarm pause <swarm-name>

  This freezes all Docker containers in the swarm. The containers remain
  running but all processes are suspended. Use `mix swarm resume` to continue.
  """

  use Mix.Task

  @shortdoc "Pause a running swarm"

  @impl Mix.Task
  def run([swarm_name]) do
    pause_swarm(swarm_name)
  end

  def run(_) do
    Mix.shell().error("Usage: mix swarm pause <swarm-name>")
  end

  defp pause_swarm(swarm_name) do
    # Find all containers for this swarm
    prefix = "szc-#{swarm_name}-"

    {output, 0} =
      System.cmd(
        "docker",
        [
          "ps",
          "--filter",
          "name=#{prefix}",
          "--format",
          "{{.Names}}"
        ],
        stderr_to_stdout: true
      )

    containers =
      output
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.starts_with?(&1, prefix))

    if containers == [] do
      Mix.shell().error("No running containers found for swarm")
      System.halt(1)
    end

    # Pause all containers
    Mix.shell().info("Pausing #{length(containers)} containers...")

    results =
      Enum.map(containers, fn container ->
        case System.cmd("docker", ["pause", container], stderr_to_stdout: true) do
          {_, 0} ->
            Mix.shell().info("  ✓ Paused #{container}")
            :ok

          {err, _} ->
            Mix.shell().error("  ✗ Failed to pause #{container}: #{err}")
            :error
        end
      end)

    success_count = Enum.count(results, &(&1 == :ok))
    Mix.shell().info("✓ Paused #{success_count}/#{length(containers)} containers")
  end
end
