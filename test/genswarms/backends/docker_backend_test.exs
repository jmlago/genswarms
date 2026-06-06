defmodule Genswarms.Backends.DockerBackendTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.DockerBackend

  describe "build_docker_args/8 (command-injection hardening)" do
    test "returns a flat argv list of strings (no shell string)" do
      args = DockerBackend.build_docker_args("szc-s-a", "img:tag", nil, nil, nil, nil, "agentA", %{})
      assert is_list(args)
      assert Enum.all?(args, &is_binary/1)
      # container name is a single discrete element right after --name
      assert ["--name", "szc-s-a" | _] = drop_until(args, "--name")
    end

    test "env values are literal argv elements; a malicious model cannot split argv or inject" do
      evil = "x'; touch /tmp/pwned #"
      args = DockerBackend.build_docker_args("c", "i", nil, "sk-secret", evil, nil, "a", %{})

      # the whole malicious value is ONE element, verbatim (quote preserved, not interpreted)
      assert "SUBZEROCLAW_MODEL=#{evil}" in args
      assert "SUBZEROCLAW_API_KEY=sk-secret" in args
      # it did not break out into separate tokens
      refute "touch" in args
      refute "/tmp/pwned" in args
    end

    test "default container command is argv ['sh','-c',script] (runs in the container, not host)" do
      args = DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{})
      assert ["sh", "-c", script] = Enum.take(args, -3)
      assert script =~ "subzeroclaw"
    end

    test "a string :cmd is wrapped as sh -c (container shell); a list :cmd is used as argv" do
      str = DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{cmd: "python app.py"})
      assert Enum.take(str, -3) == ["sh", "-c", "python app.py"]

      lst = DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{cmd: ["python", "app.py"]})
      assert Enum.take(lst, -2) == ["python", "app.py"]
    end
  end

  # helper: return the list starting at the first occurrence of `val`
  defp drop_until([val | _] = rest, val), do: rest
  defp drop_until([_ | t], val), do: drop_until(t, val)
  defp drop_until([], _val), do: []
end
