# D&D Hub GM Server

Local FastAPI/WebSocket server for D&D Hub LAN sessions (`v0.7.0`). It is started automatically by `Host Game` in the Flutter desktop client. The server keeps the authoritative campaign state and ordered event history in memory for the lifetime of the GM session.

## Manual run

```bash
pip install -r server/requirements.txt
python server/run.py --campaign-id <sync-id> --campaign-name "Campaign" --gm-name "GM" --invite-token <random-token>
```

HTTP endpoints:

- `GET /health` — readiness probe and protocol version
- `GET /session` — session metadata and current authoritative state size
- `WS /ws` — D&D Hub protocol transport

Discovery:

- UDP `42817`
- request: `DNDHUB_DISCOVER_V1`

## LAN server behaviour

The LAN server provides:

- campaign snapshot import from the GM client;
- real-time `state.upsert` / `state.delete` events;
- ordered event `sequence` numbers;
- bounded event history for reconnect/replay;
- full snapshot fallback when replay is no longer available;
- duplicate command protection by command id;
- reconnect-safe replacement of a previous connection using the same `client_id`;
- campaign/entity scope validation.

The v0.7.0 server also provides authoritative Session Workspace state for:

- `session_note`;
- `session_event`;
- `session_reward`;
- `session_loot`.

GM-only game commands apply XP rewards and claim Loot atomically, updating the existing Character XP/Inventory state together with the Session context and History event. Battle start/finish events are exposed as Session Events without duplicating the existing Combat Journal.

The server is intentionally temporary. It does not replace the local SQLite database and it does not persist campaign state after the GM process exits.

The current release uses LAN/IP networking only. Wi-Fi P2P and Bluetooth transports are deferred to later versions.

## Automatic dependencies

The launcher checks the Python environment and reuses a working `server/.venv` when available. Otherwise it installs the server requirements into `server/.deps` and adds that directory to the Python module path before importing FastAPI/Uvicorn + WebSocket support.
