#!/usr/bin/env python3
"""Dashboard web Smart Home — Flask + MQTT + SSE."""
from __future__ import annotations

import argparse
import json
import sys

from flask import Flask, Response, jsonify, render_template, request

from mqtt_bridge import HomeMqttBridge

app = Flask(__name__)
bridge: HomeMqttBridge | None = None


@app.route("/")
def index():
  return render_template("home.html")


@app.route("/api/state")
def api_state():
  if not bridge:
    return jsonify({"error": "bridge not ready"}), 503
  return jsonify(bridge.snapshot())


@app.route("/api/command", methods=["POST"])
def api_command():
  if not bridge:
    return jsonify({"ok": False}), 503
  data = request.get_json(silent=True) or {}
  command = str(data.get("command", "")).strip()
  if not command:
    return jsonify({"ok": False, "error": "command required"}), 400
  ok = bridge.publish_command(command)
  return jsonify({"ok": ok, "command": command.upper()})


@app.route("/api/stream")
def api_stream():
  if not bridge:
    return jsonify({"error": "bridge not ready"}), 503

  def generate():
    yield f"data: {json.dumps({'kind': 'hello', 'payload': bridge.snapshot()})}\n\n"
    while True:
      event = bridge.poll_event(timeout=25.0)
      if event is None:
        yield ": keepalive\n\n"
        continue
      yield f"data: {json.dumps(event)}\n\n"

  return Response(generate(), mimetype="text/event-stream")


def parse_args() -> argparse.Namespace:
  p = argparse.ArgumentParser(description="Dashboard Smart Home El Jezi")
  p.add_argument("--broker", default="localhost")
  p.add_argument("--port", type=int, default=1883)
  p.add_argument("--host", default="127.0.0.1")
  p.add_argument("--web-port", type=int, default=8100)
  return p.parse_args()


def main() -> int:
  global bridge
  args = parse_args()
  bridge = HomeMqttBridge(broker=args.broker, port=args.port)
  bridge.start()
  print(f"Smart Home dashboard : http://{args.host}:{args.web_port}")
  try:
    app.run(host=args.host, port=args.web_port, debug=False, threaded=True)
  except KeyboardInterrupt:
    print("\nArret.")
  finally:
    bridge.stop()
  return 0


if __name__ == "__main__":
  sys.exit(main())
