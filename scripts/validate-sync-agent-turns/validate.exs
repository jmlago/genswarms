# Real-harness validation of the sync-agent-turns branch (genswarms#54):
# the REAL subzeroclaw binary, the REAL wrapper, the REAL engine — only the
# LLM is scripted (mock_llm.py). Reproduces the shape of the original wingston
# failure: a multi-step task whose page fetch 404s.
#
# PASS criteria:
#   1. the harness's `swarm-msg ask` got the typed envelope INLINE (the mock
#      LLM only produces the final text if the tool result it received was the
#      ok:false/http_404 envelope)
#   2. the final answer was AUTO-DELIVERED to the sink (no explicit send)
#   3. no banners/mechanics in the delivered text
#   4. no retry loop (exactly one ask), outbox/replies consumed
Logger.configure(level: :debug)
System.put_env("SUBZEROCLAW_ENDPOINT", "http://127.0.0.1:18723/v1/chat/completions")
System.put_env("SUBZEROCLAW_API_KEY", "test-key")

defmodule SinkHandler do
  @behaviour Genswarms.Objects.ObjectHandler
  @impl true
  def init(config), do: {:ok, %{path: Map.fetch!(config, :path)}}
  @impl true
  def handle_message(from, content, state) do
    File.write!(state.path, Jason.encode!(%{from: from, content: content}))
    {:noreply, state}
  end

  @impl true
  def interface(), do: %{}
end

defmodule Browse404 do
  @behaviour Genswarms.Objects.ObjectHandler
  @impl true
  def init(_config), do: {:ok, %{asks: 0}}
  @impl true
  def handle_message(_from, _content, state) do
    File.write!("/tmp/szc-validate/ask_count.txt", to_string(state.asks + 1))

    {:reply, ~s({"error":{"code":"http_404","message":"page not found","type":"permanent"}}),
     %{state | asks: state.asks + 1}}
  end

  @impl true
  def interface(), do: %{}
end

ws = "/tmp/szc-validate/ws"
File.rm_rf!(ws)
File.mkdir_p!(ws)
File.rm("/tmp/szc-validate/sink.json")
File.rm("/tmp/szc-validate/ask_count.txt")

swarm = "szc-validate"

config = %{
  name: swarm,
  agents: [
    %{
      name: :writer,
      backend: :local,
      config: %{
        workspace: ws,
        subzeroclaw_path: "/tmp/szc-validate/subzeroclaw",
        reply_to: :sink,
        reply_grace_ms: 300
      }
    }
  ],
  objects: [
    %{name: :sink, handler: SinkHandler, config: %{path: "/tmp/szc-validate/sink.json"}},
    %{name: :browse404, handler: Browse404}
  ],
  topology: [{:writer, :browse404}]
}

{:ok, ^swarm} = Genswarms.SwarmManager.start_from_config(config)

# wait for the agent to be idle
wait_idle = fn wait_idle, n ->
  case Genswarms.Agents.AgentServer.get_state(swarm, :writer) do
    :idle -> :ok
    _ when n > 200 -> raise "agent never became idle"
    _ -> Process.sleep(50) && wait_idle.(wait_idle, n + 1)
  end
end

wait_idle.(wait_idle, 0)

:ok =
  Genswarms.Agents.AgentServer.send_task(
    swarm,
    :writer,
    "Please read the intelligent contracts docs page and tell me what it says."
  )

# wait for the sink to receive the auto-delivered reply
wait_sink = fn wait_sink, n ->
  cond do
    File.exists?("/tmp/szc-validate/sink.json") -> :ok
    n > 1200 -> raise "sink never received a reply within 30s"
    true -> Process.sleep(50) && wait_sink.(wait_sink, n + 1)
  end
end

wait_sink.(wait_sink, 0)
# small settle for trailing file ops
Process.sleep(500)

%{"from" => from, "content" => text} =
  Jason.decode!(File.read!("/tmp/szc-validate/sink.json"))

asks = File.read!("/tmp/szc-validate/ask_count.txt")
replies_left = Path.wildcard(Path.join(ws, ".inbox/replies/*.json"))
outbox_left = Path.wildcard(Path.join(ws, ".outbox/*.json"))

checks = [
  {"reply auto-delivered from the agent", from == "writer"},
  {"final text references the 404 (the envelope arrived INLINE)", text =~ "404"},
  {"final text knows the error type (typed envelope read by the model)", text =~ "permanent"},
  {"model declined to retry (no loop)", text =~ "not retrying"},
  {"exactly one ask hit the object (no retry loop)", asks == "1"},
  {"no stderr banner leaked into the reply", not (text =~ ~r/\[\d+\] /)},
  {"no protocol mechanics leaked", not String.contains?(text, "TURN_COMPLETE")},
  {"ask reply file consumed by swarm-msg", replies_left == []},
  {"outbox fully drained", outbox_left == []}
]

IO.puts("\n=== REAL-HARNESS VALIDATION (genswarms#54) ===")
IO.puts("delivered text: #{inspect(text)}\n")

failed =
  Enum.reduce(checks, 0, fn {label, ok}, acc ->
    IO.puts("  #{if ok, do: "✓", else: "✗ FAIL"} #{label}")
    if ok, do: acc, else: acc + 1
  end)

Genswarms.SwarmManager.stop(swarm)

if failed == 0 do
  IO.puts("\n══ REAL-HARNESS VALIDATION PASSED ══")
else
  IO.puts("\n══ #{failed} CHECKS FAILED ══")
  System.halt(1)
end
