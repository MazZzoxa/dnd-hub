import 'dart:typed_data';

import 'hub_transport.dart';

/// Phase 2 transport placeholder.
///
/// The actual Windows/Android Wi-Fi Direct implementation belongs in the
/// platform bridges; keeping this adapter here prevents the sync layer from
/// depending on a concrete transport.
class WifiP2pTransport implements HubTransport {
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
    throw UnsupportedError(
      'Wi-Fi P2P native transport is scheduled for v0.5 Phase 2.',
    );
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> send(Uint8List data) async {
    throw UnsupportedError(
      'Wi-Fi P2P native transport is scheduled for v0.5 Phase 2.',
    );
  }
}
