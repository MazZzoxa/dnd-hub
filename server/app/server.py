from __future__ import annotations

import asyncio
import collections
import secrets
import time
from dataclasses import dataclass
from typing import Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect

PROTOCOL = 2
MAX_HISTORY = 500
MAX_MESSAGE_BYTES = 2 * 1024 * 1024
MAX_SNAPSHOT_ENTITIES = 10_000
SUPPORTED_ENTITIES = {
    "campaign",
    "campaign_member",
    "session",
    "character",
    "item",
    "spell",
    "ability",
    "attack",
    "note",
    "spell_slot",
    "xp_transaction",
}


@dataclass
class Client:
    websocket: WebSocket
    client_id: str
    role: str
    display_name: str
    campaign_id: str
    connected_at: float


class HubServer:
    def __init__(
        self,
        *,
        campaign_id: str,
        campaign_name: str,
        gm_name: str,
        invite_token: str,
        max_players: int = 5,
    ) -> None:
        self.campaign_id = campaign_id
        self.campaign_name = campaign_name
        self.gm_name = gm_name
        self.invite_token = invite_token
        self.max_players = max_players
        self.port = 8765
        self.clients: dict[str, Client] = {}
        self.history: collections.deque[dict[str, Any]] = collections.deque(maxlen=MAX_HISTORY)
        self.state: dict[tuple[str, str], dict[str, Any]] = {}
        self.sequence = 0
        self._seen_commands: dict[str, collections.deque[str]] = collections.defaultdict(
            lambda: collections.deque(maxlen=256)
        )
        self._lock = asyncio.Lock()

    @property
    def player_count(self) -> int:
        return sum(1 for c in self.clients.values() if c.role == "player")

    def advertisement(self, host: str) -> dict[str, Any]:
        return {
            "protocol": PROTOCOL,
            "service": "DND_HUB",
            "host": host,
            "port": self.port,
            "campaign_id": self.campaign_id,
            "campaign_name": self.campaign_name,
            "gm_name": self.gm_name,
            "players": self.player_count,
            "max_players": self.max_players,
            "invite_token": self.invite_token,
        }

    async def connect(
        self,
        websocket: WebSocket,
        client_id: str,
        role: str,
        display_name: str,
        campaign_id: str,
    ) -> Client:
        if not client_id or len(client_id) > 128:
            raise ValueError("invalid client_id")
        if campaign_id != self.campaign_id:
            raise ValueError("campaign mismatch")
        role = "gm" if role == "gm" else "player"

        existing = self.clients.get(client_id)
        if existing is not None:
            # A reconnect may arrive before the old WebSocket gets its close
            # callback. Replace the connection atomically; the old finally block
            # is guarded in disconnect() so it cannot remove the new client.
            if existing.role != role:
                raise ValueError("client role mismatch")
            try:
                await existing.websocket.close(code=1012, reason="replaced by reconnect")
            except Exception:
                pass
            self.clients.pop(client_id, None)

        if role == "gm" and any(c.role == "gm" for c in self.clients.values()):
            raise ValueError("GM is already connected")
        if role == "player" and self.player_count >= self.max_players:
            raise ValueError("player limit reached")

        client = Client(
            websocket=websocket,
            client_id=client_id,
            role=role,
            display_name=display_name.strip()[:80] or role.upper(),
            campaign_id=campaign_id,
            connected_at=time.time(),
        )
        async with self._lock:
            self.clients[client.client_id] = client
        return client

    async def disconnect(self, client: Client) -> None:
        # Never remove a newer connection that reused the same client_id.
        if self.clients.get(client.client_id) is not client:
            return
        async with self._lock:
            self.clients.pop(client.client_id, None)
        await self.broadcast_event(
            "player.left",
            {"client_id": client.client_id, "display_name": client.display_name, "role": client.role},
            include_sender=False,
        )

    def _event(self, event_type: str, payload: dict[str, Any]) -> dict[str, Any]:
        self.sequence += 1
        return {
            "protocol": PROTOCOL,
            "type": "event",
            "id": secrets.token_hex(16),
            "client_id": "server",
            "campaign_id": self.campaign_id,
            "sequence": self.sequence,
            "payload": {"event": event_type, **payload},
        }

    async def broadcast_event(
        self,
        event_type: str,
        payload: dict[str, Any],
        *,
        include_sender: bool = True,
        sender_id: str | None = None,
        record: bool = True,
    ) -> dict[str, Any]:
        event = self._event(event_type, payload)
        if record:
            self.history.append(event)
        stale: list[str] = []
        for client_id, client in list(self.clients.items()):
            if not include_sender and client_id == sender_id:
                continue
            try:
                await client.websocket.send_json(event)
            except Exception:
                stale.append(client_id)
        for client_id in stale:
            if client_id in self.clients:
                self.clients.pop(client_id, None)
        return event

    async def send_error(self, client: Client, message: str, command_id: str = "") -> None:
        await client.websocket.send_json(
            {
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": self.sequence,
                "payload": {"event": "error", "message": message, "command_id": command_id},
            }
        )

    async def send_welcome(self, client: Client) -> None:
        await client.websocket.send_json(
            {
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": self.sequence,
                "payload": {
                    "event": "session.ready",
                    "campaign_name": self.campaign_name,
                    "campaign_id": self.campaign_id,
                    "gm_name": self.gm_name,
                    "players": [
                        {"client_id": c.client_id, "display_name": c.display_name, "role": c.role}
                        for c in self.clients.values()
                    ],
                },
            }
        )

    async def send_snapshot(self, client: Client, *, record: bool = True) -> None:
        entities = [
            {"entity": entity, "data": dict(data)}
            for (entity, _sync_id), data in self.state.items()
        ]
        event = self._event("state.snapshot", {"entities": entities})
        if record:
            self.history.append(event)
        await client.websocket.send_json(event)

    def _state_entry_belongs_to_campaign(
        self, entity: str, data: dict[str, Any]
    ) -> bool:
        if entity == "campaign":
            return str(data.get("sync_id", "")) == self.campaign_id
        if entity in {"campaign_member", "session"}:
            return str(data.get("campaign_sync_id", "")) == self.campaign_id
        character_sync_id = str(data.get("character_sync_id", ""))
        if entity == "character":
            character_sync_id = str(data.get("sync_id", ""))
        if not character_sync_id:
            return False
        return any(
            member_entity == "campaign_member"
            and member_data.get("campaign_sync_id") == self.campaign_id
            and member_data.get("linked_character_sync_id") == character_sync_id
            for (member_entity, _), member_data in self.state.items()
        )

    def _delete_state_entry(self, entity: str, sync_id: str) -> None:
        self.state.pop((entity, sync_id), None)
        if entity == "campaign":
            linked_characters = {
                str(data.get("linked_character_sync_id"))
                for (kind, _), data in self.state.items()
                if kind == "campaign_member"
                and data.get("campaign_sync_id") == sync_id
                and data.get("linked_character_sync_id")
            }
            for key, data in list(self.state.items()):
                kind, _ = key
                if kind in {"campaign_member", "session"} and data.get("campaign_sync_id") == sync_id:
                    self.state.pop(key, None)
                elif kind == "character" and str(data.get("sync_id")) in linked_characters:
                    self.state.pop(key, None)
                elif kind in {
                    "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction"
                } and data.get("character_sync_id") in linked_characters:
                    self.state.pop(key, None)
        elif entity == "character":
            for key, data in list(self.state.items()):
                kind, _ = key
                if kind == "campaign_member" and data.get("linked_character_sync_id") == sync_id:
                    # Match the local SQLite FK semantics: deleting a character
                    # removes its character data but leaves the campaign member
                    # present, with no linked character.
                    data["linked_character_sync_id"] = None
                elif kind in {
                    "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction"
                } and data.get("character_sync_id") == sync_id:
                    self.state.pop(key, None)

    def _player_member(self, client: Client) -> tuple[tuple[str, str], dict[str, Any]] | None:
        for key, data in self.state.items():
            entity, _ = key
            if entity != "campaign_member":
                continue
            if data.get("campaign_sync_id") != self.campaign_id:
                continue
            if data.get("client_id") == client.client_id and data.get("role") == "player":
                return key, data
        return None

    def _player_character_sync_ids(self, client: Client) -> set[str]:
        member = self._player_member(client)
        if member is None:
            return set()
        linked = str(member[1].get("linked_character_sync_id") or "").strip()
        return {linked} if linked else set()

    def _remove_member_state(self, member_sync_id: str) -> list[tuple[str, str]]:
        removed: list[tuple[str, str]] = []
        member_key = ("campaign_member", member_sync_id)
        member = self.state.get(member_key)
        if member is None:
            return removed

        linked_character = str(member.get("linked_character_sync_id") or "").strip()
        removed.append(member_key)
        self.state.pop(member_key, None)

        if linked_character:
            character_key = ("character", linked_character)
            if character_key in self.state:
                removed.append(character_key)
                self.state.pop(character_key, None)
            for key, data in list(self.state.items()):
                entity, _ = key
                if entity in {
                    "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction"
                } and data.get("character_sync_id") == linked_character:
                    removed.append(key)
                    self.state.pop(key, None)
        return removed

    def _player_can_mutate(self, client: Client, entity: str, data: dict[str, Any]) -> bool:
        if client.role == "gm":
            return True
        if client.role != "player":
            return False
        if entity not in {"character", "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction"}:
            return False
        allowed = self._player_character_sync_ids(client)
        if not allowed:
            return False
        character_sync_id = str(data.get("character_sync_id") or "")
        if entity == "character":
            character_sync_id = str(data.get("sync_id") or "")
        return character_sync_id in allowed

    async def handle_command(self, client: Client, message: dict[str, Any]) -> None:
        if message.get("protocol") != PROTOCOL or message.get("type") != "command":
            await self.send_error(client, "Unsupported protocol message")
            return
        command_id = str(message.get("id", ""))[:128]
        payload = message.get("payload")
        if not command_id or not isinstance(payload, dict):
            await self.send_error(client, "Invalid command envelope", command_id)
            return
        command = str(payload.get("command", ""))[:80]
        if message.get("campaign_id") != self.campaign_id:
            await self.send_error(client, "Campaign mismatch", command_id)
            return
        if command_id in self._seen_commands[client.client_id]:
            await client.websocket.send_json(
                {
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": self.sequence,
                    "payload": {"event": "ack", "command_id": command_id, "duplicate": True},
                }
            )
            return
        self._seen_commands[client.client_id].append(command_id)

        if command == "ping":
            await client.websocket.send_json(
                {
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": self.sequence,
                    "payload": {"event": "pong", "command_id": command_id},
                }
            )
            return

        if command == "resume":
            try:
                last_sequence = max(0, int(payload.get("last_sequence", 0) or 0))
            except (TypeError, ValueError):
                await self.send_error(client, "Invalid resume sequence", command_id)
                return
            await self._resume(client, last_sequence)
            return

        if command == "member.leave":
            if client.role != "player":
                await self.send_error(client, "Only a player can leave the campaign", command_id)
                return
            member = self._player_member(client)
            member_sync_id = str(payload.get("member_sync_id", "")).strip()
            if member is None or member[0][1] != member_sync_id:
                await self.send_error(client, "Player membership was not found", command_id)
                return

            removed = self._remove_member_state(member_sync_id)
            # Other connected clients remove the membership from their local campaign
            # view. The leaving player's local member row is intentionally left alone
            # until the acknowledged command is completed; this keeps the local
            # character intact and lets CampaignProvider remove only the membership.
            await self.broadcast_event(
                "state.delete",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "entity": "campaign_member",
                    "sync_id": member_sync_id,
                },
                include_sender=False,
                sender_id=client.client_id,
            )
            await self.broadcast_event(
                "player.left",
                {
                    "client_id": client.client_id,
                    "display_name": client.display_name,
                    "role": client.role,
                },
                include_sender=False,
                sender_id=client.client_id,
            )
            await client.websocket.send_json(
                {
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": self.sequence,
                    "payload": {
                        "event": "ack",
                        "command_id": command_id,
                        "left": True,
                        "removed_entities": len(removed),
                    },
                }
            )
            return

        if command == "snapshot.publish":
            if client.role != "gm":
                await self.send_error(client, "Only GM can publish an authoritative snapshot", command_id)
                return
            raw_entities = payload.get("entities")
            if not isinstance(raw_entities, list) or len(raw_entities) > MAX_SNAPSHOT_ENTITIES:
                await self.send_error(client, "Invalid snapshot", command_id)
                return
            new_state: dict[tuple[str, str], dict[str, Any]] = {}
            try:
                for raw in raw_entities:
                    if not isinstance(raw, dict):
                        raise ValueError("invalid snapshot entity")
                    entity = str(raw.get("entity", ""))
                    data = raw.get("data")
                    if entity not in SUPPORTED_ENTITIES or not isinstance(data, dict):
                        raise ValueError("invalid snapshot entity")
                    sync_id = str(data.get("sync_id", "")).strip()
                    if not sync_id:
                        raise ValueError("snapshot entity has no sync_id")
                    candidate = dict(data)
                    candidate.pop("id", None)
                    new_state[(entity, sync_id)] = candidate
                campaign = new_state.get(("campaign", self.campaign_id))
                if campaign is None:
                    raise ValueError("snapshot does not contain the hosted campaign")
                linked_characters = {
                    str(candidate.get("linked_character_sync_id"))
                    for (entity_name, _), candidate in new_state.items()
                    if entity_name == "campaign_member"
                    and candidate.get("campaign_sync_id") == self.campaign_id
                    and candidate.get("linked_character_sync_id")
                }
                for (entity_name, sync_key), candidate in new_state.items():
                    if entity_name == "campaign" and sync_key != self.campaign_id:
                        raise ValueError("snapshot contains another campaign")
                    if entity_name in {"campaign_member", "session"} and candidate.get("campaign_sync_id") != self.campaign_id:
                        raise ValueError("snapshot contains another campaign")
                    if entity_name == "character" and sync_key not in linked_characters:
                        raise ValueError("snapshot contains an unlinked character")
                    if entity_name in {"item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction"} and candidate.get("character_sync_id") not in linked_characters:
                        raise ValueError("snapshot contains an entity outside the hosted campaign")
            except ValueError as exc:
                await self.send_error(client, str(exc), command_id)
                return

            self.state = new_state
            event = await self.broadcast_event(
                "state.snapshot",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "entities": [
                        {"entity": entity, "data": dict(data)}
                        for (entity, _sync_id), data in self.state.items()
                    ],
                },
                include_sender=False,
                sender_id=client.client_id,
            )
            await client.websocket.send_json(
                {
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": event["sequence"],
                    "payload": {"event": "ack", "command_id": command_id},
                }
            )
            return

        if command == "member.link_character":
            if client.role != "player":
                await self.send_error(client, "Only a player can link their own character", command_id)
                return
            member = self._player_member(client)
            if member is None:
                await self.send_error(client, "Player membership was not found", command_id)
                return
            member_key, member_data = member
            member_sync_id = str(payload.get("member_sync_id", "")).strip()
            character = payload.get("character")
            if member_sync_id != member_key[1] or not isinstance(character, dict):
                await self.send_error(client, "Invalid player character link", command_id)
                return
            character_data = dict(character)
            character_sync_id = str(character_data.get("sync_id", "")).strip()
            if not character_sync_id:
                await self.send_error(client, "Character requires sync_id", command_id)
                return
            if "bio_image" in character_data:
                character_data.pop("bio_image", None)

            existing_link = None
            for (entity_name, sync_key), candidate in self.state.items():
                if entity_name == "campaign_member" and candidate.get("linked_character_sync_id") == character_sync_id and sync_key != member_key[1]:
                    existing_link = sync_key
                    break
            if existing_link is not None:
                await self.send_error(client, "Character is already linked to another campaign member", command_id)
                return

            member_data = dict(member_data)
            member_data["linked_character_sync_id"] = character_sync_id
            self.state[member_key] = member_data
            self.state[("character", character_sync_id)] = character_data

            first = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "character",
                    "data": character_data,
                },
                include_sender=True,
                sender_id=client.client_id,
            )
            second = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "campaign_member",
                    "data": member_data,
                },
                include_sender=True,
                sender_id=client.client_id,
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": second["sequence"],
                "payload": {"event": "ack", "command_id": command_id, "linked": True, "character_sequence": first["sequence"]},
            })
            return

        if command in {"state.upsert", "state.delete"}:
            if client.role not in {"player", "gm"}:
                await self.send_error(client, "Insufficient permissions", command_id)
                return
            entity = str(payload.get("entity", ""))
            if entity not in SUPPORTED_ENTITIES:
                await self.send_error(client, "Unsupported sync entity", command_id)
                return

            if command == "state.upsert":
                raw_data = payload.get("data")
                if not isinstance(raw_data, dict):
                    await self.send_error(client, "Invalid state payload", command_id)
                    return
                data = dict(raw_data)
                sync_id = str(data.get("sync_id", "")).strip()
                if not sync_id:
                    await self.send_error(client, "State entity requires sync_id", command_id)
                    return
                if entity == "character" and "bio_image" in data:
                    await self.send_error(client, "Binary character images are not part of realtime sync", command_id)
                    return
                if not self._player_can_mutate(client, entity, data):
                    await self.send_error(client, "Player may only modify their linked character", command_id)
                    return
                if not self._state_entry_belongs_to_campaign(entity, data):
                    await self.send_error(client, "State entity is outside the hosted campaign", command_id)
                    return
                self.state[(entity, sync_id)] = data
                event = await self.broadcast_event(
                    "state.upsert",
                    {
                        "command_id": command_id,
                        "origin_client_id": client.client_id,
                        "origin_display_name": client.display_name,
                        "entity": entity,
                        "data": data,
                    },
                    include_sender=True,
                    sender_id=client.client_id,
                )
            else:
                sync_id = str(payload.get("sync_id", "")).strip()
                if not sync_id:
                    await self.send_error(client, "Delete requires sync_id", command_id)
                    return
                current = self.state.get((entity, sync_id))
                if current is None:
                    await client.websocket.send_json({
                        "protocol": PROTOCOL,
                        "type": "event",
                        "id": secrets.token_hex(16),
                        "client_id": "server",
                        "campaign_id": self.campaign_id,
                        "sequence": self.sequence,
                        "payload": {"event": "ack", "command_id": command_id, "not_found": True},
                    })
                    return
                if not self._state_entry_belongs_to_campaign(entity, current):
                    await self.send_error(client, "State entity is outside the hosted campaign", command_id)
                    return
                if not self._player_can_mutate(client, entity, current):
                    await self.send_error(client, "Player may only modify their linked character", command_id)
                    return
                self._delete_state_entry(entity, sync_id)
                event = await self.broadcast_event(
                    "state.delete",
                    {
                        "command_id": command_id,
                        "origin_client_id": client.client_id,
                        "entity": entity,
                        "sync_id": sync_id,
                    },
                    include_sender=True,
                    sender_id=client.client_id,
                )

            await client.websocket.send_json(
                {
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": event["sequence"],
                    "payload": {"event": "ack", "command_id": command_id},
                }
            )
            return

        await self.send_error(client, f"Unknown command: {command}", command_id)

    async def _resume(self, client: Client, last_sequence: int) -> None:
        if last_sequence >= self.sequence:
            return
        if not self.history:
            await self.send_snapshot(client)
            return
        oldest = self.history[0]["sequence"]
        if last_sequence < oldest - 1:
            await self.send_snapshot(client)
            return
        for event in self.history:
            if event["sequence"] > last_sequence:
                await client.websocket.send_json(event)


def build_app(hub: HubServer, *, port: int) -> FastAPI:
    hub.port = port
    app = FastAPI(title="D&D Hub GM Server", version="0.5.0")

    @app.get("/health")
    async def health() -> dict[str, Any]:
        return {"ok": True, "protocol": PROTOCOL, "campaign_id": hub.campaign_id}

    @app.get("/session")
    async def session() -> dict[str, Any]:
        return {
            "protocol": PROTOCOL,
            "campaign_id": hub.campaign_id,
            "campaign_name": hub.campaign_name,
            "gm_name": hub.gm_name,
            "players": hub.player_count,
            "max_players": hub.max_players,
            "state_entities": len(hub.state),
            "sequence": hub.sequence,
        }

    @app.websocket("/ws")
    async def websocket_endpoint(websocket: WebSocket) -> None:
        await websocket.accept()
        query = websocket.query_params
        token = query.get("token", "")
        if not secrets.compare_digest(token, hub.invite_token):
            await websocket.close(code=1008, reason="invalid invite token")
            return
        client: Client | None = None
        try:
            client = await hub.connect(
                websocket,
                query.get("client_id", ""),
                query.get("role", "player"),
                query.get("display_name", "Player"),
                query.get("campaign_id", ""),
            )
            await hub.send_welcome(client)
            if hub.state:
                await hub.send_snapshot(client)
            await hub.broadcast_event(
                "player.joined",
                {"client_id": client.client_id, "display_name": client.display_name, "role": client.role},
                include_sender=False,
                sender_id=client.client_id,
            )
            while True:
                raw = await websocket.receive_text()
                if len(raw.encode("utf-8")) > MAX_MESSAGE_BYTES:
                    await hub.send_error(client, "Message too large")
                    continue
                import json

                try:
                    message = json.loads(raw)
                except json.JSONDecodeError:
                    await hub.send_error(client, "Invalid JSON")
                    continue
                await hub.handle_command(client, message)
        except WebSocketDisconnect:
            pass
        except Exception as exc:
            if client is not None:
                try:
                    await hub.send_error(client, str(exc)[:200])
                except Exception:
                    pass
        finally:
            if client is not None:
                await hub.disconnect(client)

    return app
