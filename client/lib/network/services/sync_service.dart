import 'dart:async';

import '../../data/models/character_model.dart';
import '../../data/models/campaign_member_model.dart';
import '../connection_manager.dart';
import '../protocol/network_message.dart';
import 'local_sync_store.dart';

class SyncService {
  final ConnectionManager connectionManager;
  final LocalSyncStore store;
  StreamSubscription<String>? _messages;
  StreamSubscription<dynamic>? _connectionStates;
  final StreamController<NetworkMessage> _events = StreamController.broadcast();

  bool _publishingSnapshot = false;

  SyncService(this.connectionManager, {LocalSyncStore? store})
      : store = store ?? LocalSyncStore() {
    _messages = connectionManager.messageStream.listen(_onMessage);
    _connectionStates = connectionManager.stateStream.listen(_onConnectionState);
  }

  Stream<NetworkMessage> get events => _events.stream;
  bool get connected => connectionManager.connected;
  String get clientId => connectionManager.clientId;

  Future<void> publishCharacter(CharacterModel character) async {
    await publishEntity('character', character.toMap());
  }

  Future<void> publishEntity(String entity, Map<String, dynamic> data) async {
    if (!connected) return;
    try {
      final prepared = await store.preparePayload(entity, data);
      if (!await store.isPayloadInCampaign(entity, prepared, connectionManager.campaignId)) return;
      await connectionManager.sendCommand(
        'state.upsert',
        payload: {'entity': entity, 'data': prepared},
      );
    } catch (_) {
      // Local UI operations must not fail merely because a network packet
      // could not be produced.
    }
  }

  Future<void> linkOwnCharacter({required CampaignMemberModel member, required CharacterModel character}) async {
    if (!connected || member.syncId.isEmpty || member.clientId != clientId) return;
    final prepared = await store.preparePayload('character', character.toMap());
    await connectionManager.sendCommand(
      'member.link_character',
      payload: {
        'member_sync_id': member.syncId,
        'character': prepared,
      },
    );
  }

  Future<void> leaveCampaign({required CampaignMemberModel member}) async {
    if (!connected) throw StateError('Нет подключения к LAN-кампании.');
    if (member.clientId != clientId || member.role != CampaignRole.player) {
      throw StateError('Только подключённый игрок может покинуть эту кампанию.');
    }
    if (member.syncId.isEmpty) {
      throw StateError('У участника нет sync_id.');
    }

    String? commandId;
    final completer = Completer<void>();
    late StreamSubscription<NetworkMessage> subscription;
    subscription = events.listen((event) {
      final eventName = event.payload['event']?.toString();
      if (commandId == null || event.payload['command_id']?.toString() != commandId) return;
      if (eventName == 'ack' && event.payload['left'] == true) {
        if (!completer.isCompleted) completer.complete();
      } else if (eventName == 'error' && !completer.isCompleted) {
        completer.completeError(
          StateError(event.payload['message']?.toString() ?? 'Не удалось покинуть кампанию.'),
        );
      }
    });

    try {
      commandId = await connectionManager.sendCommand(
        'member.leave',
        payload: {'member_sync_id': member.syncId},
      );
      if (commandId == null) throw StateError('Не удалось отправить запрос на выход.');
      await completer.future.timeout(const Duration(seconds: 5));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> publishDelete(String entity, String syncId) async {
    if (!connected || syncId.isEmpty) return;
    await connectionManager.sendCommand(
      'state.delete',
      payload: {'entity': entity, 'sync_id': syncId},
    );
  }

  Future<void> publishCampaignSnapshot(String campaignSyncId) async {
    if (!connected ||
        campaignSyncId.isEmpty ||
        campaignSyncId != connectionManager.campaignId ||
        _publishingSnapshot) return;
    _publishingSnapshot = true;
    try {
      final entities = await store.exportCampaignSnapshot(campaignSyncId);
      await connectionManager.sendCommand(
        'snapshot.publish',
        payload: {'entities': entities},
      );
    } catch (_) {
      // Snapshot is best-effort; ordinary entity events remain usable.
    } finally {
      _publishingSnapshot = false;
    }
  }

  Future<void> ping() async {
    await connectionManager.sendCommand('ping', payload: const {});
  }

  Future<void> _onConnectionState(dynamic state) async {
    // Once the GM is connected, the local campaign becomes the initial
    // authoritative snapshot for the temporary LAN server. ConnectionManager
    // exposes the campaign sync_id, so no local integer ID crosses the network.
    if (!connectionManager.connected || connectionManager.role != 'gm') return;
    if (state.toString().endsWith('connected')) {
      await publishCampaignSnapshot(connectionManager.campaignId);
    }
  }

  Future<void> _onMessage(String raw) async {
    try {
      final message = NetworkMessage.fromEncoded(raw);
      if (message.protocol != NetworkMessage.protocolVersion) return;
      final eventName = message.payload['event']?.toString();

      if (eventName == 'state.upsert') {
        final entity = message.payload['entity']?.toString() ?? '';
        final data = message.payload['data'];
        if (data is Map) {
          await store.applyEntity(
            entity,
            data.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } else if (eventName == 'state.delete') {
        final entity = message.payload['entity']?.toString() ?? '';
        final syncId = message.payload['sync_id']?.toString() ?? '';
        await store.deleteEntity(entity, syncId);
      } else if (eventName == 'state.snapshot') {
        final rawEntities = message.payload['entities'];
        if (rawEntities is List) {
          final campaignSyncId = message.campaignId.isNotEmpty
              ? message.campaignId
              : connectionManager.campaignId;
          final entities = [
            for (final rawEntity in rawEntities)
              if (rawEntity is Map)
                rawEntity.map((key, value) => MapEntry(key.toString(), value)),
          ];
          await store.applySnapshot(campaignSyncId, entities);
        }
      }

      if (!_events.isClosed) _events.add(message);
    } catch (_) {
      // Bad packets are ignored at the protocol boundary.
    }
  }

  Future<void> dispose() async {
    await _messages?.cancel();
    await _connectionStates?.cancel();
    await _events.close();
  }
}
