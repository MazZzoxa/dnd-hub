from fastapi.testclient import TestClient

from server.app.server import HubServer, PROTOCOL, build_app


def test_health_and_session() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))
    assert client.get("/health").json()["ok"] is True
    assert client.get("/health").json()["protocol"] == PROTOCOL
    assert client.get("/session").json()["campaign_name"] == "Test Campaign"


def test_websocket_join_and_ping() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        "/ws?token=token&client_id=client-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as ws:
        welcome = ws.receive_json()
        assert welcome["payload"]["event"] == "session.ready"
        ws.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "command-1",
                "client_id": "client-1",
                "campaign_id": "campaign-1",
                "payload": {"command": "ping"},
            }
        )
        pong = ws.receive_json()
        assert pong["payload"]["event"] == "pong"


def test_gm_snapshot_is_delivered_and_state_is_shared() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))

    with client.websocket_connect(
        "/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM"
    ) as gm, client.websocket_connect(
        "/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as player:
        assert gm.receive_json()["payload"]["event"] == "session.ready"
        assert player.receive_json()["payload"]["event"] == "session.ready"
        assert gm.receive_json()["payload"]["event"] == "player.joined"

        gm.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "snapshot-1",
                "client_id": "gm-1",
                "campaign_id": "campaign-1",
                "payload": {
                    "command": "snapshot.publish",
                    "entities": [
                        {
                            "entity": "campaign",
                            "data": {
                                "sync_id": "campaign-1",
                                "name": "Test Campaign",
                                "description": "",
                                "created_at": "2026-09-19T00:00:00Z",
                                "updated_at": "2026-09-19T00:00:00Z",
                            },
                        },
                        {
                            "entity": "campaign_member",
                            "data": {
                                "sync_id": "member-1",
                                "campaign_sync_id": "campaign-1",
                                "name": "Alice",
                                "role": "player",
                                "linked_character_sync_id": "character-1",
                                "created_at": "2026-09-19T00:00:00Z",
                            },
                        },
                        {
                            "entity": "character",
                            "data": {
                                "sync_id": "character-1",
                                "name": "Rogue",
                                "level": 5,
                                "race": "",
                                "class_name": "Rogue",
                                "subclass": "",
                                "background": "",
                                "alignment": "",
                                "player_name": "Alice",
                                "strength": 10,
                                "dexterity": 16,
                                "constitution": 10,
                                "intelligence": 10,
                                "wisdom": 10,
                                "charisma": 10,
                                "hp": 30,
                                "max_hp": 42,
                                "temporary_hp": 0,
                                "armor_class": 15,
                                "initiative": 3,
                                "speed": 30,
                                "proficiency_bonus": 3,
                                "inspiration": 0,
                                "hit_dice": "5d8",
                                "death_save_successes": 0,
                                "death_save_failures": 0,
                                "saving_throw_proficiencies": "[]",
                                "skill_proficiencies": "[]",
                                "xp": 6500,
                                "copper": 0,
                                "silver": 0,
                                "electrum": 0,
                                "gold": 100,
                                "platinum": 0,
                                "spellcasting_class": "",
                                "spellcasting_ability": "",
                                "personality_traits": "",
                                "ideals": "",
                                "bonds": "",
                                "flaws": "",
                                "proficiencies_languages": "",
                                "age": "",
                                "height": "",
                                "weight": "",
                                "eyes": "",
                                "skin": "",
                                "hair": "",
                                "backstory": "",
                                "allies_organizations": "",
                                "treasure": "",
                            },
                        },
                        {
                            "entity": "item",
                            "data": {
                                "sync_id": "item-1",
                                "character_sync_id": "character-1",
                                "name": "Dagger",
                                "quantity": 1,
                                "category": "Weapons",
                                "description": "",
                                "weight": 1.0,
                                "source_url": "",
                            },
                        },
                    ],
                },
            }
        )
        ack = gm.receive_json()
        assert ack["payload"]["event"] == "ack"

        snapshot = player.receive_json()
        assert snapshot["payload"]["event"] == "state.snapshot"
        entities = snapshot["payload"]["entities"]
        assert {entity["entity"] for entity in entities} == {"campaign", "campaign_member", "character", "item"}
        assert hub.state[("item", "item-1")]["character_sync_id"] == "character-1"


def test_wrong_protocol_is_rejected() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        "/ws?token=token&client_id=client-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as ws:
        assert ws.receive_json()["payload"]["event"] == "session.ready"
        ws.send_json(
            {
                "protocol": 1,
                "type": "command",
                "id": "command-old",
                "client_id": "client-1",
                "campaign_id": "campaign-1",
                "payload": {"command": "ping"},
            }
        )
        error = ws.receive_json()
        assert error["payload"]["event"] == "error"


def _minimal_snapshot() -> list[dict]:
    return [
        {
            "entity": "campaign",
            "data": {
                "sync_id": "campaign-1",
                "name": "Test Campaign",
                "description": "",
                "created_at": "2026-09-19T00:00:00Z",
                "updated_at": "2026-09-19T00:00:00Z",
            },
        },
        {
            "entity": "campaign_member",
            "data": {
                "sync_id": "member-1",
                "campaign_sync_id": "campaign-1",
                "name": "Alice",
                "role": "player",
                "client_id": "player-1",
                "linked_character_sync_id": "character-1",
                "created_at": "2026-09-19T00:00:00Z",
            },
        },
        {
            "entity": "character",
            "data": {
                "sync_id": "character-1",
                "name": "Rogue",
                "level": 5,
                "race": "",
                "class_name": "Rogue",
                "subclass": "",
                "background": "",
                "alignment": "",
                "player_name": "Alice",
                "hp": 30,
                "max_hp": 42,
                "armor_class": 15,
                "initiative": 3,
                "speed": 30,
                "proficiency_bonus": 3,
            },
        },
        {
            "entity": "item",
            "data": {
                "sync_id": "item-1",
                "character_sync_id": "character-1",
                "name": "Dagger",
                "quantity": 1,
                "category": "Weapons",
                "description": "",
                "weight": 1.0,
                "source_url": "",
            },
        },
    ]


def test_state_upsert_and_delete_are_broadcast_and_authoritative() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        "/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM"
    ) as gm, client.websocket_connect(
        "/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as player:
        assert gm.receive_json()["payload"]["event"] == "session.ready"
        assert player.receive_json()["payload"]["event"] == "session.ready"
        assert gm.receive_json()["payload"]["event"] == "player.joined"

        gm.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "snapshot-1",
                "client_id": "gm-1",
                "campaign_id": "campaign-1",
                "payload": {"command": "snapshot.publish", "entities": _minimal_snapshot()},
            }
        )
        assert gm.receive_json()["payload"]["event"] == "ack"
        assert player.receive_json()["payload"]["event"] == "state.snapshot"

        player.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "update-1",
                "client_id": "player-1",
                "campaign_id": "campaign-1",
                "payload": {
                    "command": "state.upsert",
                    "entity": "character",
                    "data": {
                        "sync_id": "character-1",
                        "name": "Rogue",
                        "level": 5,
                        "hp": 12,
                    },
                },
            }
        )
        update = gm.receive_json()
        assert update["payload"]["event"] == "state.upsert"
        assert update["payload"]["entity"] == "character"
        assert hub.state[("character", "character-1")]["hp"] == 12
        player_event = player.receive_json()
        assert player_event["payload"]["event"] == "state.upsert"
        player_ack = player.receive_json()
        assert player_ack["payload"]["event"] == "ack"

        player.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "delete-1",
                "client_id": "player-1",
                "campaign_id": "campaign-1",
                "payload": {
                    "command": "state.delete",
                    "entity": "character",
                    "sync_id": "character-1",
                },
            }
        )
        deleted = gm.receive_json()
        assert deleted["payload"]["event"] == "state.delete"
        assert ("character", "character-1") not in hub.state
        assert ("item", "item-1") not in hub.state
        assert hub.state[("campaign_member", "member-1")]["linked_character_sync_id"] is None
        player_event = player.receive_json()
        assert player_event["payload"]["event"] == "state.delete"
        player_ack = player.receive_json()
        assert player_ack["payload"]["event"] == "ack"


def test_reconnect_with_same_client_id_gets_current_snapshot() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))

    with client.websocket_connect(
        "/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM"
    ) as gm:
        assert gm.receive_json()["payload"]["event"] == "session.ready"
        gm.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "snapshot-1",
                "client_id": "gm-1",
                "campaign_id": "campaign-1",
                "payload": {"command": "snapshot.publish", "entities": _minimal_snapshot()},
            }
        )
        assert gm.receive_json()["payload"]["event"] == "ack"

    player_url = "/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice"
    with client.websocket_connect(player_url) as player:
        assert player.receive_json()["payload"]["event"] == "session.ready"
        snapshot = player.receive_json()
        assert snapshot["payload"]["event"] == "state.snapshot"

    # Reusing the same client_id is the reconnect path. The server replaces the
    # old connection and the new one receives the current authoritative state.
    with client.websocket_connect(player_url) as player:
        assert player.receive_json()["payload"]["event"] == "session.ready"
        snapshot = player.receive_json()
        assert snapshot["payload"]["event"] == "state.snapshot"
        assert {e["entity"] for e in snapshot["payload"]["entities"]} == {
            "campaign",
            "campaign_member",
            "character",
            "item",
        }


def test_player_can_link_only_own_character_and_cannot_edit_campaign() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        "/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM"
    ) as gm, client.websocket_connect(
        "/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as player:
        assert gm.receive_json()["payload"]["event"] == "session.ready"
        assert player.receive_json()["payload"]["event"] == "session.ready"
        assert gm.receive_json()["payload"]["event"] == "player.joined"

        snapshot = [
            {
                "entity": "campaign",
                "data": {
                    "sync_id": "campaign-1",
                    "name": "Test Campaign",
                    "description": "",
                    "created_at": "2026-09-19T00:00:00Z",
                    "updated_at": "2026-09-19T00:00:00Z",
                },
            },
            {
                "entity": "campaign_member",
                "data": {
                    "sync_id": "member-1",
                    "campaign_sync_id": "campaign-1",
                    "name": "Alice",
                    "role": "player",
                    "client_id": "player-1",
                    "linked_character_sync_id": None,
                    "created_at": "2026-09-19T00:00:00Z",
                },
            },
        ]
        gm.send_json({
            "protocol": PROTOCOL,
            "type": "command",
            "id": "snapshot-perm-1",
            "client_id": "gm-1",
            "campaign_id": "campaign-1",
            "payload": {"command": "snapshot.publish", "entities": snapshot},
        })
        assert gm.receive_json()["payload"]["event"] == "ack"
        assert player.receive_json()["payload"]["event"] == "state.snapshot"

        player.send_json({
            "protocol": PROTOCOL,
            "type": "command",
            "id": "campaign-update-by-player",
            "client_id": "player-1",
            "campaign_id": "campaign-1",
            "payload": {
                "command": "state.upsert",
                "entity": "campaign",
                "data": {
                    "sync_id": "campaign-1",
                    "name": "Hacked Name",
                    "description": "",
                    "created_at": "2026-09-19T00:00:00Z",
                    "updated_at": "2026-09-19T00:00:00Z",
                },
            },
        })
        error = player.receive_json()
        assert error["payload"]["event"] == "error"
        assert hub.state[("campaign", "campaign-1")]["name"] == "Test Campaign"

        player.send_json({
            "protocol": PROTOCOL,
            "type": "command",
            "id": "link-character-1",
            "client_id": "player-1",
            "campaign_id": "campaign-1",
            "payload": {
                "command": "member.link_character",
                "member_sync_id": "member-1",
                "character": {
                    "sync_id": "character-1",
                    "name": "Alice's Rogue",
                    "level": 3,
                    "hp": 18,
                    "max_hp": 24,
                },
            },
        })
        character_event = gm.receive_json()
        member_event = gm.receive_json()
        assert character_event["payload"]["entity"] == "character"
        assert member_event["payload"]["entity"] == "campaign_member"
        player_character_event = player.receive_json()
        player_member_event = player.receive_json()
        player_ack = player.receive_json()
        assert player_character_event["payload"]["entity"] == "character"
        assert player_member_event["payload"]["entity"] == "campaign_member"
        assert player_ack["payload"]["event"] == "ack"
        assert hub.state[("campaign_member", "member-1")]["linked_character_sync_id"] == "character-1"

        player.send_json({
            "protocol": PROTOCOL,
            "type": "command",
            "id": "wrong-character-1",
            "client_id": "player-1",
            "campaign_id": "campaign-1",
            "payload": {
                "command": "state.upsert",
                "entity": "character",
                "data": {"sync_id": "other-character", "name": "Not Mine"},
            },
        })
        error = player.receive_json()
        assert error["payload"]["event"] == "error"
        assert ("character", "other-character") not in hub.state


def test_player_can_leave_and_membership_is_removed_without_deleting_campaign() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    client = TestClient(build_app(hub, port=8765))

    snapshot = [
        {
            "entity": "campaign",
            "data": {"sync_id": "campaign-1", "name": "Test Campaign"},
        },
        {
            "entity": "campaign_member",
            "data": {
                "sync_id": "member-1",
                "campaign_sync_id": "campaign-1",
                "name": "Alice",
                "role": "player",
                "client_id": "player-1",
                "linked_character_sync_id": "character-1",
            },
        },
        {
            "entity": "character",
            "data": {"sync_id": "character-1", "name": "Alice"},
        },
        {
            "entity": "item",
            "data": {"sync_id": "item-1", "character_sync_id": "character-1", "name": "Dagger"},
        },
    ]

    with client.websocket_connect(
        "/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM"
    ) as gm, client.websocket_connect(
        "/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as player:
        assert gm.receive_json()["payload"]["event"] == "session.ready"
        assert player.receive_json()["payload"]["event"] == "session.ready"
        # GM receives the player's connection event.
        assert gm.receive_json()["payload"]["event"] == "player.joined"

        gm.send_json({
            "protocol": PROTOCOL,
            "type": "command",
            "id": "snapshot-leave-1",
            "client_id": "gm-1",
            "campaign_id": "campaign-1",
            "payload": {"command": "snapshot.publish", "entities": snapshot},
        })
        assert gm.receive_json()["payload"]["event"] == "ack"
        assert player.receive_json()["payload"]["event"] == "state.snapshot"

        player.send_json({
            "protocol": PROTOCOL,
            "type": "command",
            "id": "leave-1",
            "client_id": "player-1",
            "campaign_id": "campaign-1",
            "payload": {"command": "member.leave", "member_sync_id": "member-1"},
        })

        member_delete = gm.receive_json()
        left = gm.receive_json()
        ack = player.receive_json()
        assert member_delete["payload"]["event"] == "state.delete"
        assert member_delete["payload"]["entity"] == "campaign_member"
        assert left["payload"]["event"] == "player.left"
        assert ack["payload"]["event"] == "ack"
        assert ack["payload"]["left"] is True
        assert ("campaign_member", "member-1") not in hub.state
        assert ("character", "character-1") not in hub.state
        assert ("item", "item-1") not in hub.state
        assert ("campaign", "campaign-1") in hub.state
