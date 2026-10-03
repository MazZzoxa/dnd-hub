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


def _battle_snapshot() -> list[dict]:
    entities = _minimal_snapshot()
    entities[1]['data']['client_id'] = 'player-1'
    entities[2]['data']['temporary_hp'] = 8
    entities[2]['data']['max_hp'] = 42
    entities.append({
        'entity': 'campaign_member',
        'data': {
            'sync_id': 'member-2',
            'campaign_sync_id': 'campaign-1',
            'name': 'Bob',
            'role': 'player',
            'client_id': 'player-2',
            'linked_character_sync_id': 'character-2',
        },
    })
    entities.append({
        'entity': 'character',
        'data': {
            'sync_id': 'character-2',
            'name': 'Fighter',
            'level': 5,
            'class_name': 'Fighter',
            'hp': 20,
            'max_hp': 30,
            'temporary_hp': 0,
            'armor_class': 16,
        },
    })
    entities.append({
        'entity': 'session',
        'data': {
            'sync_id': 'session-1',
            'campaign_sync_id': 'campaign-1',
            'title': 'Goblin Cave',
            'notes': '',
            'status': 'active',
            'created_at': '2026-09-19T00:00:00Z',
            'started_at': '2026-09-19T00:00:00Z',
            'ended_at': None,
            'updated_at': '2026-09-19T00:00:00Z',
        },
    })
    return entities


def _send_command(ws, command_id: str, command: str, **payload: object) -> None:
    ws.send_json({
        'protocol': PROTOCOL,
        'type': 'command',
        'id': command_id,
        'client_id': 'test',
        'campaign_id': 'campaign-1',
        'payload': {'command': command, **payload},
    })


def test_active_battle_reflects_direct_life_state_and_conditions() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'snapshot-state-battle', 'snapshot.publish', entities=_battle_snapshot())
        assert _receive_until_ack(gm, 'snapshot-state-battle')['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(gm, 'state-battle-start', 'battle.start', session_sync_id='session-1')
        assert gm.receive_json()['payload']['event'] == 'battle.started'
        assert player.receive_json()['payload']['event'] == 'battle.started'
        battle_id = gm.receive_json()['payload']['battle_sync_id']

        _send_command(
            gm,
            'state-condition-apply',
            'character.condition.apply',
            character_sync_id='character-1',
            name='Poisoned',
            description='Токсин действует.',
            duration_rounds=2,
            remaining_rounds=2,
            battle_sync_id=battle_id,
            session_sync_id='session-1',
        )
        gm_events = []
        player_events = []
        while True:
            event = gm.receive_json()
            gm_events.append(event)
            if event['payload'].get('event') == 'ack' and event['payload'].get('command_id') == 'state-condition-apply':
                break
        while len(player_events) < 3:
            player_events.append(player.receive_json())
        assert [event['payload'].get('event') for event in gm_events[:3]] == [
            'state.upsert', 'battle.journal.entry', 'battle.state'
        ]
        assert [event['payload'].get('event') for event in player_events] == [
            'state.upsert', 'battle.journal.entry', 'battle.state'
        ]
        condition_id = gm_events[0]['payload']['data']['sync_id']
        assert any(
            event['payload'].get('data', {}).get('type') == 'condition_applied'
            for event in gm_events
            if event['payload'].get('event') == 'battle.journal.entry'
        )
        battle_state = next(event for event in gm_events if event['payload'].get('event') == 'battle.state')
        projection = next(item for item in battle_state['payload']['projections'] if item['character_sync_id'] == 'character-1')
        assert projection['conditions'][0]['name'] == 'Poisoned'
        assert projection['life_state'] == 'normal'
        assert hub.state[('character_condition', condition_id)]['active'] == 1

        _send_command(
            gm,
            'state-life-dead',
            'character.life_state.set',
            character_sync_id='character-1',
            life_state='dead',
            battle_sync_id=battle_id,
            session_sync_id='session-1',
        )
        gm_events = []
        player_events = []
        while True:
            event = gm.receive_json()
            gm_events.append(event)
            if event['payload'].get('event') == 'ack' and event['payload'].get('command_id') == 'state-life-dead':
                break
        while len(player_events) < 3:
            player_events.append(player.receive_json())
        assert [event['payload'].get('event') for event in gm_events[:3]] == [
            'state.upsert', 'battle.journal.entry', 'battle.state'
        ]
        assert any(
            event['payload'].get('data', {}).get('type') == 'death'
            for event in gm_events
            if event['payload'].get('event') == 'battle.journal.entry'
        )
        battle_state = next(event for event in gm_events if event['payload'].get('event') == 'battle.state')
        projection = next(item for item in battle_state['payload']['projections'] if item['character_sync_id'] == 'character-1')
        assert projection['life_state'] == 'dead'

        _send_command(
            gm,
            'state-life-revive',
            'character.life_state.set',
            character_sync_id='character-1',
            life_state='normal',
            battle_sync_id=battle_id,
            session_sync_id='session-1',
        )
        gm_events = []
        while True:
            event = gm.receive_json()
            gm_events.append(event)
            if event['payload'].get('event') == 'ack' and event['payload'].get('command_id') == 'state-life-revive':
                break
        while player.receive_json()['payload'].get('event') != 'battle.state':
            pass
        assert any(
            event['payload'].get('data', {}).get('type') == 'revived'
            for event in gm_events
            if event['payload'].get('event') == 'battle.journal.entry'
        )


def test_battle_start_damage_heal_temp_hp_and_end() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'snapshot-battle-1', 'snapshot.publish', entities=_battle_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(gm, 'battle-start-1', 'battle.start', session_sync_id='session-1', battle_name='Бой у ворот')
        gm_event = gm.receive_json()
        player_event = player.receive_json()
        gm_ack = gm.receive_json()
        assert gm_event['payload']['event'] == 'battle.started'
        assert player_event['payload']['event'] == 'battle.started'
        assert gm_ack['payload']['event'] == 'ack'
        battle_id = gm_ack['payload']['battle_sync_id']
        assert hub.state[('battle', battle_id)]['status'] == 'active'
        assert hub.state[('battle', battle_id)]['name'] == 'Бой у ворот'

        _send_command(gm, 'battle-damage-1', 'battle.damage', battle_sync_id=battle_id, character_sync_id='character-1', amount=11)
        gm_character = gm.receive_json()
        player_character = player.receive_json()
        gm_battle = gm.receive_json()
        player_battle = player.receive_json()
        gm_ack = gm.receive_json()
        assert gm_character['payload']['event'] == 'state.upsert'
        assert player_character['payload']['event'] == 'state.upsert'
        assert gm_character['payload']['entity'] == 'character'
        assert player_character['payload']['entity'] == 'character'
        assert gm_character['payload']['data']['sync_id'] == 'character-1'
        assert player_character['payload']['data']['sync_id'] == 'character-1'
        assert gm_character['payload']['data']['hp'] == 27
        assert player_character['payload']['data']['hp'] == 27
        assert gm_character['payload']['data']['temporary_hp'] == 0
        assert player_character['payload']['data']['temporary_hp'] == 0
        assert gm_battle['payload']['event'] == 'battle.state'
        assert player_battle['payload']['event'] == 'battle.state'
        assert gm_ack['payload']['event'] == 'ack'
        assert hub.state[('character', 'character-1')]['hp'] == 27
        assert hub.state[('character', 'character-1')]['temporary_hp'] == 0

        _send_command(gm, 'battle-heal-1', 'battle.heal', battle_sync_id=battle_id, character_sync_id='character-1', amount=50)
        gm_heal = gm.receive_json()
        player_heal = player.receive_json()
        gm.receive_json()
        player.receive_json()
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert gm_heal['payload']['data']['hp'] == 42
        assert player_heal['payload']['data']['hp'] == 42
        assert hub.state[('character', 'character-1')]['hp'] == 42

        _send_command(gm, 'battle-temp-1', 'battle.temp_hp', battle_sync_id=battle_id, character_sync_id='character-1', amount=10)
        gm_temp = gm.receive_json()
        player_temp = player.receive_json()
        gm.receive_json()
        player.receive_json()
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert gm_temp['payload']['data']['temporary_hp'] == 10
        assert player_temp['payload']['data']['temporary_hp'] == 10
        assert hub.state[('character', 'character-1')]['temporary_hp'] == 10

        _send_command(gm, 'battle-end-1', 'battle.end', battle_sync_id=battle_id)
        gm_event = gm.receive_json()
        player_event = player.receive_json()
        gm_ack = gm.receive_json()
        assert gm_event['payload']['event'] == 'battle.ended'
        assert player_event['payload']['event'] == 'battle.ended'
        assert gm_ack['payload']['event'] == 'ack'
        assert hub.state[('battle', battle_id)]['status'] == 'completed'

        _send_command(gm, 'battle-start-2', 'battle.start', session_sync_id='session-1')
        second_start = gm.receive_json()
        player_second_start = player.receive_json()
        second_ack = gm.receive_json()
        assert second_start['payload']['event'] == 'battle.started'
        assert player_second_start['payload']['event'] == 'battle.started'
        assert second_ack['payload']['event'] == 'ack'
        assert second_ack['payload']['battle_sync_id'] != battle_id

        _send_command(gm, 'battle-end-2', 'battle.end', battle_sync_id=second_ack['payload']['battle_sync_id'])
        assert gm.receive_json()['payload']['event'] == 'battle.ended'
        assert player.receive_json()['payload']['event'] == 'battle.ended'
        assert gm.receive_json()['payload']['event'] == 'ack'



def test_gm_can_start_battle_without_connected_players() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm:
        assert gm.receive_json()['payload']['event'] == 'session.ready'

        _send_command(gm, 'snapshot-no-players', 'snapshot.publish', entities=[
            {
                'entity': 'campaign',
                'data': {'sync_id': 'campaign-1', 'name': 'Test Campaign'},
            },
            {
                'entity': 'campaign_member',
                'data': {
                    'sync_id': 'gm-member-1',
                    'campaign_sync_id': 'campaign-1',
                    'name': 'GM',
                    'role': 'gm',
                    'client_id': 'gm-1',
                    'linked_character_sync_id': None,
                },
            },
            {
                'entity': 'session',
                'data': {
                    'sync_id': 'session-1',
                    'campaign_sync_id': 'campaign-1',
                    'title': 'Solo test',
                    'status': 'active',
                },
            },
        ])
        assert gm.receive_json()['payload']['event'] == 'ack'

        _send_command(gm, 'battle-no-players', 'battle.start', session_sync_id='session-1')
        started = gm.receive_json()
        ack = gm.receive_json()
        assert started['payload']['event'] == 'battle.started'
        assert ack['payload']['event'] == 'ack'
        assert hub.player_count == 0
        assert any(
            key[0] == 'battle' and data['status'] == 'active'
            for key, data in hub.state.items()
        )

def test_player_battle_permissions_are_enforced_server_side() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player_one, client.websocket_connect(
        '/ws?token=token&client_id=player-2&campaign_id=campaign-1&role=player&display_name=Bob'
    ) as player_two:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player_one.receive_json()['payload']['event'] == 'session.ready'
        assert player_two.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'
        assert gm.receive_json()['payload']['event'] == 'player.joined'
        assert player_one.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'snapshot-permission-battle', 'snapshot.publish', entities=_battle_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player_one.receive_json()['payload']['event'] == 'state.snapshot'
        assert player_two.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(gm, 'battle-start-permission', 'battle.start', session_sync_id='session-1')
        assert gm.receive_json()['payload']['event'] == 'battle.started'
        assert player_one.receive_json()['payload']['event'] == 'battle.started'
        assert player_two.receive_json()['payload']['event'] == 'battle.started'
        battle_ack = gm.receive_json()
        assert battle_ack['payload']['event'] == 'ack'
        battle_id = battle_ack['payload']['battle_sync_id']

        _send_command(
            player_one,
            'battle-other-character',
            'battle.damage',
            battle_sync_id=battle_id,
            character_sync_id='character-2',
            amount=5,
        )
        error = player_one.receive_json()
        assert error['payload']['event'] == 'error'
        assert 'своего персонажа' in error['payload']['message'].lower()
        assert hub.state[('character', 'character-2')]['hp'] == 20

        _send_command(
            player_one,
            'battle-own-character',
            'battle.damage',
            battle_sync_id=battle_id,
            character_sync_id='character-1',
            amount=11,
        )
        player_one_character = player_one.receive_json()
        player_two_character = player_two.receive_json()
        player_one_battle = player_one.receive_json()
        player_two_battle = player_two.receive_json()
        ack = player_one.receive_json()
        assert player_one_character['payload']['event'] == 'state.upsert'
        assert player_two_character['payload']['event'] == 'state.upsert'
        assert player_one_battle['payload']['event'] == 'battle.state'
        assert player_two_battle['payload']['event'] == 'battle.state'
        assert ack['payload']['event'] == 'ack'
        assert hub.state[('character', 'character-1')]['hp'] == 27
        assert hub.state[('character', 'character-1')]['temporary_hp'] == 0

        _send_command(
            player_one,
            'battle-start-by-player',
            'battle.start',
            session_sync_id='session-1',
        )
        error = player_one.receive_json()
        assert error['payload']['event'] == 'error'



def test_active_battle_is_restored_to_reconnecting_player() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    player_url = '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'

    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(player_url) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'snapshot-reconnect-battle', 'snapshot.publish', entities=_battle_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(gm, 'battle-start-reconnect', 'battle.start', session_sync_id='session-1')
        start = gm.receive_json()
        assert start['payload']['event'] == 'battle.started'
        assert player.receive_json()['payload']['event'] == 'battle.started'
        ack = gm.receive_json()
        battle_id = ack['payload']['battle_sync_id']

    with client.websocket_connect(player_url) as player:
        assert player.receive_json()['payload']['event'] == 'session.ready'
        state_snapshot = player.receive_json()
        battle_snapshot = player.receive_json()
        assert state_snapshot['payload']['event'] == 'state.snapshot'
        assert battle_snapshot['payload']['event'] == 'battle.snapshot'
        assert battle_snapshot['payload']['battle']['sync_id'] == battle_id
        assert battle_snapshot['payload']['battle']['status'] == 'active'
        assert any(
            item['character_sync_id'] == 'character-1'
            for item in battle_snapshot['payload']['projections']
        )




def test_reconnect_snapshot_limits_journal_to_last_100_entries() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    hub.state[('campaign', 'campaign-1')] = {
        'sync_id': 'campaign-1',
        'name': 'Test Campaign',
        'description': '',
    }
    battle_id = 'battle-journal-limit'
    hub.state[('battle', battle_id)] = {
        'sync_id': battle_id,
        'campaign_sync_id': 'campaign-1',
        'session_sync_id': 'session-1',
        'status': 'completed',
    }
    for index in range(101):
        sync_id = f'log-{index:03d}'
        hub.state[('battle_log_entry', sync_id)] = {
            'sync_id': sync_id,
            'battle_sync_id': battle_id,
            'type': 'action_approved',
            'created_at': f'2026-09-19T00:00:{index % 60:02d}.000Z',
        }

    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player:
        assert player.receive_json()['payload']['event'] == 'session.ready'
        snapshot = player.receive_json()
        assert snapshot['payload']['event'] == 'state.snapshot'
        logs = [
            item for item in snapshot['payload']['entities']
            if item['entity'] == 'battle_log_entry'
        ]
        assert len(logs) == 100
        assert {item['data']['sync_id'] for item in logs} == {
            f'log-{index:03d}' for index in range(1, 101)
        }


def test_battle_workspace_turn_action_approval_and_state_application() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'workspace-seed', 'snapshot.publish', entities=_battle_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(gm, 'workspace-battle-start', 'battle.start', session_sync_id='session-1')
        assert gm.receive_json()['payload']['event'] == 'battle.started'
        assert player.receive_json()['payload']['event'] == 'battle.started'
        battle_id = gm.receive_json()['payload']['battle_sync_id']

        _send_command(
            gm,
            'turn-start-1',
            'battle.turn.start',
            battle_sync_id=battle_id,
            character_sync_id='character-1',
        )
        turn_started_gm = gm.receive_json()
        turn_started_player = player.receive_json()
        assert turn_started_gm['payload']['event'] == 'battle.turn.started'
        assert turn_started_player['payload']['event'] == 'battle.turn.started'
        turn_id = turn_started_gm['payload']['data']['sync_id']
        assert turn_started_gm['payload']['current_turn']['character_sync_id'] == 'character-1'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'ack'

        _send_command(
            player,
            'action-submit-1',
            'battle.action.submit',
            battle_sync_id=battle_id,
            actor_character_sync_id='character-1',
            action_type='attack',
            action_name='Fire Bolt',
            target_type='external',
            target_label='Goblin 2',
            attack_formula='1d20+5',
            attack_total=18,
            effect_formula='1d10',
            effect_type='damage',
            effect_total=9,
            metadata={'attack_rolls': [13]},
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.submitted'
        assert player.receive_json()['payload']['event'] == 'battle.action.submitted'
        for websocket in (gm, player):
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
        action_ack = player.receive_json()
        action_id = action_ack['payload']['action_request_sync_id']
        assert action_ack['payload']['event'] == 'ack'
        request = hub.state[('battle_action_request', action_id)]
        assert request['status'] == 'pending_gm'
        assert request['target_type'] == 'external'
        assert hub.state[('character', 'character-1')]['hp'] == 30

        _send_command(
            gm,
            'action-approve-1',
            'battle.action.approve',
            action_request_sync_id=action_id,
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.approved'
        assert player.receive_json()['payload']['event'] == 'battle.action.approved'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'battle.state'
        assert player.receive_json()['payload']['event'] == 'battle.state'
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert hub.state[('battle_action_request', action_id)]['status'] == 'approved'
        assert hub.state[('character', 'character-1')]['hp'] == 30

        _send_command(
            player,
            'action-submit-2',
            'battle.action.submit',
            battle_sync_id=battle_id,
            actor_character_sync_id='character-1',
            action_type='spell',
            action_name='Healing Word',
            target_type='ally',
            target_character_sync_id='character-2',
            effect_formula='1d8+3',
            effect_type='healing',
            effect_total=7,
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.submitted'
        assert player.receive_json()['payload']['event'] == 'battle.action.submitted'
        for websocket in (gm, player):
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
        action_ack = player.receive_json()
        second_action_id = action_ack['payload']['action_request_sync_id']
        assert action_ack['payload']['event'] == 'ack'

        _send_command(
            gm,
            'action-approve-2',
            'battle.action.approve',
            action_request_sync_id=second_action_id,
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.approved'
        assert player.receive_json()['payload']['event'] == 'battle.action.approved'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'state.upsert'
        assert player.receive_json()['payload']['event'] == 'state.upsert'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'battle.state'
        assert player.receive_json()['payload']['event'] == 'battle.state'
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert hub.state[('character', 'character-2')]['hp'] == 27
        assert hub.state[('battle_action_request', second_action_id)]['status'] == 'approved'

        _send_command(
            gm,
            'turn-end-1',
            'battle.turn.end',
            battle_sync_id=battle_id,
            turn_sync_id=turn_id,
        )
        assert gm.receive_json()['payload']['event'] == 'battle.turn.ended'
        assert player.receive_json()['payload']['event'] == 'battle.turn.ended'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert hub.state[('battle_turn', turn_id)]['status'] == 'completed'



def test_battle_action_modify_and_reject_preserve_original_request() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'
        _send_command(gm, 'modify-seed', 'snapshot.publish', entities=_battle_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'
        _send_command(gm, 'modify-battle', 'battle.start', session_sync_id='session-1')
        assert gm.receive_json()['payload']['event'] == 'battle.started'
        assert player.receive_json()['payload']['event'] == 'battle.started'
        battle_id = gm.receive_json()['payload']['battle_sync_id']
        _send_command(gm, 'modify-turn', 'battle.turn.start', battle_sync_id=battle_id, character_sync_id='character-1')
        assert gm.receive_json()['payload']['event'] == 'battle.turn.started'
        assert player.receive_json()['payload']['event'] == 'battle.turn.started'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'ack'

        _send_command(
            player,
            'modify-submit',
            'battle.action.submit',
            battle_sync_id=battle_id,
            actor_character_sync_id='character-1',
            action_type='attack',
            action_name='Fire Bolt',
            target_type='external',
            target_label='Goblin 2',
            attack_formula='1d20+5',
            attack_total=18,
            effect_formula='1d10',
            effect_type='damage',
            effect_total=9,
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.submitted'
        assert player.receive_json()['payload']['event'] == 'battle.action.submitted'
        for websocket in (gm, player):
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
        action_ack = player.receive_json()
        request_id = action_ack['payload']['action_request_sync_id']
        assert action_ack['payload']['event'] == 'ack'

        _send_command(
            gm,
            'modify-action',
            'battle.action.modify',
            action_request_sync_id=request_id,
            modifications={'target_type': 'external', 'target_label': 'Goblin 1', 'effect_total': 7},
            note='GM changed the target and damage.',
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.modified'
        assert player.receive_json()['payload']['event'] == 'battle.action.modified'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'battle.state'
        assert player.receive_json()['payload']['event'] == 'battle.state'
        assert gm.receive_json()['payload']['event'] == 'ack'
        modified = hub.state[('battle_action_request', request_id)]
        assert modified['status'] == 'modified'
        assert modified['target_label'] == 'Goblin 1'
        assert modified['effect_total'] == 7
        assert modified['resolution_note'] == 'GM changed the target and damage.'
        assert modified['metadata']['original']['target_label'] == 'Goblin 2'
        assert modified['metadata']['original']['effect_total'] == 9
        assert modified['metadata']['modifications']['target_label'] == {'before': 'Goblin 2', 'after': 'Goblin 1'}
        assert modified['metadata']['modifications']['effect_total'] == {'before': 9, 'after': 7}
        assert hub.state[('character', 'character-1')]['hp'] == 30

        _send_command(
            player,
            'reject-submit',
            'battle.action.submit',
            battle_sync_id=battle_id,
            actor_character_sync_id='character-1',
            action_type='ability',
            action_name='Dash',
            target_type='self',
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.submitted'
        assert player.receive_json()['payload']['event'] == 'battle.action.submitted'
        for websocket in (gm, player):
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
        reject_ack = player.receive_json()
        reject_id = reject_ack['payload']['action_request_sync_id']
        assert reject_ack['payload']['event'] == 'ack'

        _send_command(
            gm,
            'reject-action',
            'battle.action.reject',
            action_request_sync_id=reject_id,
            reason='Действие уже использовано.',
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.rejected'
        assert player.receive_json()['payload']['event'] == 'battle.action.rejected'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'battle.state'
        assert player.receive_json()['payload']['event'] == 'battle.state'
        assert gm.receive_json()['payload']['event'] == 'ack'
        rejected = hub.state[('battle_action_request', reject_id)]
        assert rejected['status'] == 'rejected'
        assert rejected['resolution_note'] == 'Действие уже использовано.'



def test_battle_workspace_is_present_after_reconnect_snapshot() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    player_url = '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'

    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(player_url) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'reconnect-seed', 'snapshot.publish', entities=_battle_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(gm, 'reconnect-battle-start', 'battle.start', session_sync_id='session-1')
        assert gm.receive_json()['payload']['event'] == 'battle.started'
        assert player.receive_json()['payload']['event'] == 'battle.started'
        battle_id = gm.receive_json()['payload']['battle_sync_id']

        _send_command(
            gm,
            'reconnect-turn-start',
            'battle.turn.start',
            battle_sync_id=battle_id,
            character_sync_id='character-1',
        )
        assert gm.receive_json()['payload']['event'] == 'battle.turn.started'
        assert player.receive_json()['payload']['event'] == 'battle.turn.started'
        assert gm.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert gm.receive_json()['payload']['event'] == 'ack'

        _send_command(
            player,
            'reconnect-action',
            'battle.action.submit',
            battle_sync_id=battle_id,
            actor_character_sync_id='character-1',
            action_type='attack',
            action_name='Dagger',
            target_type='external',
            target_label='Goblin 1',
            attack_total=17,
            effect_type='damage',
            effect_total=5,
        )
        assert gm.receive_json()['payload']['event'] == 'battle.action.submitted'
        assert player.receive_json()['payload']['event'] == 'battle.action.submitted'
        for websocket in (gm, player):
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
            assert websocket.receive_json()['payload']['event'] == 'battle.journal.entry'
        assert player.receive_json()['payload']['event'] == 'ack'

    with client.websocket_connect(player_url) as player:
        assert player.receive_json()['payload']['event'] == 'session.ready'
        snapshot = player.receive_json()
        assert snapshot['payload']['event'] == 'state.snapshot'
        entities = snapshot['payload']['entities']
        entity_names = {item['entity'] for item in entities}
        assert {'battle', 'battle_turn', 'battle_action_request', 'battle_log_entry'} <= entity_names
        assert any(
            item['entity'] == 'battle_turn'
            and item['data']['battle_sync_id'] == battle_id
            and item['data']['status'] == 'active'
            for item in entities
        )
        assert any(
            item['entity'] == 'battle_action_request'
            and item['data']['battle_sync_id'] == battle_id
            and item['data']['status'] == 'pending_gm'
            for item in entities
        )
        assert any(
            item['entity'] == 'battle_log_entry'
            and item['data']['battle_sync_id'] == battle_id
            for item in entities
        )


def _session_workspace_snapshot() -> list[dict[str, object]]:
    entities = [
        {
            'entity': 'campaign',
            'data': {'sync_id': 'campaign-1', 'name': 'Test Campaign'},
        },
        {
            'entity': 'campaign_member',
            'data': {
                'sync_id': 'gm-member-1', 'campaign_sync_id': 'campaign-1', 'name': 'GM',
                'role': 'gm', 'client_id': 'gm-1', 'linked_character_sync_id': None,
            },
        },
        {
            'entity': 'campaign_member',
            'data': {
                'sync_id': 'player-member-1', 'campaign_sync_id': 'campaign-1', 'name': 'Alice',
                'role': 'player', 'client_id': 'player-1', 'linked_character_sync_id': 'character-1',
            },
        },
        {
            'entity': 'character',
            'data': {
                'sync_id': 'character-1', 'name': 'Kael', 'level': 5, 'xp': 6500,
                'hp': 42, 'max_hp': 42, 'temporary_hp': 0,
            },
        },
        {
            'entity': 'session',
            'data': {
                'sync_id': 'session-1', 'campaign_sync_id': 'campaign-1', 'title': 'Session 7',
                'status': 'active',
            },
        },
    ]
    return entities


def test_session_reward_is_atomic_and_duplicate_safe() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        _send_command(gm, 'workspace-seed', 'snapshot.publish', entities=_session_workspace_snapshot())
        assert gm.receive_json()['payload']['event'] == 'ack'

        _send_command(gm, 'reward-1', 'session.reward.apply', session_sync_id='session-1', character_sync_id='character-1', amount=250, reason='Культисты')
        messages = [gm.receive_json() for _ in range(5)]
        assert [m['payload']['event'] for m in messages[:4]] == ['state.upsert', 'state.upsert', 'state.upsert', 'state.upsert']
        character_event = messages[0]['payload']
        assert character_event['entity'] == 'character'
        assert character_event['data']['sync_id'] == 'character-1'
        assert character_event['data']['xp'] == 6750
        assert character_event['data']['level'] == 5
        ack = messages[4]
        assert ack['payload']['event'] == 'ack'
        assert ack['payload']['character']['xp'] == 6750
        assert ack['payload']['character']['level'] == 5
        assert ack['payload']['reward']['amount'] == 250
        assert ack['payload']['xp_transaction']['xp_after'] == 6750
        assert hub.state[('character', 'character-1')]['xp'] == 6750
        assert sum(1 for kind, _ in hub.state if kind == 'session_reward') == 1
        assert sum(1 for kind, _ in hub.state if kind == 'session_event') == 1
        assert sum(1 for kind, _ in hub.state if kind == 'xp_transaction') == 1

        _send_command(gm, 'reward-1', 'session.reward.apply', session_sync_id='session-1', character_sync_id='character-1', amount=250)
        duplicate = gm.receive_json()
        assert duplicate['payload']['event'] == 'ack'
        assert duplicate['payload']['duplicate'] is True
        assert hub.state[('character', 'character-1')]['xp'] == 6750
        assert sum(1 for kind, _ in hub.state if kind == 'session_reward') == 1


def test_player_cannot_mutate_session_workspace_and_loot_claim_grants_inventory() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm, client.websocket_connect('/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice') as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'
        _send_command(gm, 'loot-seed', 'snapshot.publish', entities=_session_workspace_snapshot() + [{
            'entity': 'session_loot',
            'data': {
                'sync_id': 'loot-1', 'session_sync_id': 'session-1', 'name': 'Ancient Sword',
                'description': '', 'quantity': 1, 'source': 'Goblin Chief', 'status': 'available',
                'claimed_by_character_sync_id': None, 'created_at': '2026-09-29T00:00:00Z', 'updated_at': '2026-09-29T00:00:00Z',
            },
        }])
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        player.send_json({
            'protocol': PROTOCOL, 'type': 'command', 'id': 'player-note-1', 'client_id': 'player-1', 'campaign_id': 'campaign-1',
            'payload': {'command': 'state.upsert', 'entity': 'session_note', 'data': {
                'sync_id': 'note-evil', 'session_sync_id': 'session-1', 'title': 'x', 'content': 'x',
                'created_at': '2026-09-29T00:00:00Z', 'updated_at': '2026-09-29T00:00:00Z',
            }},
        })
        error = player.receive_json()
        assert error['payload']['event'] == 'error'

        _send_command(gm, 'claim-1', 'session.loot.claim', loot_sync_id='loot-1', character_sync_id='character-1')
        messages = [gm.receive_json() for _ in range(4)]
        assert [m['payload']['event'] for m in messages[:3]] == ['state.upsert', 'state.upsert', 'state.upsert']
        assert messages[3]['payload']['event'] == 'ack'
        assert hub.state[('session_loot', 'loot-1')]['status'] == 'claimed'
        assert any(kind == 'item' for kind, _ in hub.state)
        assert any(kind == 'session_event' for kind, _ in hub.state)


def test_session_workspace_entities_round_trip_in_reconnect_snapshot() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm, client.websocket_connect('/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice') as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'
        snapshot = _session_workspace_snapshot() + [
            {'entity': 'session_note', 'data': {'sync_id': 'note-1', 'session_sync_id': 'session-1', 'title': 'Entry', 'content': 'Found a door', 'created_at': '2026-09-29T10:00:00Z', 'updated_at': '2026-09-29T10:00:00Z'}},
            {'entity': 'session_event', 'data': {'sync_id': 'event-1', 'session_sync_id': 'session-1', 'type': 'custom', 'title': 'Entered ruins', 'description': '', 'metadata': {}, 'created_at': '2026-09-29T10:01:00Z', 'created_by': 'GM'}},
            {'entity': 'session_reward', 'data': {'sync_id': 'reward-1', 'session_sync_id': 'session-1', 'character_sync_id': 'character-1', 'type': 'xp', 'amount': 100, 'reason': 'Task', 'created_at': '2026-09-29T10:02:00Z', 'created_by': 'GM'}},
            {'entity': 'session_loot', 'data': {'sync_id': 'loot-1', 'session_sync_id': 'session-1', 'name': 'Potion', 'description': '', 'quantity': 2, 'source': 'Chest', 'status': 'available', 'claimed_by_character_sync_id': None, 'created_at': '2026-09-29T10:03:00Z', 'updated_at': '2026-09-29T10:03:00Z'}},
        ]
        _send_command(gm, 'workspace-roundtrip', 'snapshot.publish', entities=snapshot)
        assert gm.receive_json()['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'
        keys = {(kind, sync_id) for (kind, sync_id) in hub.state}
        assert {('session_note', 'note-1'), ('session_event', 'event-1'), ('session_reward', 'reward-1'), ('session_loot', 'loot-1')} <= keys





def test_campaign_delete_cascades_session_workspace_and_battle_children() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    hub.state.update({
        ('campaign', 'campaign-1'): {'sync_id': 'campaign-1'},
        ('session', 'session-1'): {'sync_id': 'session-1', 'campaign_sync_id': 'campaign-1'},
        ('session_note', 'note-1'): {'sync_id': 'note-1', 'session_sync_id': 'session-1'},
        ('session_event', 'event-1'): {'sync_id': 'event-1', 'session_sync_id': 'session-1'},
        ('session_reward', 'reward-1'): {'sync_id': 'reward-1', 'session_sync_id': 'session-1', 'character_sync_id': 'character-1'},
        ('session_loot', 'loot-1'): {'sync_id': 'loot-1', 'session_sync_id': 'session-1'},
        ('battle', 'battle-1'): {'sync_id': 'battle-1', 'campaign_sync_id': 'campaign-1', 'session_sync_id': 'session-1'},
        ('battle_turn', 'turn-1'): {'sync_id': 'turn-1', 'battle_sync_id': 'battle-1'},
        ('battle_action_request', 'request-1'): {'sync_id': 'request-1', 'battle_sync_id': 'battle-1'},
        ('battle_log_entry', 'log-1'): {'sync_id': 'log-1', 'battle_sync_id': 'battle-1'},
    })
    hub._delete_state_entry('campaign', 'campaign-1')
    assert hub.state == {}


def _receive_until_ack(ws, command_id: str) -> dict:
    while True:
        event = ws.receive_json()
        payload = event.get('payload', {})
        if payload.get('event') == 'ack' and payload.get('command_id') == command_id:
            return event


def test_v1_gameplay_state_commands_are_authoritative_and_synced() -> None:
    hub = HubServer(
        campaign_id='campaign-1',
        campaign_name='Test Campaign',
        gm_name='GM',
        invite_token='token',
    )
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        '/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM'
    ) as gm, client.websocket_connect(
        '/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice'
    ) as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        assert gm.receive_json()['payload']['event'] == 'player.joined'

        _send_command(gm, 'snapshot-v1-1', 'snapshot.publish', entities=_battle_snapshot())
        assert _receive_until_ack(gm, 'snapshot-v1-1')['payload']['event'] == 'ack'
        assert player.receive_json()['payload']['event'] == 'state.snapshot'

        _send_command(
            gm,
            'hp-down-v1',
            'character.hp.modify',
            character_sync_id='character-1',
            delta=-38,
            session_sync_id='session-1',
        )
        gm_ack = _receive_until_ack(gm, 'hp-down-v1')
        player_event = player.receive_json()
        while player_event['payload'].get('event') != 'state.upsert' or player_event['payload'].get('entity') != 'character':
            player_event = player.receive_json()
        assert gm_ack['payload']['character']['hp'] == 0
        assert gm_ack['payload']['character']['life_state'] == 'downed'
        assert hub.state[('character', 'character-1')]['life_state'] == 'downed'
        assert player_event['payload']['data']['life_state'] == 'downed'

        _send_command(
            gm,
            'life-dead-v1',
            'character.life_state.set',
            character_sync_id='character-1',
            life_state='dead',
            session_sync_id='session-1',
        )
        dead_ack = _receive_until_ack(gm, 'life-dead-v1')
        assert dead_ack['payload']['character']['life_state'] == 'dead'

        _send_command(
            gm,
            'life-revive-v1',
            'character.life_state.set',
            character_sync_id='character-1',
            life_state='normal',
            session_sync_id='session-1',
        )
        revive_ack = _receive_until_ack(gm, 'life-revive-v1')
        assert revive_ack['payload']['character']['life_state'] == 'normal'

        _send_command(
            gm,
            'currency-v1',
            'character.currency.grant',
            character_sync_id='character-1',
            currency='gold',
            amount=150,
            session_sync_id='session-1',
            reason='Награда за квест',
        )
        currency_ack = _receive_until_ack(gm, 'currency-v1')
        assert currency_ack['payload']['character']['gold'] == 150
        assert currency_ack['payload']['reward']['type'] == 'currency'
        assert currency_ack['payload']['reward']['currency'] == 'gold'

        _send_command(
            gm,
            'inspiration-v1',
            'character.inspiration.grant',
            character_sync_id='character-1',
            session_sync_id='session-1',
        )
        inspiration_ack = _receive_until_ack(gm, 'inspiration-v1')
        assert inspiration_ack['payload']['character']['inspiration'] == 1

        _send_command(
            gm,
            'condition-add-v1',
            'character.condition.apply',
            character_sync_id='character-1',
            session_sync_id='session-1',
            name='Poisoned',
            description='Отравлен токсином.',
            source_label='Goblin Assassin',
            duration_rounds=2,
            remaining_rounds=2,
            scope='character',
        )
        condition_ack = _receive_until_ack(gm, 'condition-add-v1')
        condition = condition_ack['payload']['condition']
        assert condition['name'] == 'Poisoned'
        assert condition['remaining_rounds'] == 2
        assert condition['active'] == 1
        assert hub.state[('character_condition', condition['sync_id'])]['active'] == 1

        _send_command(
            gm,
            'condition-remove-v1',
            'character.condition.remove',
            condition_sync_id=condition['sync_id'],
            session_sync_id='session-1',
        )
        remove_ack = _receive_until_ack(gm, 'condition-remove-v1')
        assert remove_ack['payload']['condition']['active'] == 0
        assert hub.state[('character_condition', condition['sync_id'])]['remaining_rounds'] == 0

        player.send_json({
            'protocol': PROTOCOL,
            'type': 'command',
            'id': 'custom-action-v1',
            'client_id': 'player-1',
            'campaign_id': 'campaign-1',
            'payload': {
                'command': 'state.upsert',
                'entity': 'custom_action',
                'data': {
                    'sync_id': 'custom-action-1',
                    'character_sync_id': 'character-1',
                    'name': 'Опрокинуть жаровню',
                    'description': 'Толкаю жаровню на врага.',
                    'attack_formula': '1d20 + 5',
                    'effect_formula': '1d6',
                    'effect_type': 'damage',
                },
            },
        })
        custom_action = gm.receive_json()
        assert custom_action['payload']['event'] == 'state.upsert'
        assert custom_action['payload']['entity'] == 'custom_action'
        assert custom_action['payload']['data']['name'] == 'Опрокинуть жаровню'
        assert hub.state[('custom_action', 'custom-action-1')]['character_sync_id'] == 'character-1'
        custom_ack = _receive_until_ack(player, 'custom-action-v1')
        assert custom_ack['payload']['event'] == 'ack'


def test_battle_events_stay_in_battle_journal_not_session_history() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        snapshot = _battle_snapshot() + [
            {'entity': 'battle', 'data': {
                'sync_id': 'battle-1', 'campaign_sync_id': 'campaign-1', 'session_sync_id': 'session-1',
                'name': 'Battle', 'status': 'active', 'started_at': '2026-10-01T12:00:00Z',
                'created_at': '2026-10-01T12:00:00Z', 'updated_at': '2026-10-01T12:00:00Z',
            }},
        ]
        _send_command(gm, 'battle-events-snapshot', 'snapshot.publish', entities=snapshot)
        assert _receive_until_ack(gm, 'battle-events-snapshot')['payload']['event'] == 'ack'

        _send_command(
            gm, 'battle-condition', 'character.condition.apply',
            character_sync_id='character-1', session_sync_id='session-1', battle_sync_id='battle-1',
            name='Poisoned', description='', duration_rounds=2, remaining_rounds=2,
        )
        ack = _receive_until_ack(gm, 'battle-condition')
        assert ack['payload']['battle_sync_id'] == 'battle-1'
        assert not any(
            data.get('event_type') == 'condition_applied'
            and data.get('session_sync_id') == 'session-1'
            for (entity, _), data in hub.state.items()
            if entity == 'session_event'
        )
        assert any(
            data.get('battle_sync_id') == 'battle-1' and data.get('type') == 'condition_applied'
            for (entity, _), data in hub.state.items()
            if entity == 'battle_log_entry'
        )

        _send_command(
            gm, 'battle-death', 'character.life_state.set',
            character_sync_id='character-1', session_sync_id='session-1', battle_sync_id='battle-1',
            life_state='dead',
        )
        _receive_until_ack(gm, 'battle-death')
        _send_command(
            gm, 'battle-revive', 'character.life_state.set',
            character_sync_id='character-1', session_sync_id='session-1', battle_sync_id='battle-1',
            life_state='normal',
        )
        _receive_until_ack(gm, 'battle-revive')
        session_event_types = {
            data.get('type')
            for (entity, _), data in hub.state.items()
            if entity == 'session_event' and data.get('session_sync_id') == 'session-1'
        }
        assert 'death' not in session_event_types
        assert 'revived' not in session_event_types
        battle_event_types = {
            data.get('type')
            for (entity, _), data in hub.state.items()
            if entity == 'battle_log_entry' and data.get('battle_sync_id') == 'battle-1'
        }
        assert {'condition_applied', 'death', 'revived'} <= battle_event_types


def test_member_link_character_can_publish_initial_loadout_in_one_operation() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm, \
         client.websocket_connect('/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Player') as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        hub.state[('campaign_member', 'member-1')] = {
            'sync_id': 'member-1', 'campaign_sync_id': 'campaign-1', 'client_id': 'player-1',
            'role': 'player', 'linked_character_sync_id': None,
        }
        hub.state[('campaign', 'campaign-1')] = {'sync_id': 'campaign-1', 'name': 'Test Campaign'}

        _send_command(
            player,
            'link-with-loadout',
            'member.link_character',
            member_sync_id='member-1',
            character={'sync_id': 'character-1', 'name': 'Mira', 'hp': 10, 'max_hp': 10},
            loadout=[
                {'entity': 'attack', 'data': {'sync_id': 'attack-1', 'character_sync_id': 'character-1', 'name': 'Longsword'}},
                {'entity': 'spell', 'data': {'sync_id': 'spell-1', 'character_sync_id': 'character-1', 'name': 'Fire Bolt'}},
                {'entity': 'ability', 'data': {'sync_id': 'ability-1', 'character_sync_id': 'character-1', 'name': 'Second Wind'}},
                {'entity': 'item', 'data': {'sync_id': 'item-1', 'character_sync_id': 'character-1', 'name': 'Potion'}},
            ],
        )

        gm_entities = []
        for _ in range(10):
            message = gm.receive_json()
            payload = message.get('payload', {})
            entity = payload.get('entity')
            if entity is not None:
                gm_entities.append(entity)
            if {'character', 'campaign_member', 'attack', 'spell', 'ability', 'item'} <= set(gm_entities):
                break
        assert {'character', 'campaign_member', 'attack', 'spell', 'ability', 'item'} <= set(gm_entities)

        player_entities = []
        for _ in range(2):
            message = player.receive_json()
            payload = message.get('payload', {})
            entity = payload.get('entity')
            if entity is not None:
                player_entities.append(entity)
        assert {'character', 'campaign_member'} <= set(player_entities)
        ack = _receive_until_ack(player, 'link-with-loadout')
        assert ack['payload']['published'] == 4
        assert hub.state[('attack', 'attack-1')]['name'] == 'Longsword'
        assert hub.state[('spell', 'spell-1')]['name'] == 'Fire Bolt'


def test_character_loadout_request_returns_all_action_entities() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        snapshot = _battle_snapshot() + [
            {'entity': 'attack', 'data': {'sync_id': 'attack-1', 'character_sync_id': 'character-1', 'name': 'Longsword', 'sort_order': 0}},
            {'entity': 'spell', 'data': {'sync_id': 'spell-1', 'character_sync_id': 'character-1', 'name': 'Fire Bolt', 'sort_order': 0}},
            {'entity': 'ability', 'data': {'sync_id': 'ability-1', 'character_sync_id': 'character-1', 'name': 'Second Wind', 'sort_order': 0}},
            {'entity': 'item', 'data': {'sync_id': 'item-1', 'character_sync_id': 'character-1', 'name': 'Potion', 'sort_order': 0}},
            {'entity': 'custom_action', 'data': {'sync_id': 'custom-1', 'character_sync_id': 'character-1', 'name': 'Improvised', 'sort_order': 0}},
        ]
        _send_command(gm, 'loadout-snapshot', 'snapshot.publish', entities=snapshot)
        assert _receive_until_ack(gm, 'loadout-snapshot')['payload']['event'] == 'ack'
        _send_command(gm, 'loadout-request', 'character.loadout.request', character_sync_id='character-1')
        ack = _receive_until_ack(gm, 'loadout-request')
        loadout = ack['payload']['loadout']
        assert {item['entity'] for item in loadout} == {'attack', 'spell', 'ability', 'item', 'custom_action'}
        assert {item['data']['name'] for item in loadout} == {'Longsword', 'Fire Bolt', 'Second Wind', 'Potion', 'Improvised'}


def test_character_loadout_publish_accepts_player_child_entities_and_gm_can_request_them() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm, \
         client.websocket_connect('/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Player') as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        hub.state[('campaign_member', 'member-1')] = {
            'sync_id': 'member-1', 'campaign_sync_id': 'campaign-1', 'client_id': 'player-1',
            'role': 'player', 'linked_character_sync_id': 'character-1',
        }
        hub.state[('character', 'character-1')] = {
            'sync_id': 'character-1', 'name': 'Mira', 'hp': 10, 'max_hp': 10,
        }
        entities = [
            {'entity': 'attack', 'data': {'sync_id': 'attack-1', 'character_sync_id': 'character-1', 'name': 'Longsword'}},
            {'entity': 'spell', 'data': {'sync_id': 'spell-1', 'character_sync_id': 'character-1', 'name': 'Fire Bolt'}},
            {'entity': 'ability', 'data': {'sync_id': 'ability-1', 'character_sync_id': 'character-1', 'name': 'Second Wind'}},
            {'entity': 'item', 'data': {'sync_id': 'item-1', 'character_sync_id': 'character-1', 'name': 'Potion'}},
        ]
        _send_command(player, 'loadout-publish', 'character.loadout.publish', character_sync_id='character-1', entities=entities)
        ack = _receive_until_ack(player, 'loadout-publish')
        assert ack['payload']['published'] == 4
        _send_command(gm, 'loadout-request', 'character.loadout.request', character_sync_id='character-1')
        loadout_ack = _receive_until_ack(gm, 'loadout-request')
        names = {item['data']['name'] for item in loadout_ack['payload']['loadout']}
        assert names == {'Longsword', 'Fire Bolt', 'Second Wind', 'Potion'}


def test_character_loadout_request_pulls_fresh_loadout_from_online_player() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=gm-1&campaign_id=campaign-1&role=gm&display_name=GM') as gm, \
         client.websocket_connect('/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Player') as player:
        assert gm.receive_json()['payload']['event'] == 'session.ready'
        assert player.receive_json()['payload']['event'] == 'session.ready'
        hub.state[('campaign_member', 'member-1')] = {
            'sync_id': 'member-1', 'campaign_sync_id': 'campaign-1', 'client_id': 'player-1',
            'role': 'player', 'linked_character_sync_id': 'character-1',
        }
        hub.state[('character', 'character-1')] = {
            'sync_id': 'character-1', 'name': 'Mira', 'hp': 10, 'max_hp': 10,
        }

        _send_command(gm, 'loadout-request', 'character.loadout.request', character_sync_id='character-1')
        ack = _receive_until_ack(gm, 'loadout-request')
        assert ack['payload']['loadout'] == []

        pull = player.receive_json()
        assert pull['payload']['event'] == 'character.loadout.pull'
        assert pull['payload']['character_sync_id'] == 'character-1'


def test_character_loadout_publish_replaces_stale_actions() -> None:
    hub = HubServer(campaign_id='campaign-1', campaign_name='Test Campaign', gm_name='GM', invite_token='token')
    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect('/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Player') as player:
        assert player.receive_json()['payload']['event'] == 'session.ready'
        hub.state[('campaign_member', 'member-1')] = {
            'sync_id': 'member-1', 'campaign_sync_id': 'campaign-1', 'client_id': 'player-1',
            'role': 'player', 'linked_character_sync_id': 'character-1',
        }
        hub.state[('character', 'character-1')] = {'sync_id': 'character-1', 'name': 'Mira'}
        hub.state[('attack', 'old-attack')] = {'sync_id': 'old-attack', 'character_sync_id': 'character-1', 'name': 'Old'}
        _send_command(
            player,
            'loadout-publish-2',
            'character.loadout.publish',
            character_sync_id='character-1',
            entities=[{'entity': 'attack', 'data': {'sync_id': 'new-attack', 'character_sync_id': 'character-1', 'name': 'New'}}],
        )
        assert _receive_until_ack(player, 'loadout-publish-2')['payload']['published'] == 1
        assert ('attack', 'old-attack') not in hub.state
        assert hub.state[('attack', 'new-attack')]['name'] == 'New'


def test_player_can_unlink_own_character_without_leaving_campaign() -> None:
    hub = HubServer(
        campaign_id="campaign-1",
        campaign_name="Test Campaign",
        gm_name="GM",
        invite_token="token",
    )
    hub.state[("campaign_member", "member-1")] = {
        "sync_id": "member-1",
        "campaign_sync_id": "campaign-1",
        "name": "Alice",
        "role": "player",
        "client_id": "player-1",
        "linked_character_sync_id": "character-1",
        "created_at": "2026-09-19T00:00:00Z",
    }
    hub.state[("character", "character-1")] = {
        "sync_id": "character-1",
        "name": "Rogue",
        "level": 5,
        "hp": 30,
        "max_hp": 42,
    }
    hub.state[("attack", "attack-1")] = {
        "sync_id": "attack-1",
        "character_sync_id": "character-1",
        "name": "Dagger",
    }

    client = TestClient(build_app(hub, port=8765))
    with client.websocket_connect(
        "/ws?token=token&client_id=player-1&campaign_id=campaign-1&role=player&display_name=Alice"
    ) as ws:
        assert ws.receive_json()["payload"]["event"] == "session.ready"
        snapshot = ws.receive_json()
        assert snapshot["payload"]["event"] == "state.snapshot"

        ws.send_json(
            {
                "protocol": PROTOCOL,
                "type": "command",
                "id": "unlink-1",
                "client_id": "player-1",
                "campaign_id": "campaign-1",
                "payload": {
                    "command": "member.unlink_character",
                    "member_sync_id": "member-1",
                },
            }
        )

        member_update = ws.receive_json()
        assert member_update["payload"]["event"] == "state.upsert"
        assert member_update["payload"]["entity"] == "campaign_member"
        assert member_update["payload"]["data"]["linked_character_sync_id"] is None

        ack = ws.receive_json()
        assert ack["payload"]["event"] == "ack"
        assert ack["payload"]["unlinked"] is True

    assert hub.state[("campaign_member", "member-1")]["linked_character_sync_id"] is None
    assert ("character", "character-1") not in hub.state
    assert ("attack", "attack-1") not in hub.state
