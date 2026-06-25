#!/usr/bin/env python3
"""Dashboard web Smart Home — Flask + MQTT + SSE."""
from __future__ import annotations

import argparse
import json
import sys

from flask import Flask, Response, jsonify, render_template, request

from mqtt_bridge import HomeMqttBridge
from demo_data import demo_state_dict, load_zones

app = Flask(__name__)
bridge: HomeMqttBridge | None = None


def _effective_state() -> dict:
  if not bridge:
    return demo_state_dict()
  snap = bridge.snapshot()
  if snap.get("last_telemetry") is None:
    demo = demo_state_dict()
    demo["mqtt_connected"] = snap.get("mqtt_connected", False)
    demo["broker"] = snap.get("broker", "localhost")
    demo["port"] = snap.get("port", 1883)
    return demo
  return snap


@app.route("/")
def index():
  return render_template("home.html")


@app.route("/api/state")
def api_state():
  return jsonify(_effective_state())


@app.route("/api/zones")
def api_zones():
  return jsonify(load_zones())


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
    yield f"data: {json.dumps({'kind': 'hello', 'payload': _effective_state()})}\n\n"
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
