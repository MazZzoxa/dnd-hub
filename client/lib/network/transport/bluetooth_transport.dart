import 'dart:typed_data';

import 'hub_transport.dart';

/// Future local fallback. Intentionally not enabled in v0.5 Phase 1.
class BluetoothTransport implements HubTransport {
  @override
  Stream<Uint8List> get messages => const Stream<Uint8List>.empty();

  @override
  Stream<TransportState> get state =>
      Stream<TransportState>.value(TransportState.disconnected);

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String token,
  }) async {
    throw UnsupportedError('Bluetooth transport is planned for a later phase.');
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(Uint8List data) async {
    throw UnsupportedError('Bluetooth transport is planned for a later phase.');
  }
}
