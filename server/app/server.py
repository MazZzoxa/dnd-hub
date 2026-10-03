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
    "battle",
    "battle_turn",
    "battle_action_request",
    "battle_log_entry",
    "character",
    "item",
    "spell",
    "ability",
    "attack",
    "note",
    "spell_slot",
    "xp_transaction",
    "session_note",
    "session_event",
    "session_reward",
    "session_loot",
    "custom_action",
    "character_condition",
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
        recent_log_keys: dict[str, list[tuple[str, str]]] = {}
        for key, data in self.state.items():
            if key[0] != "battle_log_entry":
                continue
            battle_sync_id = str(data.get("battle_sync_id", "")).strip()
            if battle_sync_id:
                recent_log_keys.setdefault(battle_sync_id, []).append(key)

        # Journal is authoritative and append-only on the server, but reconnect
        # snapshots only need the recent workspace context. Keep at most 100
        # log entries per active/completed battle in state insertion order.
        allowed_recent_logs: set[tuple[str, str]] = set()
        for keys in recent_log_keys.values():
            allowed_recent_logs.update(keys[-100:])

        entities = []
        for key, data in self.state.items():
            if key[0] == "battle_log_entry" and key not in allowed_recent_logs:
                continue
            entities.append({"entity": key[0], "data": dict(data)})

        event = self._event("state.snapshot", {"entities": entities})
        if record:
            self.history.append(event)
        await client.websocket.send_json(event)

    def _state_entry_belongs_to_campaign(
        self, entity: str, data: dict[str, Any]
    ) -> bool:
        if entity == "campaign":
            return str(data.get("sync_id", "")) == self.campaign_id
        if entity in {"campaign_member", "session", "battle"}:
            return str(data.get("campaign_sync_id", "")) == self.campaign_id
        if entity in {"session_note", "session_event", "session_reward", "session_loot"}:
            session_sync_id = str(data.get("session_sync_id", "")).strip()
            session = self._session_by_sync_id(session_sync_id)
            return session is not None and session[1].get("campaign_sync_id") == self.campaign_id
        if entity in {"battle_turn", "battle_action_request", "battle_log_entry"}:
            battle_sync_id = str(data.get("battle_sync_id", "")).strip()
            battle = self.state.get(("battle", battle_sync_id))
            return battle is not None and battle.get("campaign_sync_id") == self.campaign_id
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
            session_sync_ids = {
                str(data.get("sync_id"))
                for (kind, _), data in self.state.items()
                if kind == "session" and data.get("campaign_sync_id") == sync_id
            }
            battle_sync_ids = {
                str(data.get("sync_id"))
                for (kind, _), data in self.state.items()
                if kind == "battle" and data.get("campaign_sync_id") == sync_id
            }
            for key, data in list(self.state.items()):
                kind, _ = key
                if kind in {"campaign_member", "session", "battle"} and data.get("campaign_sync_id") == sync_id:
                    self.state.pop(key, None)
                elif kind in {"session_note", "session_event", "session_reward", "session_loot"} and data.get("session_sync_id") in session_sync_ids:
                    self.state.pop(key, None)
                elif kind in {"battle_turn", "battle_action_request", "battle_log_entry"} and data.get("battle_sync_id") in battle_sync_ids:
                    self.state.pop(key, None)
                elif kind == "character" and str(data.get("sync_id")) in linked_characters:
                    self.state.pop(key, None)
                elif kind in {
                    "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction", "custom_action", "character_condition"
                } and data.get("character_sync_id") in linked_characters:
                    self.state.pop(key, None)
        elif entity == "session":
            for key, data in list(self.state.items()):
                kind, _ = key
                if kind in {"session_note", "session_event", "session_reward", "session_loot"} and data.get("session_sync_id") == sync_id:
                    self.state.pop(key, None)
                elif kind == "battle" and data.get("session_sync_id") == sync_id:
                    battle_sync_id = str(data.get("sync_id") or "")
                    self.state.pop(key, None)
                    for child_key, child_data in list(self.state.items()):
                        child_kind, _ = child_key
                        if child_kind in {"battle_turn", "battle_action_request", "battle_log_entry"} and child_data.get("battle_sync_id") == battle_sync_id:
                            self.state.pop(child_key, None)
        elif entity == "character":
            for key, data in list(self.state.items()):
                kind, _ = key
                if kind == "campaign_member" and data.get("linked_character_sync_id") == sync_id:
                    data["linked_character_sync_id"] = None
                elif kind in {
                    "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction", "custom_action", "character_condition"
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

    def _remove_linked_character_state(self, character_sync_id: str) -> list[tuple[str, str]]:
        removed: list[tuple[str, str]] = []
        value = character_sync_id.strip()
        if not value:
            return removed

        for key, data in list(self.state.items()):
            entity, sync_id = key
            belongs_to_character = (
                (entity == "character" and str(data.get("sync_id") or "") == value)
                or (
                    entity
                    in {
                        "item",
                        "spell",
                        "ability",
                        "attack",
                        "note",
                        "spell_slot",
                        "xp_transaction",
                        "custom_action",
                        "character_condition",
                        "session_reward",
                    }
                    and str(data.get("character_sync_id") or "") == value
                )
                or (
                    entity == "session_loot"
                    and str(data.get("claimed_by_character_sync_id") or "") == value
                )
                or (
                    entity == "battle_turn"
                    and str(data.get("character_sync_id") or "") == value
                )
                or (
                    entity == "battle_action_request"
                    and (
                        str(data.get("actor_character_sync_id") or "") == value
                        or str(data.get("target_character_sync_id") or "") == value
                    )
                )
                or (
                    entity == "battle_log_entry"
                    and (
                        str(data.get("actor_character_sync_id") or "") == value
                        or str(data.get("target_character_sync_id") or "") == value
                    )
                )
            )
            if not belongs_to_character:
                continue
            removed.append(key)
            self.state.pop(key, None)

        return removed

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
                    "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction", "custom_action", "character_condition"
                } and data.get("character_sync_id") == linked_character:
                    removed.append(key)
                    self.state.pop(key, None)
                elif entity == "battle_turn" and data.get("character_sync_id") == linked_character:
                    removed.append(key)
                    self.state.pop(key, None)
                elif entity == "battle_action_request" and data.get("actor_character_sync_id") == linked_character:
                    removed.append(key)
                    self.state.pop(key, None)
        return removed

    def _player_can_mutate(self, client: Client, entity: str, data: dict[str, Any]) -> bool:
        if client.role == "gm":
            return True
        if client.role != "player":
            return False
        if entity not in {"character", "item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction", "custom_action"}:
            return False
        allowed = self._player_character_sync_ids(client)
        if not allowed:
            return False
        character_sync_id = str(data.get("character_sync_id") or "")
        if entity == "character":
            character_sync_id = str(data.get("sync_id") or "")
        return character_sync_id in allowed

    def _active_battle(self) -> tuple[tuple[str, str], dict[str, Any]] | None:
        for key, data in self.state.items():
            if key[0] != "battle":
                continue
            if data.get("campaign_sync_id") != self.campaign_id:
                continue
            if data.get("status") == "active":
                return key, data
        return None

    def _session_by_sync_id(self, session_sync_id: str) -> tuple[tuple[str, str], dict[str, Any]] | None:
        value = session_sync_id.strip()
        if not value:
            return None
        for key, data in self.state.items():
            if key[0] != "session":
                continue
            if key[1] == value and data.get("campaign_sync_id") == self.campaign_id:
                return key, data
        return None

    def _make_session_event_data(
        self,
        *,
        session_sync_id: str,
        event_type: str,
        title: str,
        description: str = "",
        metadata: dict[str, Any] | None = None,
        created_by: str = "server",
    ) -> dict[str, Any]:
        sync_id = secrets.token_hex(16)
        data = {
            "sync_id": sync_id,
            "session_sync_id": session_sync_id,
            "type": event_type,
            "title": title,
            "description": description,
            "metadata": dict(metadata or {}),
            "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
            "created_by": created_by,
        }
        self.state[("session_event", sync_id)] = data
        return data

    async def _append_session_event(
        self,
        *,
        session_sync_id: str,
        event_type: str,
        title: str,
        description: str = "",
        metadata: dict[str, Any] | None = None,
        created_by: str = "server",
    ) -> dict[str, Any]:
        data = self._make_session_event_data(
            session_sync_id=session_sync_id,
            event_type=event_type,
            title=title,
            description=description,
            metadata=metadata,
            created_by=created_by,
        )
        return await self.broadcast_event(
            "state.upsert",
            {
                "origin_client_id": "server",
                "origin_display_name": created_by,
                "entity": "session_event",
                "data": dict(data),
            },
        )

    @staticmethod
    def _level_for_xp(xp: int) -> int:
        thresholds = (0, 300, 900, 2700, 6500, 14000, 23000, 34000, 48000, 64000, 85000, 100000, 120000, 140000, 165000, 195000, 225000, 265000, 305000, 355000)
        safe_xp = max(0, xp)
        for index in range(len(thresholds) - 1, -1, -1):
            if safe_xp >= thresholds[index]:
                return index + 1
        return 1

    def _character_for_campaign(self, character_sync_id: str) -> tuple[tuple[str, str], dict[str, Any]] | None:
        value = character_sync_id.strip()
        if not value:
            return None
        item = self.state.get(("character", value))
        if item is None:
            return None
        if not self._state_entry_belongs_to_campaign("character", item):
            return None
        return ("character", value), item

    def _battle_projection(self, battle: dict[str, Any]) -> list[dict[str, Any]]:
        projections: list[dict[str, Any]] = []
        linked_clients: dict[str, str] = {}
        for (entity, _sync_id), member in self.state.items():
            if entity != "campaign_member" or member.get("campaign_sync_id") != self.campaign_id:
                continue
            linked = str(member.get("linked_character_sync_id") or "").strip()
            if linked:
                linked_clients[linked] = str(member.get("client_id") or "")

        for character_sync_id, player_client_id in linked_clients.items():
            character = self.state.get(("character", character_sync_id))
            if character is None:
                continue
            projections.append({
                "character_sync_id": character_sync_id,
                "name": str(character.get("name") or "Character"),
                "hp": max(0, int(character.get("hp", 0) or 0)),
                "max_hp": max(0, int(character.get("max_hp", 0) or 0)),
                "temporary_hp": max(0, int(character.get("temporary_hp", 0) or 0)),
                "armor_class": max(0, int(character.get("armor_class", 0) or 0)),
                "initiative": int(character.get("initiative", 0) or 0),
                "life_state": str(character.get("life_state") or "normal"),
                "player_client_id": player_client_id,
                "conditions": [
                    {
                        "sync_id": condition.get("sync_id", ""),
                        "name": str(condition.get("name") or ""),
                        "description": str(condition.get("description") or ""),
                        "remaining_rounds": max(0, int(condition.get("remaining_rounds", 0) or 0)),
                    }
                    for (condition_entity, _), condition in self.state.items()
                    if condition_entity == "character_condition"
                    and condition.get("character_sync_id") == character_sync_id
                    and int(condition.get("active", 1) or 0) == 1
                ],
            })
        return projections

    async def send_battle_event(
        self,
        event_name: str,
        battle: dict[str, Any],
        *,
        extra: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "battle": dict(battle),
            "projections": self._battle_projection(battle),
        }
        if extra:
            payload.update(extra)
        return await self.broadcast_event(event_name, payload)

    def _character_loadout(self, character_sync_id: str) -> list[dict[str, Any]]:
        value = character_sync_id.strip()
        if not value:
            return []
        allowed_entities = {"attack", "spell", "ability", "item", "custom_action"}
        result: list[dict[str, Any]] = []
        for (entity, _sync_id), data in self.state.items():
            if entity not in allowed_entities:
                continue
            if str(data.get("character_sync_id") or "").strip() != value:
                continue
            result.append({"entity": entity, "data": dict(data)})
        result.sort(key=lambda item: (item["entity"], str(item["data"].get("sort_order", 0)), str(item["data"].get("name", "")).lower()))
        return result

    async def send_battle_snapshot(self, client: Client, battle: dict[str, Any]) -> None:
        event = self._event(
            "battle.snapshot",
            {
                "battle": dict(battle),
                "projections": self._battle_projection(battle),
            },
        )
        await client.websocket.send_json(event)

    def _battle_character_allowed(self, client: Client, character_sync_id: str) -> bool:
        character = self._character_for_campaign(character_sync_id)
        if character is None:
            return False
        if client.role == "gm":
            return True
        return character_sync_id in self._player_character_sync_ids(client)

    def _player_client_for_character(self, character_sync_id: str) -> Client | None:
        value = character_sync_id.strip()
        if not value:
            return None
        for candidate in self.clients.values():
            if candidate.role != "player":
                continue
            if value in self._player_character_sync_ids(candidate):
                return candidate
        return None

    def _battle_by_sync_id(self, battle_sync_id: str) -> tuple[tuple[str, str], dict[str, Any]] | None:
        value = battle_sync_id.strip()
        if not value:
            return None
        battle = self.state.get(("battle", value))
        if battle is None or battle.get("campaign_sync_id") != self.campaign_id:
            return None
        return ("battle", value), battle

    def _active_turn(self, battle_sync_id: str) -> tuple[tuple[str, str], dict[str, Any]] | None:
        for key, data in self.state.items():
            if key[0] == "battle_turn" and data.get("battle_sync_id") == battle_sync_id and data.get("status") == "active":
                return key, data
        return None

    def _next_turn_sequence(self, battle_sync_id: str) -> int:
        values = [
            int(data.get("sequence", 0) or 0)
            for (entity, _), data in self.state.items()
            if entity == "battle_turn" and data.get("battle_sync_id") == battle_sync_id
        ]
        return max(values, default=0) + 1

    def _is_linked_player_character(self, character_sync_id: str) -> bool:
        value = character_sync_id.strip()
        if not value:
            return False
        character = self._character_for_campaign(value)
        if character is None:
            return False
        return any(
            entity == "campaign_member"
            and member.get("campaign_sync_id") == self.campaign_id
            and member.get("role") == "player"
            and str(member.get("linked_character_sync_id") or "").strip() == value
            for (entity, _), member in self.state.items()
        )

    async def _publish_workspace_entity(
        self,
        event_name: str,
        entity: str,
        data: dict[str, Any],
        *,
        command_id: str = "",
        extra: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        sync_id = str(data.get("sync_id", "")).strip()
        if not sync_id:
            raise ValueError(f"{entity} requires sync_id")
        stored = dict(data)
        self.state[(entity, sync_id)] = stored
        payload: dict[str, Any] = {
            "command_id": command_id,
            "entity": entity,
            "data": stored,
        }
        if extra:
            payload.update(extra)
        return await self.broadcast_event(event_name, payload)

    async def _append_battle_log(
        self,
        battle_sync_id: str,
        entry_type: str,
        *,
        actor_character_sync_id: str = "",
        target_character_sync_id: str = "",
        target_label: str = "",
        action_sync_id: str = "",
        action_request_sync_id: str = "",
        amount: int | None = None,
        turn_sequence: int | None = None,
        metadata: dict[str, Any] | None = None,
        broadcast: bool = True,
    ) -> dict[str, Any]:
        now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
        entry = {
            "sync_id": secrets.token_hex(16),
            "battle_sync_id": battle_sync_id,
            "type": entry_type,
            "actor_character_sync_id": actor_character_sync_id,
            "target_character_sync_id": target_character_sync_id,
            "target_label": target_label,
            "action_sync_id": action_sync_id,
            "action_request_sync_id": action_request_sync_id,
            "amount": amount,
            "turn_sequence": turn_sequence,
            "metadata": dict(metadata or {}),
            "created_at": now,
        }
        if not broadcast:
            self.state[("battle_log_entry", entry["sync_id"])] = entry
            return {
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": self.sequence,
                "payload": {"event": "battle.journal.entry", "entity": "battle_log_entry", "data": entry},
            }
        return await self._publish_workspace_entity(
            "battle.journal.entry",
            "battle_log_entry",
            entry,
            extra={"battle_sync_id": battle_sync_id},
        )

    async def _send_battle_state(self, battle: dict[str, Any]) -> dict[str, Any]:
        return await self.send_battle_event("battle.state", battle)

    async def _handle_battle_turn_start(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может начать ход", command_id)
            return
        async with self._lock:
            battle_sync_id = str(payload.get("battle_sync_id", "")).strip()
            active = self._battle_by_sync_id(battle_sync_id)
            if active is None or active[1].get("status") != "active":
                await self.send_error(client, "Активный бой не найден", command_id)
                return
            character_sync_id = str(payload.get("character_sync_id", "")).strip()
            if not self._is_linked_player_character(character_sync_id):
                await self.send_error(client, "Персонаж хода должен быть привязан к игроку", command_id)
                return

            current = self._active_turn(battle_sync_id)
            if current is not None:
                current_data = dict(current[1])
                current_data["status"] = "completed"
                current_data["ended_at"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
                self.state[current[0]] = current_data
                await self._publish_workspace_entity(
                    "battle.turn.ended",
                    "battle_turn",
                    current_data,
                    command_id=command_id,
                    extra={"battle_sync_id": battle_sync_id, "current_turn": None},
                )
                await self._append_battle_log(
                    battle_sync_id,
                    "turn_ended",
                    actor_character_sync_id=current_data.get("character_sync_id", ""),
                    turn_sequence=int(current_data.get("sequence", 0) or 0),
                )

            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            turn = {
                "sync_id": secrets.token_hex(16),
                "battle_sync_id": battle_sync_id,
                "character_sync_id": character_sync_id,
                "sequence": self._next_turn_sequence(battle_sync_id),
                "status": "active",
                "started_at": now,
                "ended_at": None,
            }
            event = await self._publish_workspace_entity(
                "battle.turn.started",
                "battle_turn",
                turn,
                command_id=command_id,
                extra={"battle_sync_id": battle_sync_id, "current_turn": turn},
            )
            await self._append_battle_log(
                battle_sync_id,
                "turn_started",
                actor_character_sync_id=character_sync_id,
                turn_sequence=turn["sequence"],
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": event["sequence"],
                "payload": {"event": "ack", "command_id": command_id, "turn_sync_id": turn["sync_id"]},
            })

    async def _handle_battle_turn_end(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может завершить ход", command_id)
            return
        async with self._lock:
            battle_sync_id = str(payload.get("battle_sync_id", "")).strip()
            active = self._battle_by_sync_id(battle_sync_id)
            if active is None or active[1].get("status") != "active":
                await self.send_error(client, "Активный бой не найден", command_id)
                return
            current = self._active_turn(battle_sync_id)
            requested = str(payload.get("turn_sync_id", "")).strip()
            if current is None or (requested and requested != current[0][1]):
                await self.send_error(client, "Активный ход не найден", command_id)
                return
            turn = dict(current[1])
            turn["status"] = "completed"
            turn["ended_at"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            event = await self._publish_workspace_entity(
                "battle.turn.ended",
                "battle_turn",
                turn,
                command_id=command_id,
                extra={"battle_sync_id": battle_sync_id, "current_turn": None},
            )
            await self._append_battle_log(
                battle_sync_id,
                "turn_ended",
                actor_character_sync_id=turn.get("character_sync_id", ""),
                turn_sequence=int(turn.get("sequence", 0) or 0),
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": event["sequence"],
                "payload": {"event": "ack", "command_id": command_id, "turn_sync_id": turn["sync_id"]},
            })

    def _request_original_metadata(self, payload: dict[str, Any]) -> dict[str, Any]:
        return {
            "target_type": str(payload.get("target_type", "self")),
            "target_character_sync_id": str(payload.get("target_character_sync_id", "")),
            "target_label": str(payload.get("target_label", "")),
            "attack_total": payload.get("attack_total"),
            "effect_formula": str(payload.get("effect_formula", "")),
            "effect_type": str(payload.get("effect_type", "none")),
            "effect_total": payload.get("effect_total"),
        }

    def _action_request_belongs_to_battle(self, request_sync_id: str) -> tuple[tuple[str, str], dict[str, Any]] | None:
        value = request_sync_id.strip()
        if not value:
            return None
        request = self.state.get(("battle_action_request", value))
        if request is None:
            return None
        battle = self._battle_by_sync_id(str(request.get("battle_sync_id", "")).strip())
        if battle is None:
            return None
        return ("battle_action_request", value), request

    def _validate_target(
        self,
        target_type: str,
        target_character_sync_id: str,
        target_label: str,
        actor_character_sync_id: str,
    ) -> tuple[str, str]:
        normalized_target = target_type.strip() or "self"
        if normalized_target not in {"self", "ally", "external"}:
            raise ValueError("Unsupported target type")
        target_character_sync_id = target_character_sync_id.strip()
        target_label = target_label.strip()[:120]
        if normalized_target == "self":
            return actor_character_sync_id, ""
        if normalized_target == "ally":
            if not self._is_linked_player_character(target_character_sync_id):
                raise ValueError("Ally target is not a linked Player character")
            return target_character_sync_id, ""
        if not target_label:
            raise ValueError("External target requires a name")
        return "", target_label

    async def _handle_battle_action_submit(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "player":
            await self.send_error(client, "Только игрок может отправить действие", command_id)
            return
        async with self._lock:
            battle_sync_id = str(payload.get("battle_sync_id", "")).strip()
            active = self._battle_by_sync_id(battle_sync_id)
            if active is None or active[1].get("status") != "active":
                await self.send_error(client, "Активный бой не найден", command_id)
                return
            current = self._active_turn(battle_sync_id)
            if current is None:
                await self.send_error(client, "Сейчас не ход игрока", command_id)
                return
            actor_character_sync_id = str(payload.get("actor_character_sync_id", "")).strip()
            allowed = self._player_character_sync_ids(client)
            if actor_character_sync_id not in allowed or actor_character_sync_id != str(current[1].get("character_sync_id") or ""):
                await self.send_error(client, "Отправлять действия можно только во время своего хода", command_id)
                return

            action_name = str(payload.get("action_name", "")).strip()[:160]
            if not action_name:
                await self.send_error(client, "Необходимо указать название действия", command_id)
                return
            action_type = str(payload.get("action_type", "manual")).strip() or "manual"
            if action_type not in {"attack", "spell", "ability", "item", "manual"}:
                await self.send_error(client, "Неподдерживаемый тип действия", command_id)
                return
            try:
                target_character_sync_id, target_label = self._validate_target(
                    str(payload.get("target_type", "self")),
                    str(payload.get("target_character_sync_id", "")),
                    str(payload.get("target_label", "")),
                    actor_character_sync_id,
                )
            except ValueError as exc:
                await self.send_error(client, str(exc), command_id)
                return

            effect_type = str(payload.get("effect_type", "none")).strip() or "none"
            if effect_type not in {"none", "damage", "healing", "temporary_hp", "condition_apply", "condition_remove"}:
                await self.send_error(client, "Неподдерживаемый тип эффекта", command_id)
                return
            if effect_type in {"condition_apply", "condition_remove"} and target_type not in {"self", "ally"}:
                await self.send_error(client, "Состояние можно применить или снять только с себя или союзника", command_id)
                return
            def optional_int(key: str) -> int | None:
                raw = payload.get(key)
                if raw is None or raw == "":
                    return None
                try:
                    return int(raw)
                except (TypeError, ValueError):
                    raise ValueError(f"{key} must be an integer")

            try:
                attack_total = optional_int("attack_total")
                effect_total = optional_int("effect_total")
            except ValueError as exc:
                await self.send_error(client, str(exc), command_id)
                return
            if attack_total is not None and attack_total < 0:
                await self.send_error(client, "Результат попадания не может быть отрицательным", command_id)
                return
            if effect_total is not None and effect_total < 0:
                await self.send_error(client, "Результат эффекта не может быть отрицательным", command_id)
                return

            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            metadata = payload.get("metadata")
            metadata = dict(metadata) if isinstance(metadata, dict) else {}
            metadata.setdefault("original", self._request_original_metadata(payload))
            request = {
                "sync_id": secrets.token_hex(16),
                "battle_sync_id": battle_sync_id,
                "turn_sync_id": current[0][1],
                "turn_sequence": int(current[1].get("sequence", 0) or 0),
                "actor_character_sync_id": actor_character_sync_id,
                "action_type": action_type,
                "action_sync_id": str(payload.get("action_sync_id", "")).strip(),
                "action_name": action_name,
                "target_type": str(payload.get("target_type", "self")).strip() or "self",
                "target_character_sync_id": target_character_sync_id,
                "target_label": target_label,
                "attack_formula": str(payload.get("attack_formula", "")).strip()[:120],
                "attack_total": attack_total,
                "effect_formula": str(payload.get("effect_formula", "")).strip()[:120],
                "effect_type": effect_type,
                "effect_total": effect_total,
                "status": "pending_gm",
                "resolution_note": "",
                "metadata": metadata,
                "created_at": now,
                "resolved_at": None,
                "updated_at": now,
            }
            event = await self._publish_workspace_entity(
                "battle.action.submitted",
                "battle_action_request",
                request,
                command_id=command_id,
                extra={"battle_sync_id": battle_sync_id},
            )
            await self._append_battle_log(
                battle_sync_id,
                "action_submitted",
                actor_character_sync_id=actor_character_sync_id,
                target_character_sync_id=target_character_sync_id,
                target_label=target_label,
                action_sync_id=request["action_sync_id"],
                action_request_sync_id=request["sync_id"],
                turn_sequence=request["turn_sequence"],
                metadata={"action_name": action_name, "action_type": action_type},
            )
            if attack_total is not None:
                await self._append_battle_log(
                    battle_sync_id,
                    "attack_roll",
                    actor_character_sync_id=actor_character_sync_id,
                    target_character_sync_id=target_character_sync_id,
                    target_label=target_label,
                    action_sync_id=request["action_sync_id"],
                    action_request_sync_id=request["sync_id"],
                    amount=attack_total,
                    turn_sequence=request["turn_sequence"],
                    metadata={"formula": request["attack_formula"], "bonus": (request.get("metadata") or {}).get("attack_bonus", "")},
                )
            if effect_total is not None and effect_type != "none":
                roll_type = {"damage": "damage_roll", "healing": "healing_roll", "temporary_hp": "temporary_hp_applied"}.get(effect_type, "effect_applied")
                await self._append_battle_log(
                    battle_sync_id,
                    roll_type,
                    actor_character_sync_id=actor_character_sync_id,
                    target_character_sync_id=target_character_sync_id,
                    target_label=target_label,
                    action_sync_id=request["action_sync_id"],
                    action_request_sync_id=request["sync_id"],
                    amount=effect_total,
                    turn_sequence=request["turn_sequence"],
                    metadata={"formula": request["effect_formula"]},
                )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": event["sequence"],
                "payload": {"event": "ack", "command_id": command_id, "action_request_sync_id": request["sync_id"]},
            })

    async def _resolve_action_request(
        self,
        client: Client,
        command_id: str,
        request: dict[str, Any],
        *,
        status: str,
        note: str = "",
        modifications: dict[str, Any] | None = None,
    ) -> None:
        battle_sync_id = str(request.get("battle_sync_id", "")).strip()
        battle_ref = self._battle_by_sync_id(battle_sync_id)
        if battle_ref is None or battle_ref[1].get("status") != "active":
            await self.send_error(client, "Активный бой не найден", command_id)
            return
        current = dict(request)
        if modifications:
            for key, value in modifications.items():
                if key in {"target_type", "target_character_sync_id", "target_label", "attack_formula", "attack_total", "effect_formula", "effect_type", "effect_total", "resolution_note"}:
                    current[key] = value
            if "attack_bonus" in modifications:
                current_metadata = dict(current.get("metadata") or {})
                current_metadata["attack_bonus"] = str(modifications.get("attack_bonus", "")).strip()[:32]
                current["metadata"] = current_metadata
            target_type = str(current.get("target_type", "self"))
            actor_id = str(current.get("actor_character_sync_id", ""))
            try:
                target_character_sync_id, target_label = self._validate_target(
                    target_type,
                    str(current.get("target_character_sync_id", "")),
                    str(current.get("target_label", "")),
                    actor_id,
                )
            except ValueError as exc:
                await self.send_error(client, str(exc), command_id)
                return
            current["target_character_sync_id"] = target_character_sync_id
            current["target_label"] = target_label
            metadata = dict(current.get("metadata") or {})
            changes = dict(metadata.get("modifications") or {})
            for key in modifications:
                if key in {"target_type", "target_character_sync_id", "target_label", "attack_formula", "attack_total", "effect_formula", "effect_type", "effect_total"}:
                    before = request.get(key)
                    after = current.get(key)
                    if before != after:
                        changes[key] = {"before": before, "after": after}
            if "attack_bonus" in modifications:
                before = (request.get("metadata") or {}).get("attack_bonus", "")
                after = (current.get("metadata") or {}).get("attack_bonus", "")
                if before != after:
                    changes["attack_bonus"] = {"before": before, "after": after}
            metadata["modifications"] = changes
            current["metadata"] = metadata

        if status in {"approved", "modified"}:
            target_type = str(current.get("target_type", "self"))
            effect_type = str(current.get("effect_type", "none"))
            if effect_type not in {"none", "damage", "healing", "temporary_hp", "condition_apply", "condition_remove"}:
                await self.send_error(client, "Неподдерживаемый тип эффекта", command_id)
                return
            if effect_type in {"condition_apply", "condition_remove"} and target_type not in {"self", "ally"}:
                await self.send_error(client, "Состояние можно применить или снять только с себя или союзника", command_id)
                return
            raw_amount = current.get("effect_total")
            amount = None if raw_amount is None else int(raw_amount)
            if amount is not None and amount < 0:
                await self.send_error(client, "Результат эффекта не может быть отрицательным", command_id)
                return
            if target_type in {"self", "ally"} and effect_type in {"damage", "healing", "temporary_hp"} and amount is None:
                await self.send_error(client, "Для действий по себе или союзнику перед подтверждением нужен результат эффекта", command_id)
                return
            if effect_type == "condition_apply":
                metadata = current.get("metadata") or {}
                if not str(metadata.get("condition_name") or "").strip():
                    await self.send_error(client, "Для наложения состояния нужно название", command_id)
                    return
            if effect_type == "condition_remove":
                metadata = current.get("metadata") or {}
                if not str(metadata.get("condition_sync_id") or "").strip():
                    await self.send_error(client, "Для снятия состояния не выбрано состояние", command_id)
                    return

        now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
        current["status"] = status
        current["resolution_note"] = note[:300]
        current["resolved_at"] = now
        current["updated_at"] = now
        event_name = {
            "approved": "battle.action.approved",
            "modified": "battle.action.modified",
            "rejected": "battle.action.rejected",
        }[status]
        event = await self._publish_workspace_entity(
            event_name,
            "battle_action_request",
            current,
            command_id=command_id,
            extra={"battle_sync_id": battle_sync_id},
        )
        await self._append_battle_log(
            battle_sync_id,
            f"action_{status}",
            actor_character_sync_id=str(current.get("actor_character_sync_id", "")),
            target_character_sync_id=str(current.get("target_character_sync_id", "")),
            target_label=str(current.get("target_label", "")),
            action_sync_id=str(current.get("action_sync_id", "")),
            action_request_sync_id=str(current.get("sync_id", "")),
            turn_sequence=int(current.get("turn_sequence", 0) or 0),
            metadata={"note": note, "modifications": current.get("metadata", {}).get("modifications", {})},
        )

        if status in {"approved", "modified"}:
            target_type = str(current.get("target_type", "self"))
            effect_type = str(current.get("effect_type", "none"))
            amount = current.get("effect_total")
            target_id = str(current.get("target_character_sync_id", ""))
            if target_type in {"self", "ally"} and effect_type != "none":
                target = self._character_for_campaign(target_id)
                if target is not None:
                    updated = dict(target[1])
                    hp_before = max(0, int(updated.get("hp", 0) or 0))
                    temp_before = max(0, int(updated.get("temporary_hp", 0) or 0))
                    max_hp = max(0, int(updated.get("max_hp", 0) or 0))
                    amount_int = max(0, int(amount or 0))
                    if effect_type == "damage":
                        absorbed = min(amount_int, temp_before)
                        updated["temporary_hp"] = temp_before - absorbed
                        updated["hp"] = max(0, hp_before - (amount_int - absorbed))
                        if updated["hp"] == 0 and str(updated.get("life_state") or "normal") == "normal":
                            updated["life_state"] = "downed"
                        log_type = "damage_applied"
                        before_after = {"hp_before": hp_before, "hp_after": updated["hp"], "temporary_hp_before": temp_before, "temporary_hp_after": updated["temporary_hp"]}
                    elif effect_type == "healing":
                        updated["hp"] = min(max_hp, hp_before + amount_int)
                        log_type = "healing_applied"
                        before_after = {"hp_before": hp_before, "hp_after": updated["hp"]}
                    elif effect_type == "temporary_hp":
                        updated["temporary_hp"] = amount_int
                        log_type = "temporary_hp_applied"
                        before_after = {"temporary_hp_before": temp_before, "temporary_hp_after": updated["temporary_hp"]}
                    else:
                        updated = None
                    if updated is not None:
                        self.state[target[0]] = updated
                    if effect_type in {"damage", "healing", "temporary_hp"}:
                        await self.broadcast_event(
                            "state.upsert",
                            {
                                "command_id": command_id,
                                "origin_client_id": client.client_id,
                                "origin_display_name": client.display_name,
                                "entity": "character",
                                "data": dict(updated),
                            },
                            include_sender=True,
                            sender_id=client.client_id,
                        )
                        await self._append_battle_log(
                            battle_sync_id,
                            log_type,
                            actor_character_sync_id=str(current.get("actor_character_sync_id", "")),
                            target_character_sync_id=target_id,
                            target_label=str(current.get("target_label", "")),
                            action_sync_id=str(current.get("action_sync_id", "")),
                            action_request_sync_id=str(current.get("sync_id", "")),
                            amount=amount_int,
                            turn_sequence=int(current.get("turn_sequence", 0) or 0),
                            metadata=before_after,
                        )
                        if effect_type == "damage" and str(updated.get("life_state") or "normal") == "downed" and str(target[1].get("life_state") or "normal") != "downed":
                            await self._append_battle_log(
                                battle_sync_id, "downed", target_character_sync_id=target_id,
                                action_request_sync_id=str(current.get("sync_id", "")),
                                metadata={"previous_life_state": target[1].get("life_state", "normal"), "life_state": "downed"},
                            )
                    elif effect_type == "condition_apply":
                        metadata = dict(current.get("metadata") or {})
                        condition_name = str(metadata.get("condition_name") or "Состояние").strip()[:120]
                        condition_description = str(metadata.get("condition_description") or "").strip()[:500]
                        duration = max(0, int(metadata.get("duration_rounds", 0) or 0))
                        remaining = max(0, int(metadata.get("remaining_rounds", duration) or 0))
                        condition_sync_id = secrets.token_hex(16)
                        condition = {
                            "sync_id": condition_sync_id, "character_sync_id": target_id,
                            "name": condition_name, "description": condition_description,
                            "source_character_sync_id": str(current.get("actor_character_sync_id") or ""),
                            "source_label": str(metadata.get("source_label") or current.get("action_name") or "").strip()[:160],
                            "duration_rounds": duration, "remaining_rounds": remaining,
                            "scope": str(metadata.get("scope") or "battle"), "active": 1,
                            "metadata": metadata, "created_at": now, "updated_at": now,
                        }
                        self.state[("character_condition", condition_sync_id)] = condition
                        await self.broadcast_event("state.upsert", {
                            "command_id": command_id, "origin_client_id": client.client_id,
                            "origin_display_name": client.display_name, "entity": "character_condition", "data": dict(condition),
                        }, include_sender=True, sender_id=client.client_id)
                        await self._append_battle_log(
                            battle_sync_id, "condition_applied", actor_character_sync_id=str(current.get("actor_character_sync_id", "")),
                            target_character_sync_id=target_id, action_sync_id=str(current.get("action_sync_id", "")),
                            action_request_sync_id=str(current.get("sync_id", "")), metadata={"condition_sync_id": condition_sync_id, "name": condition_name, "remaining_rounds": remaining},
                        )
                    elif effect_type == "condition_remove":
                        condition_sync_id = str((current.get("metadata") or {}).get("condition_sync_id") or "").strip()
                        condition = self.state.get(("character_condition", condition_sync_id)) if condition_sync_id else None
                        if condition is not None:
                            removed = dict(condition); removed["active"] = 0; removed["remaining_rounds"] = 0; removed["updated_at"] = now
                            self.state[("character_condition", condition_sync_id)] = removed
                            await self.broadcast_event("state.upsert", {
                                "command_id": command_id, "origin_client_id": client.client_id,
                                "origin_display_name": client.display_name, "entity": "character_condition", "data": dict(removed),
                            }, include_sender=True, sender_id=client.client_id)
                            await self._append_battle_log(
                                battle_sync_id, "condition_removed", actor_character_sync_id=str(current.get("actor_character_sync_id", "")),
                                target_character_sync_id=target_id, action_request_sync_id=str(current.get("sync_id", "")),
                                metadata={"condition_sync_id": condition_sync_id, "name": condition.get("name", "")},
                            )

        await self._send_battle_state(active[1] if (active := self._battle_by_sync_id(battle_sync_id)) is not None else {"sync_id": battle_sync_id})
        await client.websocket.send_json({
            "protocol": PROTOCOL,
            "type": "event",
            "id": secrets.token_hex(16),
            "client_id": "server",
            "campaign_id": self.campaign_id,
            "sequence": event["sequence"],
            "payload": {"event": "ack", "command_id": command_id, "action_request_sync_id": current["sync_id"]},
        })

    async def _handle_battle_action_resolve(self, client: Client, command_id: str, payload: dict[str, Any], *, status: str) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может обработать запрос действия", command_id)
            return
        async with self._lock:
            request_ref = self._action_request_belongs_to_battle(str(payload.get("action_request_sync_id", "")))
            if request_ref is None:
                await self.send_error(client, "Запрос действия не найден", command_id)
                return
            _key, request = request_ref
            if request.get("status") != "pending_gm":
                await self.send_error(client, "Запрос действия уже обработан", command_id)
                return
            if status == "rejected":
                await self._resolve_action_request(
                    client,
                    command_id,
                    request,
                    status="rejected",
                    note=str(payload.get("reason", "")),
                )
                return

            modifications: dict[str, Any] = {}
            raw_modifications = payload.get("modifications")
            if isinstance(raw_modifications, dict):
                for key in ("target_type", "target_character_sync_id", "target_label", "attack_formula", "attack_total", "effect_formula", "effect_type", "effect_total"):
                    if key in raw_modifications:
                        modifications[key] = raw_modifications[key]
            # Accept flat fields as well so the protocol remains easy to use
            # from simple clients and older prototypes.
            for key in ("target_type", "target_character_sync_id", "target_label", "attack_formula", "attack_total", "effect_formula", "effect_type", "effect_total"):
                if key in payload:
                    modifications[key] = payload[key]
            await self._resolve_action_request(
                client,
                command_id,
                request,
                status=status,
                note=str(payload.get("resolution_note", payload.get("note", ""))),
                modifications=modifications or None,
            )

    async def _handle_battle_start(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может начать бой", command_id)
            return

        async with self._lock:
            session_sync_id = str(payload.get("session_sync_id", "")).strip()
            session = self._session_by_sync_id(session_sync_id)
            if session is None or session[1].get("status") != "active":
                await self.send_error(client, "Для начала боя нужна активная сессия", command_id)
                return
            if self._active_battle() is not None:
                await self.send_error(client, "В этой сессии уже есть активный бой", command_id)
                return

            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            battle_name = str(payload.get("battle_name", "")).strip()[:120] or "Бой"
            battle = {
                "sync_id": secrets.token_hex(16),
                "name": battle_name,
                "campaign_sync_id": self.campaign_id,
                "session_sync_id": session_sync_id,
                "status": "active",
                "created_at": now,
                "started_at": now,
                "ended_at": None,
                "updated_at": now,
            }
            self.state[("battle", battle["sync_id"])] = battle
            session_event = self._make_session_event_data(
                session_sync_id=session_sync_id,
                event_type="battle_started",
                title=f"⚔ {battle_name}",
                metadata={"battle_sync_id": battle["sync_id"]},
                created_by=client.display_name,
            )
            event = await self.send_battle_event(
                "battle.started",
                battle,
                extra={"session_event": dict(session_event)},
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": event["sequence"],
                "payload": {
                    "event": "ack",
                    "command_id": command_id,
                    "battle_sync_id": battle["sync_id"],
                },
            })

    async def _handle_battle_end(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может завершить бой", command_id)
            return

        async with self._lock:
            battle_sync_id = str(payload.get("battle_sync_id", "")).strip()
            current = self.state.get(("battle", battle_sync_id))
            if current is None or current.get("status") != "active":
                await self.send_error(client, "Активный бой не найден", command_id)
                return

            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            battle = dict(current)
            active_turn = self._active_turn(battle_sync_id)
            if active_turn is not None:
                ended_turn = dict(active_turn[1])
                ended_turn["status"] = "completed"
                ended_turn["ended_at"] = now
                await self._publish_workspace_entity(
                    "battle.turn.ended",
                    "battle_turn",
                    ended_turn,
                    extra={"battle_sync_id": battle_sync_id, "current_turn": None},
                )
                await self._append_battle_log(
                    battle_sync_id,
                    "turn_ended",
                    actor_character_sync_id=str(ended_turn.get("character_sync_id") or ""),
                    turn_sequence=int(ended_turn.get("sequence", 0) or 0),
                )

            battle["status"] = "completed"
            battle["ended_at"] = now
            battle["updated_at"] = now
            self.state[("battle", battle_sync_id)] = battle
            session_event = self._make_session_event_data(
                session_sync_id=str(battle.get("session_sync_id") or ""),
                event_type="battle_finished",
                title=f"⚔ {str(battle.get('name') or 'Бой').strip() or 'Бой'} завершён",
                metadata={"battle_sync_id": battle_sync_id},
                created_by=client.display_name,
            )
            event = await self.send_battle_event(
                "battle.ended",
                battle,
                extra={"session_event": dict(session_event)},
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": event["sequence"],
                "payload": {
                    "event": "ack",
                    "command_id": command_id,
                    "battle_sync_id": battle_sync_id,
                },
            })

    def _command_session_sync_id(self, payload: dict[str, Any]) -> str:
        session_sync_id = str(payload.get("session_sync_id") or "").strip()
        if session_sync_id:
            if self._session_by_sync_id(session_sync_id) is None:
                raise ValueError("Сессия не найдена")
            return session_sync_id
        battle_sync_id = str(payload.get("battle_sync_id") or "").strip()
        if battle_sync_id:
            battle = self._battle_by_sync_id(battle_sync_id)
            if battle is not None:
                value = str(battle[1].get("session_sync_id") or "").strip()
                if value and self._session_by_sync_id(value) is not None:
                    return value
        return ""

    async def _broadcast_character_change(
        self,
        client: Client,
        command_id: str,
        character_key: tuple[str, str],
        character: dict[str, Any],
    ) -> dict[str, Any]:
        self.state[character_key] = dict(character)
        return await self.broadcast_event(
            "state.upsert",
            {
                "command_id": command_id,
                "origin_client_id": client.client_id,
                "origin_display_name": client.display_name,
                "entity": "character",
                "data": dict(character),
            },
            include_sender=True,
            sender_id=client.client_id,
        )

    async def _character_command_ack(
        self,
        client: Client,
        command_id: str,
        sequence: int,
        data: dict[str, Any],
    ) -> None:
        await client.websocket.send_json({
            "protocol": PROTOCOL,
            "type": "event",
            "id": secrets.token_hex(16),
            "client_id": "server",
            "campaign_id": self.campaign_id,
            "sequence": sequence,
            "payload": {"event": "ack", "command_id": command_id, **data},
        })

    async def _handle_character_hp_modify(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может менять HP другого персонажа", command_id)
            return
        async with self._lock:
            character_sync_id = str(payload.get("character_sync_id") or "").strip()
            target = self._character_for_campaign(character_sync_id)
            if target is None:
                await self.send_error(client, "Персонаж не найден", command_id)
                return
            try:
                delta = int(payload.get("delta"))
            except (TypeError, ValueError):
                await self.send_error(client, "Изменение HP должно быть целым числом", command_id)
                return
            key, character = target
            updated = dict(character)
            hp_before = max(0, int(character.get("hp", 0) or 0))
            temp_before = max(0, int(character.get("temporary_hp", 0) or 0))
            max_hp = max(0, int(character.get("max_hp", 0) or 0))
            if delta < 0:
                damage = -delta
                absorbed = min(damage, temp_before)
                updated["temporary_hp"] = temp_before - absorbed
                updated["hp"] = max(0, hp_before - (damage - absorbed))
            elif delta > 0:
                updated["hp"] = min(max_hp, hp_before + delta)
            else:
                return
            old_life = str(character.get("life_state") or "normal")
            if updated["hp"] == 0 and old_life == "normal":
                updated["life_state"] = "downed"
            sequence_event = await self._broadcast_character_change(client, command_id, key, updated)
            log_type = "damage_applied" if delta < 0 else "healing_applied"
            battle_sync_id = str(payload.get("battle_sync_id") or "").strip()
            if battle_sync_id and self._battle_by_sync_id(battle_sync_id) is not None:
                journal = await self._append_battle_log(
                    battle_sync_id, log_type,
                    target_character_sync_id=character_sync_id,
                    amount=abs(delta),
                    metadata={"hp_before": hp_before, "hp_after": updated["hp"], "temporary_hp_before": temp_before, "temporary_hp_after": updated.get("temporary_hp", 0), "source": "gm_command"},
                )
                if old_life != str(updated.get("life_state") or "normal"):
                    await self._append_battle_log(
                        battle_sync_id, "downed",
                        target_character_sync_id=character_sync_id,
                        metadata={"previous_life_state": old_life, "life_state": updated.get("life_state")},
                    )
                    journal = journal
                await self._send_battle_state(self._battle_by_sync_id(battle_sync_id)[1])
                await self._character_command_ack(client, command_id, sequence_event["sequence"], {"character": dict(updated), "battle_sync_id": battle_sync_id, "character_sequence": sequence_event["sequence"]})
                return
            session_sync_id = self._command_session_sync_id(payload)
            if session_sync_id:
                event_type = "downed" if old_life != str(updated.get("life_state") or "normal") else ("damage" if delta < 0 else "healing")
                session_event = await self._append_session_event(
                    session_sync_id=session_sync_id,
                    event_type=event_type,
                    title=("Нокаут" if event_type == "downed" else (f"Урон -{abs(delta)}" if delta < 0 else f"Лечение +{delta}")) + f" — {character.get('name') or 'Персонаж'}",
                    metadata={"character_sync_id": character_sync_id, "hp_before": hp_before, "hp_after": updated["hp"], "life_state": updated.get("life_state")},
                    created_by=client.display_name,
                )
                await self._character_command_ack(client, command_id, session_event["sequence"], {"character": dict(updated), "character_sequence": sequence_event["sequence"]})
            else:
                await self._character_command_ack(client, command_id, sequence_event["sequence"], {"character": dict(updated), "character_sequence": sequence_event["sequence"]})

    async def _handle_character_temp_hp_set(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может менять временные хиты", command_id)
            return
        async with self._lock:
            target = self._character_for_campaign(str(payload.get("character_sync_id") or "").strip())
            if target is None:
                await self.send_error(client, "Персонаж не найден", command_id); return
            try:
                amount = int(payload.get("amount"))
            except (TypeError, ValueError):
                await self.send_error(client, "Временные хиты должны быть целым числом", command_id); return
            amount = max(0, amount)
            updated = dict(target[1]); before = max(0, int(updated.get("temporary_hp", 0) or 0)); updated["temporary_hp"] = amount
            event = await self._broadcast_character_change(client, command_id, target[0], updated)
            session_sync_id = self._command_session_sync_id(payload)
            if session_sync_id:
                session_event = await self._append_session_event(
                    session_sync_id=session_sync_id,
                    event_type="temporary_hp",
                    title=f"Временные хиты {amount} — {target[1].get('name') or 'Персонаж'}",
                    metadata={"character_sync_id": target[0][1], "before": before, "after": amount},
                    created_by=client.display_name,
                )
                seq = session_event["sequence"]
            else:
                seq = event["sequence"]
            await self._character_command_ack(client, command_id, seq, {"character": dict(updated), "character_sequence": event["sequence"]})

    async def _handle_character_life_state_set(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может изменять состояние жизни персонажа", command_id)
            return
        async with self._lock:
            target = self._character_for_campaign(str(payload.get("character_sync_id") or "").strip())
            if target is None:
                await self.send_error(client, "Персонаж не найден", command_id); return
            value = str(payload.get("life_state") or payload.get("value") or "").strip().lower()
            if value not in {"normal", "downed", "dead"}:
                await self.send_error(client, "Недопустимое состояние жизни", command_id); return
            before = str(target[1].get("life_state") or "normal")
            updated = dict(target[1]); updated["life_state"] = value
            event = await self._broadcast_character_change(client, command_id, target[0], updated)
            if before == value:
                event_type = "life_state_changed"
            elif value == "dead":
                event_type = "death"
            elif before == "dead" and value in {"normal", "downed"}:
                event_type = "revived"
            elif before == "downed" and value == "normal":
                event_type = "revived"
            elif value == "downed":
                event_type = "downed"
            else:
                event_type = "life_state_changed"
            battle_sync_id = str(payload.get("battle_sync_id") or "").strip()
            battle = self._battle_by_sync_id(battle_sync_id) if battle_sync_id else None
            if battle is not None and battle[1].get("status") == "active" and before != value:
                battle_event_type = (
                    "death"
                    if value == "dead"
                    else "revived"
                    if before == "dead" and value in {"normal", "downed"}
                    else "revived"
                    if before == "downed" and value == "normal"
                    else "downed"
                    if value == "downed"
                    else "life_state_changed"
                )
                await self._append_battle_log(
                    battle_sync_id,
                    battle_event_type,
                    target_character_sync_id=target[0][1],
                    metadata={"before": before, "after": value},
                )
                await self._send_battle_state(battle[1])
            session_sync_id = self._command_session_sync_id(payload)
            # Combat state changes are recorded in Battle Mode's journal.
            # Do not create a second Session History event for the same change.
            if session_sync_id and battle is None:
                session_event = await self._append_session_event(
                    session_sync_id=session_sync_id,
                    event_type=event_type,
                    title=f"{('Смерть' if value == 'dead' else 'Воскрешение' if event_type == 'revived' else 'Нокаут' if value == 'downed' else 'Состояние жизни')} — {target[1].get('name') or 'Персонаж'}",
                    metadata={"character_sync_id": target[0][1], "before": before, "after": value},
                    created_by=client.display_name,
                )
                seq = session_event["sequence"]
            else:
                seq = event["sequence"]
            await self._character_command_ack(
                client,
                command_id,
                seq,
                {
                    "character": dict(updated),
                    "character_sequence": event["sequence"],
                    "battle_sync_id": battle_sync_id,
                },
            )

    async def _handle_character_xp_grant(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        # Keep the existing XP workflow/API but expose it under the v1.0 command name.
        await self._handle_session_reward_apply(client, command_id, {**payload, "type": "xp"})

    async def _handle_character_currency_grant(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может выдавать валюту", command_id); return
        async with self._lock:
            session_sync_id = self._command_session_sync_id(payload)
            if not session_sync_id:
                await self.send_error(client, "Для выдачи валюты нужна сессия", command_id); return
            session = self._session_by_sync_id(session_sync_id)
            if session is None or session[1].get("status") == "planned":
                await self.send_error(client, "Выдавать награды можно только во время активной сессии", command_id); return
            character_sync_id = str(payload.get("character_sync_id") or "").strip()
            target = self._character_for_campaign(character_sync_id)
            if target is None:
                await self.send_error(client, "Персонаж не найден", command_id); return
            currency = str(payload.get("currency") or "").strip().lower()
            if currency not in {"copper", "silver", "electrum", "gold", "platinum"}:
                await self.send_error(client, "Неизвестный тип валюты", command_id); return
            try: amount = int(payload.get("amount"))
            except (TypeError, ValueError):
                await self.send_error(client, "Количество валюты должно быть целым числом", command_id); return
            if amount <= 0:
                await self.send_error(client, "Количество валюты должно быть положительным", command_id); return
            character = dict(target[1]); before = max(0, int(character.get(currency, 0) or 0)); after = min(1 << 30, before + amount)
            if after == before:
                await self.send_error(client, "Валюта уже находится на максимальном значении", command_id); return
            character[currency] = after
            character_event = await self._broadcast_character_change(client, command_id, target[0], character)
            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            reward = {"sync_id": secrets.token_hex(16), "session_sync_id": session_sync_id, "character_sync_id": character_sync_id, "type": "currency", "currency": currency, "amount": amount, "reason": str(payload.get("reason") or "").strip()[:300], "level_before": int(character.get("level", 1) or 1), "level_after": int(character.get("level", 1) or 1), "created_at": now, "created_by": client.display_name}
            self.state[("session_reward", reward["sync_id"])] = reward
            reward_event = await self.broadcast_event("state.upsert", {"command_id": command_id, "origin_client_id": client.client_id, "origin_display_name": client.display_name, "entity": "session_reward", "data": dict(reward)})
            session_event = await self._append_session_event(
                session_sync_id=session_sync_id, event_type="currency_reward",
                title=f"+{amount} {currency.upper()} — {target[1].get('name') or 'Персонаж'}",
                description=reward["reason"], metadata={"reward_sync_id": reward["sync_id"], "character_sync_id": character_sync_id, "currency": currency, "amount": amount}, created_by=client.display_name,
            )
            await self._character_command_ack(client, command_id, session_event["sequence"], {"character": dict(character), "reward": dict(reward), "character_sequence": character_event["sequence"], "reward_sequence": reward_event["sequence"]})

    async def _handle_character_inspiration_grant(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может выдавать вдохновение", command_id); return
        async with self._lock:
            session_sync_id = self._command_session_sync_id(payload)
            if not session_sync_id:
                await self.send_error(client, "Для выдачи вдохновения нужна сессия", command_id); return
            session = self._session_by_sync_id(session_sync_id)
            target = self._character_for_campaign(str(payload.get("character_sync_id") or "").strip())
            if session is None or session[1].get("status") == "planned" or target is None:
                await self.send_error(client, "Персонаж или сессия не найдены", command_id); return
            if int(target[1].get("inspiration", 0) or 0) == 1 or target[1].get("inspiration") is True:
                await self.send_error(client, "У персонажа уже есть вдохновение", command_id); return
            character = dict(target[1]); character["inspiration"] = 1
            character_event = await self._broadcast_character_change(client, command_id, target[0], character)
            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            reward = {"sync_id": secrets.token_hex(16), "session_sync_id": session_sync_id, "character_sync_id": target[0][1], "type": "inspiration", "currency": "", "amount": 1, "reason": str(payload.get("reason") or "").strip()[:300], "level_before": int(character.get("level", 1) or 1), "level_after": int(character.get("level", 1) or 1), "created_at": now, "created_by": client.display_name}
            self.state[("session_reward", reward["sync_id"])] = reward
            reward_event = await self.broadcast_event("state.upsert", {"command_id": command_id, "origin_client_id": client.client_id, "origin_display_name": client.display_name, "entity": "session_reward", "data": dict(reward)})
            session_event = await self._append_session_event(
                session_sync_id=session_sync_id, event_type="inspiration_granted",
                title=f"Вдохновение — {target[1].get('name') or 'Персонаж'}", description=reward["reason"], metadata={"reward_sync_id": reward["sync_id"], "character_sync_id": target[0][1]}, created_by=client.display_name,
            )
            await self._character_command_ack(client, command_id, session_event["sequence"], {"character": dict(character), "reward": dict(reward), "character_sequence": character_event["sequence"], "reward_sequence": reward_event["sequence"]})

    async def _handle_character_condition_apply(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может накладывать состояния", command_id); return
        async with self._lock:
            character_sync_id = str(payload.get("character_sync_id") or "").strip()
            target = self._character_for_campaign(character_sync_id)
            if target is None:
                await self.send_error(client, "Персонаж не найден", command_id); return
            name = str(payload.get("name") or "").strip()[:120]
            if not name:
                await self.send_error(client, "У состояния должно быть название", command_id); return
            try: duration = max(0, int(payload.get("duration_rounds") or 0)); remaining = max(0, int(payload.get("remaining_rounds") if payload.get("remaining_rounds") is not None else duration))
            except (TypeError, ValueError):
                await self.send_error(client, "Длительность состояния должна быть целым числом", command_id); return
            scope = str(payload.get("scope") or "character").strip().lower()
            if scope not in {"character", "battle", "session"}:
                await self.send_error(client, "Недопустимая область состояния", command_id); return
            condition = {
                "sync_id": secrets.token_hex(16), "character_sync_id": character_sync_id,
                "name": name, "description": str(payload.get("description") or "").strip()[:500],
                "source_character_sync_id": str(payload.get("source_character_sync_id") or "").strip(),
                "source_label": str(payload.get("source_label") or "").strip()[:160],
                "duration_rounds": duration, "remaining_rounds": remaining, "scope": scope, "active": 1,
                "metadata": dict(payload.get("metadata") or {}),
                "created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
                "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime()),
            }
            self.state[("character_condition", condition["sync_id"])] = dict(condition)
            event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "character_condition",
                    "data": condition,
                },
            )
            battle_sync_id = str(payload.get("battle_sync_id") or "").strip()
            battle = self._battle_by_sync_id(battle_sync_id) if battle_sync_id else None
            if battle is not None and battle[1].get("status") == "active":
                await self._append_battle_log(
                    battle_sync_id,
                    "condition_applied",
                    actor_character_sync_id="",
                    target_character_sync_id=character_sync_id,
                    target_label=target[1].get("name") or "Персонаж",
                    metadata={
                        "condition_sync_id": condition["sync_id"],
                        "name": name,
                        "remaining_rounds": remaining,
                        "source_label": condition["source_label"],
                    },
                )
                await self._send_battle_state(battle[1])
            session_sync_id = self._command_session_sync_id(payload)
            # A condition applied during an active battle belongs to the
            # Battle journal, not to the general Session History feed.
            if session_sync_id and battle is None:
                session_event = await self._append_session_event(
                    session_sync_id=session_sync_id,
                    event_type="condition_applied",
                    title=f"{name} — {target[1].get('name') or 'Персонаж'}",
                    description=condition["description"],
                    metadata={"condition_sync_id": condition["sync_id"], "character_sync_id": character_sync_id},
                    created_by=client.display_name,
                )
                seq = session_event["sequence"]
            else:
                seq = event["sequence"]
            await self._character_command_ack(
                client,
                command_id,
                seq,
                {
                    "condition": dict(condition),
                    "condition_sequence": event["sequence"],
                    "battle_sync_id": battle_sync_id,
                },
            )

    async def _handle_character_condition_remove(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может снимать состояния", command_id); return
        async with self._lock:
            sync_id = str(payload.get("condition_sync_id") or payload.get("sync_id") or "").strip()
            condition = self.state.get(("character_condition", sync_id)) if sync_id else None
            if condition is None:
                await self.send_error(client, "Состояние не найдено", command_id); return
            character_sync_id = str(condition.get("character_sync_id") or "").strip()
            if self._character_for_campaign(character_sync_id) is None:
                await self.send_error(client, "Состояние не относится к кампании", command_id); return
            updated = dict(condition)
            updated["active"] = 0
            updated["remaining_rounds"] = 0
            updated["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            self.state[("character_condition", sync_id)] = dict(updated)
            event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "character_condition",
                    "data": updated,
                },
            )
            battle_sync_id = str(payload.get("battle_sync_id") or "").strip()
            battle = self._battle_by_sync_id(battle_sync_id) if battle_sync_id else None
            if battle is not None and battle[1].get("status") == "active":
                await self._append_battle_log(
                    battle_sync_id,
                    "condition_removed",
                    actor_character_sync_id="",
                    target_character_sync_id=character_sync_id,
                    target_label=self._character_for_campaign(character_sync_id)[1].get("name") or "Персонаж",
                    metadata={"condition_sync_id": sync_id, "name": condition.get("name", "")},
                )
                await self._send_battle_state(battle[1])
            session_sync_id = self._command_session_sync_id(payload)
            if session_sync_id and battle is None:
                session_event = await self._append_session_event(
                    session_sync_id=session_sync_id,
                    event_type="condition_removed",
                    title=f"{condition.get('name') or 'Состояние'} снято",
                    metadata={"condition_sync_id": sync_id, "character_sync_id": character_sync_id},
                    created_by=client.display_name,
                )
                seq = session_event["sequence"]
            else:
                seq = event["sequence"]
            await self._character_command_ack(
                client,
                command_id,
                seq,
                {"condition": dict(updated), "condition_sequence": event["sequence"], "battle_sync_id": battle_sync_id},
            )

    async def _handle_battle_character_action(
        self,
        client: Client,
        command_id: str,
        payload: dict[str, Any],
        operation: str,
    ) -> None:
        async with self._lock:
            active = self._active_battle()
            if active is None:
                await self.send_error(client, "Нет активного боя", command_id)
                return

            battle_key, battle = active
            requested_battle_id = str(payload.get("battle_sync_id", "")).strip()
            if requested_battle_id != battle_key[1]:
                await self.send_error(client, "Бой не совпадает с текущим подключением", command_id)
                return

            character_sync_id = str(payload.get("character_sync_id", "")).strip()
            character = self._character_for_campaign(character_sync_id)
            if character is None:
                await self.send_error(client, "Персонаж не относится к размещённой кампании", command_id)
                return
            if not self._battle_character_allowed(client, character_sync_id):
                await self.send_error(client, "Игрок может изменять только своего персонажа", command_id)
                return

            try:
                amount = int(payload.get("amount"))
            except (TypeError, ValueError):
                await self.send_error(client, "Значение боя должно быть целым числом", command_id)
                return
            if amount < 0:
                await self.send_error(client, "Значение боя не может быть отрицательным", command_id)
                return

            updated = dict(character[1])
            old_life = str(updated.get("life_state") or "normal")
            hp = max(0, int(updated.get("hp", 0) or 0))
            max_hp = max(0, int(updated.get("max_hp", 0) or 0))
            temporary_hp = max(0, int(updated.get("temporary_hp", 0) or 0))

            if operation == "damage":
                absorbed = min(amount, temporary_hp)
                temporary_hp -= absorbed
                hp = max(0, hp - (amount - absorbed))
            elif operation == "heal":
                hp = min(max_hp, hp + amount)
            elif operation == "temp_hp":
                temporary_hp = amount
            else:
                await self.send_error(client, "Неподдерживаемая операция боя", command_id)
                return

            updated["hp"] = hp
            updated["temporary_hp"] = temporary_hp
            if operation == "damage" and hp == 0 and old_life == "normal":
                updated["life_state"] = "downed"
            updated["sync_id"] = character_sync_id
            self.state[character[0]] = updated

            state_event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "character",
                    "data": dict(updated),
                },
                include_sender=True,
                sender_id=client.client_id,
            )
            log_type = {
                "damage": "damage_applied",
                "heal": "healing_applied",
                "temp_hp": "temporary_hp_applied",
            }[operation]
            journal_entry = await self._append_battle_log(
                battle_key[1],
                log_type,
                actor_character_sync_id="",
                target_character_sync_id=character_sync_id,
                amount=amount,
                metadata={
                    "source": "gm_direct",
                    "hp_before": max(0, int(character[1].get("hp", 0) or 0)),
                    "hp_after": hp,
                    "temporary_hp_before": max(0, int(character[1].get("temporary_hp", 0) or 0)),
                    "temporary_hp_after": temporary_hp,
                },
                broadcast=False,
            )
            battle_event = await self.send_battle_event(
                "battle.state",
                battle,
                extra={
                    "journal_entry": journal_entry["payload"]["data"],
                },
            )
            if operation == "damage" and hp == 0 and old_life == "normal":
                await self._append_battle_log(
                    battle_key[1],
                    "downed",
                    actor_character_sync_id="",
                    target_character_sync_id=character_sync_id,
                    metadata={"source": "gm_direct", "life_state": "downed"},
                )

            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": battle_event["sequence"],
                "payload": {
                    "event": "ack",
                    "command_id": command_id,
                    "battle_sync_id": battle_key[1],
                    "character_sequence": state_event["sequence"],
                },
            })

    async def _handle_session_reward_apply(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может выдавать награды", command_id)
            return
        async with self._lock:
            session_sync_id = str(payload.get("session_sync_id", "")).strip()
            session = self._session_by_sync_id(session_sync_id)
            if session is None:
                await self.send_error(client, "Сессия не найдена", command_id)
                return
            if session[1].get("status") == "planned":
                await self.send_error(client, "XP нельзя выдавать до начала сессии", command_id)
                return
            character_sync_id = str(payload.get("character_sync_id", "")).strip()
            character_ref = self._character_for_campaign(character_sync_id)
            if character_ref is None:
                await self.send_error(client, "Персонаж не относится к кампании", command_id)
                return
            try:
                amount = int(payload.get("amount"))
            except (TypeError, ValueError):
                await self.send_error(client, "Количество XP должно быть целым числом", command_id)
                return
            if amount <= 0:
                await self.send_error(client, "Количество XP должно быть положительным", command_id)
                return
            if str(payload.get("type") or "xp") != "xp":
                await self.send_error(client, "Поддерживается только награда XP", command_id)
                return

            key, character = character_ref
            old_xp = max(0, int(character.get("xp", 0) or 0))
            new_xp = min(1 << 30, old_xp + amount)
            if new_xp == old_xp:
                await self.send_error(client, "Опыт уже находится на максимальном значении", command_id)
                return
            old_level = max(1, int(character.get("level", 1) or 1))
            new_level = self._level_for_xp(new_xp)
            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            reason = str(payload.get("reason") or "").strip()

            reward = {
                "sync_id": secrets.token_hex(16),
                "session_sync_id": session_sync_id,
                "character_sync_id": character_sync_id,
                "type": "xp",
                "amount": amount,
                "reason": reason,
                "level_before": old_level,
                "level_after": new_level,
                "created_at": now,
                "created_by": client.display_name,
            }
            xp_transaction = {
                "sync_id": secrets.token_hex(16),
                "character_sync_id": character_sync_id,
                "delta": amount,
                "xp_before": old_xp,
                "xp_after": new_xp,
                "level_before": old_level,
                "level_after": new_level,
                "reason": reason,
                "created_at": now,
            }
            updated_character = dict(character)
            updated_character["xp"] = new_xp
            updated_character["level"] = new_level
            self.state[key] = updated_character
            self.state[("session_reward", reward["sync_id"])] = reward
            self.state[("xp_transaction", xp_transaction["sync_id"])] = xp_transaction

            character_event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "character",
                    "data": dict(updated_character),
                },
            )
            reward_event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "session_reward",
                    "data": dict(reward),
                },
            )
            xp_event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "xp_transaction",
                    "data": dict(xp_transaction),
                },
            )
            session_event = await self._append_session_event(
                session_sync_id=session_sync_id,
                event_type="reward_granted",
                title=f"+{amount} XP — {character.get('name') or 'Персонаж'}",
                description=reason,
                metadata={
                    "reward_sync_id": reward["sync_id"],
                    "character_sync_id": character_sync_id,
                    "amount": amount,
                    "level_before": old_level,
                    "level_after": new_level,
                },
                created_by=client.display_name,
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": session_event["sequence"],
                "payload": {
                    "event": "ack",
                    "command_id": command_id,
                    "reward_sync_id": reward["sync_id"],
                    "xp_transaction_sync_id": xp_transaction["sync_id"],
                    "character_sequence": character_event["sequence"],
                    "reward_sequence": reward_event["sequence"],
                    "xp_transaction_sequence": xp_event["sequence"],
                    "character": dict(updated_character),
                    "reward": dict(reward),
                    "xp_transaction": dict(xp_transaction),
                },
            })

    async def _handle_session_loot_claim(self, client: Client, command_id: str, payload: dict[str, Any]) -> None:
        if client.role != "gm":
            await self.send_error(client, "Только ГМ может распределять добычу", command_id)
            return
        async with self._lock:
            loot_sync_id = str(payload.get("loot_sync_id", "")).strip()
            loot_ref = self.state.get(("session_loot", loot_sync_id))
            if loot_ref is None:
                await self.send_error(client, "Добыча не найдена", command_id)
                return
            loot = dict(loot_ref)
            if loot.get("status", "available") != "available":
                await self.send_error(client, "Эта добыча уже распределена", command_id)
                return
            session_sync_id = str(loot.get("session_sync_id", "")).strip()
            if self._session_by_sync_id(session_sync_id) is None:
                await self.send_error(client, "Сессия добычи не найдена", command_id)
                return
            character_sync_id = str(payload.get("character_sync_id", "")).strip()
            character_ref = self._character_for_campaign(character_sync_id)
            if character_ref is None:
                await self.send_error(client, "Персонаж не относится к кампании", command_id)
                return
            quantity = max(1, int(loot.get("quantity", 1) or 1))
            now = time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())
            item_sync_id = secrets.token_hex(16)
            item = {
                "sync_id": item_sync_id,
                "character_sync_id": character_sync_id,
                "name": str(loot.get("name") or "Добыча"),
                "quantity": quantity,
                "category": "Other",
                "description": str(loot.get("description") or ""),
                "weight": 0.0,
                "source_url": "",
            }
            loot["status"] = "claimed"
            loot["claimed_by_character_sync_id"] = character_sync_id
            loot["updated_at"] = now
            self.state[("session_loot", loot_sync_id)] = loot
            self.state[("item", item_sync_id)] = item
            session_event = await self._append_session_event(
                session_sync_id=session_sync_id,
                event_type="loot_claimed",
                title=f"{item['name']} → {character_ref[1].get('name') or 'Персонаж'}",
                description=(f"Источник: {loot.get('source')}" if str(loot.get('source') or "").strip() else ""),
                metadata={
                    "loot_sync_id": loot_sync_id,
                    "character_sync_id": character_sync_id,
                    "item_sync_id": item_sync_id,
                    "quantity": quantity,
                },
                created_by=client.display_name,
            )
            item_event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "item",
                    "data": dict(item),
                },
            )
            loot_event = await self.broadcast_event(
                "state.upsert",
                {
                    "command_id": command_id,
                    "origin_client_id": client.client_id,
                    "origin_display_name": client.display_name,
                    "entity": "session_loot",
                    "data": dict(loot),
                },
            )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": session_event["sequence"],
                "payload": {
                    "event": "ack",
                    "command_id": command_id,
                    "loot_sync_id": loot_sync_id,
                    "item_sync_id": item_sync_id,
                    "item_sequence": item_event["sequence"],
                    "loot_sequence": loot_event["sequence"],
                },
            })

    async def handle_command(self, client: Client, message: dict[str, Any]) -> None:
        if message.get("protocol") != PROTOCOL or message.get("type") != "command":
            await self.send_error(client, "Неподдерживаемое сообщение протокола")
            return
        command_id = str(message.get("id", ""))[:128]
        payload = message.get("payload")
        if not command_id or not isinstance(payload, dict):
            await self.send_error(client, "Недопустимый формат команды", command_id)
            return
        command = str(payload.get("command", ""))[:80]
        if message.get("campaign_id") != self.campaign_id:
            await self.send_error(client, "Кампания не совпадает с текущим подключением", command_id)
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
                await self.send_error(client, "Недопустимая последовательность восстановления соединения", command_id)
                return
            await self._resume(client, last_sequence)
            return

        if command == "member.unlink_character":
            if client.role != "player":
                await self.send_error(client, "Только игрок может отвязать своего персонажа", command_id)
                return
            member = self._player_member(client)
            member_sync_id = str(payload.get("member_sync_id", "")).strip()
            if member is None or member[0][1] != member_sync_id:
                await self.send_error(client, "Участник-игрок не найден", command_id)
                return

            async with self._lock:
                member_key, member_data = member
                linked_character_sync_id = str(
                    member_data.get("linked_character_sync_id") or ""
                ).strip()
                updated_member = dict(member_data)
                updated_member["linked_character_sync_id"] = None
                self.state[member_key] = updated_member

                await self.broadcast_event(
                    "state.upsert",
                    {
                        "command_id": command_id,
                        "origin_client_id": client.client_id,
                        "origin_display_name": client.display_name,
                        "entity": "campaign_member",
                        "data": updated_member,
                    },
                    include_sender=True,
                    sender_id=client.client_id,
                )

                removed = self._remove_linked_character_state(
                    linked_character_sync_id
                ) if linked_character_sync_id else []

                for entity, sync_id in removed:
                    await self.broadcast_event(
                        "state.delete",
                        {
                            "command_id": command_id,
                            "origin_client_id": client.client_id,
                            "origin_display_name": client.display_name,
                            "entity": entity,
                            "sync_id": sync_id,
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
                            "unlinked": True,
                            "removed_entities": len(removed),
                        },
                    }
                )
            return

        if command == "member.leave":
            if client.role != "player":
                await self.send_error(client, "Только игрок может покинуть кампанию", command_id)
                return
            member = self._player_member(client)
            member_sync_id = str(payload.get("member_sync_id", "")).strip()
            if member is None or member[0][1] != member_sync_id:
                await self.send_error(client, "Участник-игрок не найден", command_id)
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

        if command == "battle.start":
            await self._handle_battle_start(client, command_id, payload)
            return

        if command == "battle.end":
            await self._handle_battle_end(client, command_id, payload)
            return

        if command == "battle.turn.start":
            await self._handle_battle_turn_start(client, command_id, payload)
            return

        if command == "battle.turn.end":
            await self._handle_battle_turn_end(client, command_id, payload)
            return

        if command == "battle.action.submit":
            await self._handle_battle_action_submit(client, command_id, payload)
            return

        if command == "battle.action.approve":
            await self._handle_battle_action_resolve(client, command_id, payload, status="approved")
            return

        if command == "battle.action.modify":
            await self._handle_battle_action_resolve(client, command_id, payload, status="modified")
            return

        if command == "battle.action.reject":
            await self._handle_battle_action_resolve(client, command_id, payload, status="rejected")
            return

        if command == "character.hp.modify":
            await self._handle_character_hp_modify(client, command_id, payload)
            return
        if command == "character.temp_hp.set":
            await self._handle_character_temp_hp_set(client, command_id, payload)
            return
        if command == "character.life_state.set":
            await self._handle_character_life_state_set(client, command_id, payload)
            return
        if command == "character.xp.grant":
            await self._handle_character_xp_grant(client, command_id, payload)
            return
        if command == "character.currency.grant":
            await self._handle_character_currency_grant(client, command_id, payload)
            return
        if command == "character.inspiration.grant":
            await self._handle_character_inspiration_grant(client, command_id, payload)
            return
        if command == "character.condition.apply":
            await self._handle_character_condition_apply(client, command_id, payload)
            return
        if command == "character.condition.remove":
            await self._handle_character_condition_remove(client, command_id, payload)
            return

        if command in {"battle.damage", "battle.heal", "battle.temp_hp"}:
            operation = {
                "battle.damage": "damage",
                "battle.heal": "heal",
                "battle.temp_hp": "temp_hp",
            }[command]
            await self._handle_battle_character_action(
                client,
                command_id,
                payload,
                operation,
            )
            return

        if command == "session.reward.apply":
            await self._handle_session_reward_apply(client, command_id, payload)
            return

        if command == "session.loot.claim":
            await self._handle_session_loot_claim(client, command_id, payload)
            return

        if command == "snapshot.publish":
            if client.role != "gm":
                await self.send_error(client, "Только ГМ может опубликовать эталонный снимок состояния", command_id)
                return
            raw_entities = payload.get("entities")
            if not isinstance(raw_entities, list) or len(raw_entities) > MAX_SNAPSHOT_ENTITIES:
                await self.send_error(client, "Недопустимый снимок состояния", command_id)
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
                    if entity_name in {"item", "spell", "ability", "attack", "note", "spell_slot", "xp_transaction", "custom_action", "character_condition"} and candidate.get("character_sync_id") not in linked_characters:
                        raise ValueError("snapshot contains an entity outside the hosted campaign")
                    if entity_name == "character" and str(candidate.get("life_state") or "normal") not in {"normal", "downed", "dead"}:
                        raise ValueError("snapshot contains an invalid life state")
                    if entity_name in {"session_note", "session_event", "session_reward", "session_loot"}:
                        session_sync_id = str(candidate.get("session_sync_id") or "")
                        session = new_state.get(("session", session_sync_id))
                        if session is None or session.get("campaign_sync_id") != self.campaign_id:
                            raise ValueError("snapshot session workspace entity references an unknown session")
                        if entity_name == "session_reward":
                            if str(candidate.get("character_sync_id") or "") not in linked_characters:
                                raise ValueError("snapshot reward references an unlinked character")
                            reward_type = str(candidate.get("type") or "xp")
                            if reward_type not in {"xp", "currency", "inspiration"}:
                                raise ValueError("snapshot contains an unsupported reward type")
                            if int(candidate.get("amount", 0) or 0) <= 0:
                                raise ValueError("snapshot contains an invalid reward amount")
                            if reward_type == "currency" and str(candidate.get("currency") or "") not in {"copper", "silver", "electrum", "gold", "platinum"}:
                                raise ValueError("snapshot contains an invalid reward currency")
                        if entity_name == "session_loot":
                            if str(candidate.get("status") or "available") not in {"available", "claimed"}:
                                raise ValueError("snapshot contains an invalid loot status")
                            if int(candidate.get("quantity", 0) or 0) <= 0:
                                raise ValueError("snapshot contains an invalid loot quantity")
                            claimed_by = str(candidate.get("claimed_by_character_sync_id") or "")
                            if candidate.get("status") == "claimed" and claimed_by not in linked_characters:
                                raise ValueError("snapshot loot references an unlinked claimant")
                    if entity_name == "battle":
                        if candidate.get("campaign_sync_id") != self.campaign_id:
                            raise ValueError("snapshot contains a battle outside the hosted campaign")
                        session_sync_id = str(candidate.get("session_sync_id") or "")
                        session = new_state.get(("session", session_sync_id))
                        if session is None or session.get("campaign_sync_id") != self.campaign_id:
                            raise ValueError("snapshot battle references an unknown session")
                        if candidate.get("status") not in {"active", "completed"}:
                            raise ValueError("snapshot contains an invalid battle status")
                    if entity_name in {"battle_turn", "battle_action_request", "battle_log_entry"}:
                        battle_sync_id = str(candidate.get("battle_sync_id") or "")
                        battle = new_state.get(("battle", battle_sync_id))
                        if battle is None or battle.get("campaign_sync_id") != self.campaign_id:
                            raise ValueError("snapshot workspace entity references an unknown battle")
                    if entity_name == "battle_turn":
                        if candidate.get("status") not in {"active", "completed"}:
                            raise ValueError("snapshot contains an invalid turn status")
                        if str(candidate.get("character_sync_id") or "") not in linked_characters:
                            raise ValueError("snapshot turn references an unlinked character")
                    if entity_name == "battle_action_request":
                        if candidate.get("status") not in {"declared", "pending_gm", "approved", "modified", "rejected"}:
                            raise ValueError("snapshot contains an invalid action request status")
                        if str(candidate.get("actor_character_sync_id") or "") not in linked_characters:
                            raise ValueError("snapshot action references an unlinked actor")
                        target_type = str(candidate.get("target_type") or "self")
                        if target_type not in {"self", "ally", "external"}:
                            raise ValueError("snapshot contains an invalid action target")
                        if target_type == "ally" and str(candidate.get("target_character_sync_id") or "") not in linked_characters:
                            raise ValueError("snapshot action references an unlinked target")
                        if target_type == "external" and not str(candidate.get("target_label") or "").strip():
                            raise ValueError("snapshot external action has no target label")
                        effect_type = str(candidate.get("effect_type") or "none")
                        if effect_type not in {"none", "damage", "healing", "temporary_hp", "condition_apply", "condition_remove"}:
                            raise ValueError("snapshot contains an unsupported action effect")
                    if entity_name == "battle_log_entry":
                        for field in ("actor_character_sync_id", "target_character_sync_id"):
                            value = str(candidate.get(field) or "").strip()
                            if value and value not in linked_characters:
                                raise ValueError("snapshot journal references an unlinked character")
                    if entity_name == "custom_action" and not str(candidate.get("name") or "").strip():
                        raise ValueError("snapshot custom action has no name")
                    if entity_name == "character_condition":
                        if not str(candidate.get("name") or "").strip():
                            raise ValueError("snapshot condition has no name")
                        if str(candidate.get("scope") or "character") not in {"character", "battle", "session"}:
                            raise ValueError("snapshot contains an invalid condition scope")
                active_battles = [
                    candidate
                    for (entity_name, _), candidate in new_state.items()
                    if entity_name == "battle" and candidate.get("status") == "active"
                ]
                active_sessions = [str(candidate.get("session_sync_id") or "") for candidate in active_battles]
                if len(active_sessions) != len(set(active_sessions)):
                    raise ValueError("snapshot contains multiple active battles for one session")
                active_turns = [
                    candidate
                    for (entity_name, _), candidate in new_state.items()
                    if entity_name == "battle_turn" and candidate.get("status") == "active"
                ]
                active_turn_keys = [
                    f"{candidate.get('battle_sync_id')}" for candidate in active_turns
                ]
                if len(active_turn_keys) != len(set(active_turn_keys)):
                    raise ValueError("snapshot contains multiple active turns for one battle")
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
                await self.send_error(client, "Только игрок может привязать своего персонажа", command_id)
                return
            member = self._player_member(client)
            if member is None:
                await self.send_error(client, "Участник-игрок не найден", command_id)
                return
            member_key, member_data = member
            member_sync_id = str(payload.get("member_sync_id", "")).strip()
            character = payload.get("character")
            if member_sync_id != member_key[1] or not isinstance(character, dict):
                await self.send_error(client, "Недопустимая привязка персонажа игрока", command_id)
                return
            character_data = dict(character)
            character_sync_id = str(character_data.get("sync_id", "")).strip()
            if not character_sync_id:
                await self.send_error(client, "Для персонажа требуется sync_id", command_id)
                return
            if "bio_image" in character_data:
                character_data.pop("bio_image", None)

            existing_link = None
            for (entity_name, sync_key), candidate in self.state.items():
                if entity_name == "campaign_member" and candidate.get("linked_character_sync_id") == character_sync_id and sync_key != member_key[1]:
                    existing_link = sync_key
                    break
            if existing_link is not None:
                await self.send_error(client, "Персонаж уже привязан к другому участнику кампании", command_id)
                return

            # Optional initial loadout is part of the link transaction so
            # GM clients can open the character immediately without depending
            # on a later race-prone publish command.
            raw_loadout = payload.get("loadout", [])
            if raw_loadout is None:
                raw_loadout = []
            if not isinstance(raw_loadout, list) or len(raw_loadout) > MAX_SNAPSHOT_ENTITIES:
                await self.send_error(client, "Недопустимый список действий персонажа", command_id)
                return

            allowed_entities = {"attack", "spell", "ability", "item", "custom_action"}
            normalized_loadout: list[tuple[str, str, dict[str, Any]]] = []
            seen_loadout: set[tuple[str, str]] = set()
            try:
                for raw in raw_loadout:
                    if not isinstance(raw, dict):
                        raise ValueError("invalid loadout entity")
                    entity = str(raw.get("entity") or "")
                    data = raw.get("data")
                    if entity not in allowed_entities or not isinstance(data, dict):
                        raise ValueError("invalid loadout entity")
                    candidate = dict(data)
                    sync_id = str(candidate.get("sync_id") or "").strip()
                    candidate_character = str(candidate.get("character_sync_id") or "").strip()
                    if not sync_id or candidate_character != character_sync_id:
                        raise ValueError("loadout entity references another character")
                    key = (entity, sync_id)
                    if key in seen_loadout:
                        raise ValueError("duplicate loadout entity")
                    seen_loadout.add(key)
                    candidate.pop("id", None)
                    candidate.pop("character_id", None)
                    candidate.pop("library_item_id", None)
                    normalized_loadout.append((entity, sync_id, candidate))
            except (TypeError, ValueError):
                await self.send_error(client, "Недопустимые данные действий персонажа", command_id)
                return

            # Replace stale loadout rows for this character before publishing
            # the new state to every connected client.
            incoming_loadout = {(entity, sync_id) for entity, sync_id, _ in normalized_loadout}
            for key, current in list(self.state.items()):
                entity, sync_id = key
                if (
                    entity in allowed_entities
                    and str(current.get("character_sync_id") or "").strip() == character_sync_id
                    and key not in incoming_loadout
                ):
                    self.state.pop(key, None)
                    await self.broadcast_event(
                        "state.delete",
                        {
                            "command_id": command_id,
                            "origin_client_id": client.client_id,
                            "origin_display_name": client.display_name,
                            "entity": entity,
                            "sync_id": sync_id,
                        },
                        include_sender=False,
                        sender_id=client.client_id,
                    )

            member_data = dict(member_data)
            member_data["linked_character_sync_id"] = character_sync_id
            self.state[member_key] = member_data
            self.state[("character", character_sync_id)] = character_data
            for entity, sync_id, candidate in normalized_loadout:
                self.state[(entity, sync_id)] = candidate

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
            for entity, sync_id, candidate in normalized_loadout:
                await self.broadcast_event(
                    "state.upsert",
                    {
                        "command_id": command_id,
                        "origin_client_id": client.client_id,
                        "origin_display_name": client.display_name,
                        "entity": entity,
                        "data": dict(candidate),
                    },
                    include_sender=False,
                    sender_id=client.client_id,
                )
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": second["sequence"],
                "payload": {"event": "ack", "command_id": command_id, "linked": True, "character_sequence": first["sequence"], "published": len(normalized_loadout)},
            })
            return

        if command == "character.loadout.publish":
            if client.role != "player":
                await self.send_error(client, "Только игрок может опубликовать действия своего персонажа", command_id)
                return
            async with self._lock:
                character_sync_id = str(payload.get("character_sync_id") or "").strip()
                allowed = self._player_character_sync_ids(client)
                if not character_sync_id or character_sync_id not in allowed:
                    await self.send_error(client, "Можно публиковать действия только своего персонажа", command_id)
                    return
                if self._character_for_campaign(character_sync_id) is None:
                    await self.send_error(client, "Персонаж не найден", command_id)
                    return

                raw_entities = payload.get("entities")
                if not isinstance(raw_entities, list) or len(raw_entities) > MAX_SNAPSHOT_ENTITIES:
                    await self.send_error(client, "Недопустимый список действий персонажа", command_id)
                    return

                allowed_entities = {"attack", "spell", "ability", "item", "custom_action"}
                normalized: list[tuple[str, str, dict[str, Any]]] = []
                seen: set[tuple[str, str]] = set()
                try:
                    for raw in raw_entities:
                        if not isinstance(raw, dict):
                            raise ValueError("invalid loadout entity")
                        entity = str(raw.get("entity") or "")
                        data = raw.get("data")
                        if entity not in allowed_entities or not isinstance(data, dict):
                            raise ValueError("invalid loadout entity")
                        candidate = dict(data)
                        sync_id = str(candidate.get("sync_id") or "").strip()
                        candidate_character = str(candidate.get("character_sync_id") or "").strip()
                        if not sync_id or candidate_character != character_sync_id:
                            raise ValueError("loadout entity references another character")
                        key = (entity, sync_id)
                        if key in seen:
                            raise ValueError("duplicate loadout entity")
                        seen.add(key)
                        candidate.pop("id", None)
                        candidate.pop("character_id", None)
                        candidate.pop("library_item_id", None)
                        normalized.append((entity, sync_id, candidate))
                except (TypeError, ValueError):
                    await self.send_error(client, "Недопустимые данные действий персонажа", command_id)
                    return

                incoming = {(entity, sync_id) for entity, sync_id, _ in normalized}
                for key, current in list(self.state.items()):
                    entity, sync_id = key
                    if entity in allowed_entities and str(current.get("character_sync_id") or "").strip() == character_sync_id and key not in incoming:
                        self.state.pop(key, None)
                        await self.broadcast_event(
                            "state.delete",
                            {
                                "command_id": command_id,
                                "origin_client_id": client.client_id,
                                "origin_display_name": client.display_name,
                                "entity": entity,
                                "sync_id": sync_id,
                            },
                            include_sender=False,
                            sender_id=client.client_id,
                        )

                for entity, sync_id, candidate in normalized:
                    self.state[(entity, sync_id)] = candidate
                    await self.broadcast_event(
                        "state.upsert",
                        {
                            "command_id": command_id,
                            "origin_client_id": client.client_id,
                            "origin_display_name": client.display_name,
                            "entity": entity,
                            "data": candidate,
                        },
                        include_sender=False,
                        sender_id=client.client_id,
                    )

                await client.websocket.send_json({
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": self.sequence,
                    "payload": {
                        "event": "ack",
                        "command_id": command_id,
                        "character_sync_id": character_sync_id,
                        "published": len(normalized),
                    },
                })
            return

        if command == "character.loadout.request":
            character_sync_id = str(payload.get("character_sync_id") or "").strip()
            target = self._character_for_campaign(character_sync_id)
            if target is None:
                await self.send_error(client, "Персонаж не найден", command_id)
                return
            if not self._battle_character_allowed(client, character_sync_id):
                await self.send_error(client, "Нет доступа к действиям этого персонажа", command_id)
                return

            # Return the state currently known by the server immediately so the
            # GM request never blocks on another device. If the character is
            # online, also ask its owner to republish the authoritative local
            # loadout. The resulting state.upsert events update the GM view even
            # when the server had a stale/empty loadout (for example after a GM
            # reconnect or snapshot publication).
            loadout = self._character_loadout(character_sync_id)
            await client.websocket.send_json({
                "protocol": PROTOCOL,
                "type": "event",
                "id": secrets.token_hex(16),
                "client_id": "server",
                "campaign_id": self.campaign_id,
                "sequence": self.sequence,
                "payload": {
                    "event": "ack",
                    "command_id": command_id,
                    "character_sync_id": character_sync_id,
                    "loadout": loadout,
                },
            })

            owner = self._player_client_for_character(character_sync_id)
            if owner is not None and owner.client_id != client.client_id:
                await owner.websocket.send_json({
                    "protocol": PROTOCOL,
                    "type": "event",
                    "id": secrets.token_hex(16),
                    "client_id": "server",
                    "campaign_id": self.campaign_id,
                    "sequence": self.sequence,
                    "payload": {
                        "event": "character.loadout.pull",
                        "character_sync_id": character_sync_id,
                    },
                })
            return

        if command in {"state.upsert", "state.delete"}:
            if client.role not in {"player", "gm"}:
                await self.send_error(client, "Недостаточно прав", command_id)
                return
            entity = str(payload.get("entity", ""))
            if entity in {"battle", "battle_turn", "battle_action_request", "battle_log_entry"}:
                await self.send_error(client, "Состояние боевого режима можно менять только командами боя", command_id)
                return
            if entity not in SUPPORTED_ENTITIES:
                await self.send_error(client, "Неподдерживаемая сущность синхронизации", command_id)
                return

            if command == "state.upsert":
                raw_data = payload.get("data")
                if not isinstance(raw_data, dict):
                    await self.send_error(client, "Недопустимые данные состояния", command_id)
                    return
                data = dict(raw_data)
                sync_id = str(data.get("sync_id", "")).strip()
                if not sync_id:
                    await self.send_error(client, "Для сущности состояния требуется sync_id", command_id)
                    return
                if entity == "character" and "bio_image" in data:
                    await self.send_error(client, "Изображения персонажей не входят в синхронизацию в реальном времени", command_id)
                    return
                if not self._player_can_mutate(client, entity, data):
                    await self.send_error(client, "Игрок может изменять только привязанного к нему персонажа", command_id)
                    return
                if not self._state_entry_belongs_to_campaign(entity, data):
                    await self.send_error(client, "Сущность состояния не относится к размещённой кампании", command_id)
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
                    await self.send_error(client, "Для удаления требуется sync_id", command_id)
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
                    await self.send_error(client, "Сущность состояния не относится к размещённой кампании", command_id)
                    return
                if not self._player_can_mutate(client, entity, current):
                    await self.send_error(client, "Игрок может изменять только привязанного к нему персонажа", command_id)
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
            active_battle = self._active_battle()
            if active_battle is not None:
                await self.send_battle_snapshot(client, active_battle[1])
            return
        oldest = self.history[0]["sequence"]
        if last_sequence < oldest - 1:
            await self.send_snapshot(client)
            active_battle = self._active_battle()
            if active_battle is not None:
                await self.send_battle_snapshot(client, active_battle[1])
            return
        for event in self.history:
            if event["sequence"] > last_sequence:
                await client.websocket.send_json(event)


def build_app(hub: HubServer, *, port: int) -> FastAPI:
    hub.port = port
    app = FastAPI(title="D&D Hub GM Server", version="1.0.0")

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
                active_battle = hub._active_battle()
                if active_battle is not None:
                    await hub.send_battle_snapshot(client, active_battle[1])
            await hub.broadcast_event(
                "player.joined",
                {"client_id": client.client_id, "display_name": client.display_name, "role": client.role},
                include_sender=False,
                sender_id=client.client_id,
            )
            while True:
                raw = await websocket.receive_text()
                if len(raw.encode("utf-8")) > MAX_MESSAGE_BYTES:
                    await hub.send_error(client, "Сообщение слишком большое")
                    continue
                import json

                try:
                    message = json.loads(raw)
                except json.JSONDecodeError:
                    await hub.send_error(client, "Недопустимый JSON")
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
