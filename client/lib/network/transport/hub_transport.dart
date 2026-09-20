import 'dart:typed_data';

enum TransportState { disconnected, connecting, connected, reconnecting, failed }

abstract interface class HubTransport {
  Future<void> connect({required String host, required int port, required String token});
  Future<void> send(Uint8List data);
  Stream<Uint8List> get messages;
  Stream<TransportState> get state;
  Future<void> disconnect();
}
