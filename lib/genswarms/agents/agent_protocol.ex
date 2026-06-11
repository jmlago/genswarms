defmodule Genswarms.Agents.AgentProtocol do
  @moduledoc """
  JSON protocol for orchestrator-agent communication.

  ## Orchestrator → Agent Messages

      {"type": "task", "content": "analyze...", "from": "orchestrator"}
      {"type": "message", "from": "researcher", "content": "found..."}
      {"type": "system", "command": "status"}

  ## Agent → Orchestrator Messages

      {"type": "output", "content": "Working on..."}
      {"type": "send", "to": "coder", "content": "implement..."}
      {"type": "broadcast", "content": "done"}
      {"type": "status", "state": "idle"}
  """

  @type message_type ::
          :task | :message | :system | :output | :send | :broadcast | :status

  @type outbound_message :: %{
          required(:type) => :task | :message | :system,
          optional(:content) => String.t(),
          optional(:from) => String.t(),
          optional(:command) => String.t()
        }

  @type inbound_message :: %{
          required(:type) => :output | :send | :broadcast | :status,
          optional(:content) => String.t(),
          optional(:to) => String.t(),
          optional(:state) => String.t()
        }

  @doc """
  Encodes a task message to send to an agent.
  """
  @spec encode_task(String.t(), String.t()) :: binary()
  def encode_task(content, from \\ "orchestrator") do
    Jason.encode!(%{
      type: "task",
      content: content,
      from: from
    })
  end

  @doc """
  Encodes an inter-agent message.
  """
  @spec encode_message(String.t(), String.t()) :: binary()
  def encode_message(content, from) do
    Jason.encode!(%{
      type: "message",
      content: content,
      from: to_string(from)
    })
  end

  @doc """
  Encodes a system command.
  """
  @spec encode_system(String.t()) :: binary()
  def encode_system(command) do
    Jason.encode!(%{
      type: "system",
      command: command
    })
  end

  @doc """
  Decodes a message from an agent.

  Returns `{:ok, parsed_message}` or `{:error, reason}`.
  """
  @spec decode(binary()) :: {:ok, map()} | {:error, term()}
  def decode(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, %{"type" => type} = msg} ->
        {:ok, normalize_message(type, msg)}

      {:ok, _} ->
        {:error, :missing_type}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Parses raw agent output for swarm messages.

  Only supports the swarm-msg CLI tool format:
    <<SWARM_MSG:TO=agent_name:START>>
    message content
    <<SWARM_MSG:END>>

  Returns a list of messages extracted from the output.
  """
  @spec parse_output(String.t()) :: [map()]
  def parse_output(output) do
    messages = parse_swarm_messages(output)

    # Always include the full output (cleaned) as first message
    [%{type: :output, content: clean_output(output)} | messages]
  end

  # Parse <<SWARM_MSG:TO=agent:START>>...<<SWARM_MSG:END>> format
  defp parse_swarm_messages(output) do
    # Pattern for: <<SWARM_MSG:TO=agent_name:START>>\ncontent\n<<SWARM_MSG:END>>
    send_pattern = ~r/<<SWARM_MSG:TO=([a-zA-Z_][a-zA-Z0-9_]*):START>>\n(.*?)<<SWARM_MSG:END>>/s

    # Pattern for: <<SWARM_MSG:BROADCAST:START>>\ncontent\n<<SWARM_MSG:END>>
    broadcast_pattern = ~r/<<SWARM_MSG:BROADCAST:START>>\n(.*?)<<SWARM_MSG:END>>/s

    send_messages =
      Regex.scan(send_pattern, output)
      |> Enum.map(fn [_full, target, content] ->
        %{type: :send, to: String.to_atom(target), content: String.trim(content)}
      end)

    broadcast_messages =
      Regex.scan(broadcast_pattern, output)
      |> Enum.map(fn [_full, content] ->
        %{type: :broadcast, content: String.trim(content)}
      end)

    send_messages ++ broadcast_messages
  end

  # Remove swarm message markers from output for cleaner display
  defp clean_output(output) do
    output
    |> String.replace(~r/<<SWARM_MSG:[^>]+>>\n?/, "")
    |> String.replace("<<SWARM_MSG:END>>\n?", "")
    |> String.trim()
  end

  @doc """
  Checks if a message type is routable to other agents.
  """
  @spec routable?(atom()) :: boolean()
  def routable?(:send), do: true
  def routable?(:broadcast), do: true
  def routable?(_), do: false

  # Private functions

  defp normalize_message("task", msg) do
    %{
      type: :task,
      content: Map.get(msg, "content", ""),
      from: Map.get(msg, "from", "orchestrator")
    }
  end

  defp normalize_message("message", msg) do
    %{
      type: :message,
      content: Map.get(msg, "content", ""),
      from: Map.get(msg, "from") |> maybe_to_atom()
    }
  end

  defp normalize_message("system", msg) do
    %{
      type: :system,
      command: Map.get(msg, "command", "")
    }
  end

  defp normalize_message("output", msg) do
    %{
      type: :output,
      content: Map.get(msg, "content", "")
    }
  end

  defp normalize_message("send", msg) do
    %{
      type: :send,
      to: Map.get(msg, "to") |> maybe_to_atom(),
      content: Map.get(msg, "content", "")
    }
  end

  defp normalize_message("broadcast", msg) do
    %{
      type: :broadcast,
      content: Map.get(msg, "content", "")
    }
  end

  defp normalize_message("status", msg) do
    %{
      type: :status,
      state: Map.get(msg, "state", "unknown")
    }
  end

  defp normalize_message(type, msg) do
    %{
      type: String.to_atom(type),
      raw: msg
    }
  end

  defp maybe_to_atom(nil), do: nil
  defp maybe_to_atom(s) when is_binary(s), do: String.to_atom(s)
  defp maybe_to_atom(a) when is_atom(a), do: a

  # ── turn stdout grammar ─────────────────────────────────────────────────────
  # This module is the SINGLE owner of the agent-stdout grammar: the SWARM_MSG
  # markers above, and the turn mechanics below (<<TURN_COMPLETE>>, the idle
  # "> " prompt, and the wrapper's one-JSON-object-per-line stream).

  @doc """
  Strips turn-lifecycle mechanics — `<<TURN_COMPLETE>>` markers and a trailing
  idle prompt — from accumulated turn output, for logging and message parsing.
  """
  @spec strip_turn_markers(String.t()) :: String.t()
  def strip_turn_markers(output) do
    output
    |> String.replace("<<TURN_COMPLETE>>", "")
    |> String.replace(~r/\n?> $/, "")
  end

  @doc """
  The turn's reply text: harness stdout minus protocol mechanics. `""` when the
  turn produced no user-facing text.

  The wrapper (`priv/szc-wrapper-fifo.sh`) emits one JSON object per line of
  the harness's stdout — `{"type":"output","content":"..."}` — and tags harness
  stderr (per-call banners, diagnostics) as `{"type":"log",...}`. The
  AgentServer accumulates these into a single per-turn buffer, so the buffer is
  a sequence of back-to-back JSON objects, possibly with raw text in between
  (mock/test backends write plain text). This reconstructs the harness's stdout
  for the turn — the `"output"`-typed contents in order, plus any raw non-JSON
  segments — and strips `<<TURN_COMPLETE>>` markers and bare `> ` prompts.
  Because the harness prints the model's text only when the model finishes (and
  its progress banners go to stderr), what remains IS the turn's final answer.

  Total: invalid UTF-8 (a harness `cat`ing a binary file on a wrapper-less
  backend) is handled byte-wise by the scanner, and any unforeseen failure
  degrades to `""` — which the caller surfaces as `no_final_text` — instead of
  crashing the AgentServer mid-turn.
  """
  @spec reply_text(binary()) :: String.t()
  def reply_text(buffer) when is_binary(buffer) do
    buffer
    |> segments()
    |> Enum.flat_map(&segment_text/1)
    |> Enum.join("\n")
    |> clean_turn_text()
  rescue
    _ -> ""
  end

  @doc """
  Split a buffer into `{:json, map}` and `{:raw, text}` segments. Top-level
  JSON objects are found with a depth/string-aware scan (the buffer is
  CONCATENATED objects — `}{"` boundaries — not a JSON array, and object
  contents may contain braces inside strings). An undecodable `{...}` span is
  kept as raw text rather than dropped. Public for tests.
  """
  @spec segments(String.t()) :: [{:json, map()} | {:raw, String.t()}]
  def segments(buffer) do
    scan(buffer, [], "")
  end

  # Byte-wise on purpose: the buffer may contain invalid UTF-8 (raw backends,
  # binary output). All the scanner compares are ASCII bytes ({ } " \), which
  # never appear inside multi-byte UTF-8 sequences, so byte matching is both
  # total and correct.

  defp scan("", acc, raw), do: Enum.reverse(flush_raw(acc, raw))

  defp scan(<<"{", _::binary>> = rest, acc, raw) do
    case take_object(rest, 0, false, false, "") do
      {:ok, object, remainder} ->
        seg =
          case Jason.decode(object) do
            {:ok, map} when is_map(map) -> {:json, map}
            _ -> {:raw, object}
          end

        scan(remainder, [seg | flush_raw(acc, raw)], "")

      :incomplete ->
        # Unbalanced braces to end-of-buffer (e.g. a truncated final chunk) —
        # keep the tail as raw text so nothing is silently dropped.
        Enum.reverse(flush_raw(flush_raw(acc, raw), rest))
    end
  end

  defp scan(<<ch, rest::binary>>, acc, raw),
    do: scan(rest, acc, raw <> <<ch>>)

  defp flush_raw(acc, ""), do: acc
  defp flush_raw(acc, raw), do: [{:raw, raw} | acc]

  # take_object(buffer, depth, in_string?, escaped?, taken)
  defp take_object("", _depth, _in_s, _esc, _taken), do: :incomplete

  defp take_object(<<ch, rest::binary>>, depth, in_s, esc, taken) do
    taken = taken <> <<ch>>

    cond do
      esc -> take_object(rest, depth, in_s, false, taken)
      in_s and ch == ?\\ -> take_object(rest, depth, true, true, taken)
      in_s and ch == ?" -> take_object(rest, depth, false, false, taken)
      in_s -> take_object(rest, depth, true, false, taken)
      ch == ?" -> take_object(rest, depth, true, false, taken)
      ch == ?{ -> take_object(rest, depth + 1, false, false, taken)
      ch == ?} and depth == 1 -> {:ok, taken, rest}
      ch == ?} -> take_object(rest, depth - 1, false, false, taken)
      true -> take_object(rest, depth, false, false, taken)
    end
  end

  # Harness stdout lines. Everything else from the wrapper is mechanics:
  # "log" (stderr diagnostics), "send"/"broadcast" (routed separately),
  # "status"/"exit"/"error" (lifecycle).
  defp segment_text({:json, %{"type" => "output", "content" => content}})
       when is_binary(content),
       do: [content]

  defp segment_text({:json, _}), do: []
  defp segment_text({:raw, text}), do: [text]

  defp clean_turn_text(text) do
    text
    |> String.replace("<<TURN_COMPLETE>>", "")
    |> String.trim()
    |> strip_prompt()
    |> String.trim()
  end

  # The harness prints its input prompt as "> " with no trailing newline, so it
  # is consumed at the START of the NEXT turn's first output line ("> From
  # https://..."). Exactly one pending prompt can be glued there — strip exactly
  # one, from the head of the turn text only, so a reply that legitimately
  # begins with a markdown "> quote" survives ("> > quote" → "> quote").
  defp strip_prompt("> " <> rest), do: rest
  defp strip_prompt(">"), do: ""
  defp strip_prompt(text), do: text
end
