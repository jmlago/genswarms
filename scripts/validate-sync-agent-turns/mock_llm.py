#!/usr/bin/env python3
"""Scripted OpenAI-compatible endpoint for validating the real subzeroclaw
binary against the genswarms sync-agent-turns branch.

Behavior (per request, decided from the conversation it receives):
  - no tool result yet -> finish_reason "tool_calls": run `swarm-msg ask` of
    the browse404 object (THE inline synchronous call under test)
  - tool result present -> finish_reason "stop": final text derived from the
    ACTUAL envelope content the harness fed back (proves the result arrived
    inline, typed, in the same turn)
"""
import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

WS = sys.argv[1]
SWARM_MSG = sys.argv[2]
PORT = int(sys.argv[3])

ASK_CMD = (
    f"OUTBOX_DIR={WS}/.outbox ASK_REPLY_DIR={WS}/.inbox/replies "
    f"SWARM_ASK_TIMEOUT=20 {SWARM_MSG} ask browse404 "
    '\'{"action":"render","url":"https://docs.example.com/intelligent-contracts/"}\''
)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        import sys as _s
        print("HIT", file=_s.stderr, flush=True)
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        req = json.loads(body)
        msgs = req.get("messages", [])
        tool_results = [m for m in msgs if m.get("role") == "tool"]

        if not tool_results:
            msg = {
                "role": "assistant",
                "content": None,
                "tool_calls": [
                    {
                        "id": "call_1",
                        "type": "function",
                        "function": {
                            "name": "shell",
                            "arguments": json.dumps({"command": ASK_CMD}),
                        },
                    }
                ],
            }
            finish = "tool_calls"
        else:
            content = tool_results[-1].get("content", "")
            # subzeroclaw prefixes shell tool results with "[exit:N] "
            stripped = content.split("] ", 1)[1] if content.startswith("[exit:") else content
            try:
                env = json.loads(stripped)
            except (json.JSONDecodeError, TypeError):
                env = None

            if env and env.get("ok") is False and env.get("error", {}).get("code") == "http_404":
                etype = env["error"].get("type")
                text = (
                    "I tried to read the page, but it does not exist (HTTP 404, "
                    f"{etype} error) - so I am not retrying. "
                    "Tell me if you want a different page."
                )
            else:
                text = "UNEXPECTED TOOL RESULT: " + str(content)[:300]

            msg = {"role": "assistant", "content": text}
            finish = "stop"

        resp = json.dumps(
            {"choices": [{"finish_reason": finish, "message": msg}]}
        ).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(resp)))
        self.end_headers()
        self.wfile.write(resp)


HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
