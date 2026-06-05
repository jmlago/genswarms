defmodule Mix.Tasks.Genswarms.Resume do
  @moduledoc """
  Resumes a paused swarm.

  ## Usage

      mix swarm resume <swarm-name>

  This unfreezes all paused Docker containers in the swarm,
  allowing them to continue processing.
  """

  use Mix.Task

  @shortdoc "Resume a paused swarm"

  @impl Mix.Task
  def run([swarm_name]) do
    resume_swarm(swarm_name)
  end

  def run(_) do
    Mix.shell().error("Usage: mix swarm resume <swarm-name>")
  end

  defp resume_swarm(swarm_name) do
    # Find all paused containers for this swarm
    prefix = "szc-#{swarm_name}-"

    {output, 0} =
      System.cmd(
        "docker",
        [
          "ps",
          "--filter",
          "name=#{prefix}",
          "--filter",
          "status=paused",
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
      Mix.shell().info("No paused containers found")
    else
      # Resume all containers
      Mix.shell().info("Resuming #{length(containers)} containers...")

      results =
        Enum.map(containers, fn container ->
          case System.cmd("docker", ["unpause", container], stderr_to_stdout: true) do
            {_, 0} ->
              Mix.shell().info("  ✓ Resumed #{container}")
              :ok

            {err, _} ->
              Mix.shell().error("  ✗ Failed to resume #{container}: #{err}")
              :error
          end
        end)

      success_count = Enum.count(results, &(&1 == :ok))
      Mix.shell().info("✓ Resumed #{success_count}/#{length(containers)} containers")
    end
  end
end
