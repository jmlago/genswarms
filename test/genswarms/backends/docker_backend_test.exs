defmodule Genswarms.Backends.DockerBackendTest do
  use ExUnit.Case, async: true

  alias Genswarms.Backends.DockerBackend

  describe "build_docker_args/8 (command-injection hardening)" do
    test "returns a flat argv list of strings (no shell string)" do
      args =
        DockerBackend.build_docker_args("szc-s-a", "img:tag", nil, nil, nil, nil, "agentA", %{})

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
      str =
        DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{cmd: "python app.py"})

      assert Enum.take(str, -3) == ["sh", "-c", "python app.py"]

      lst =
        DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", %{
          cmd: ["python", "app.py"]
        })

      assert Enum.take(lst, -2) == ["python", "app.py"]
    end
  end

  describe "build_docker_args/8 (sandbox hardening)" do
    defp args(config),
      do: DockerBackend.build_docker_args("c", "i", nil, nil, nil, nil, "a", config)

    # true if [flag, value] appear as consecutive argv elements
    defp has_pair?(args, flag, value) do
      args |> Enum.chunk_every(2, 1, :discard) |> Enum.member?([flag, value])
    end

    test "secure defaults: no-new-privileges, cap-drop ALL, pids-limit, private tmpfs" do
      a = args(%{})
      assert has_pair?(a, "--security-opt", "no-new-privileges")
      assert has_pair?(a, "--cap-drop", "ALL")
      assert has_pair?(a, "--pids-limit", "512")
      assert has_pair?(a, "--tmpfs", "/tmp")
    end

    test "the host /tmp is no longer bind-mounted into the container" do
      a = args(%{})
      refute "/tmp:/tmp" in a
      refute has_pair?(a, "-v", "/tmp:/tmp")
    end

    test "allow_new_privileges: true drops the no-new-privileges hardening" do
      a = args(%{allow_new_privileges: true})
      refute has_pair?(a, "--security-opt", "no-new-privileges")
    end

    test "cap_drop_all: false skips the capability drop" do
      a = args(%{cap_drop_all: false})
      refute has_pair?(a, "--cap-drop", "ALL")
    end

    test "cap_add adds specific capabilities back on top of the drop" do
      a = args(%{cap_add: ["NET_RAW", :SYS_PTRACE]})
      assert has_pair?(a, "--cap-drop", "ALL")
      assert has_pair?(a, "--cap-add", "NET_RAW")
      assert has_pair?(a, "--cap-add", "SYS_PTRACE")
    end

    test "pids_limit can be overridden or disabled" do
      assert has_pair?(args(%{pids_limit: 64}), "--pids-limit", "64")
      refute Enum.member?(args(%{pids_limit: false}), "--pids-limit")
      refute Enum.member?(args(%{pids_limit: 0}), "--pids-limit")
    end

    test "hardening flags precede the image and container command" do
      a = args(%{})
      image_idx = Enum.find_index(a, &(&1 == "i"))
      sec_idx = Enum.find_index(a, &(&1 == "--security-opt"))
      assert sec_idx < image_idx
    end
  end

  # helper: return the list starting at the first occurrence of `val`
  defp drop_until([val | _] = rest, val), do: rest
  defp drop_until([_ | t], val), do: drop_until(t, val)
  defp drop_until([], _val), do: []
end
