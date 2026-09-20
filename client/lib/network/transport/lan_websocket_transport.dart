import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'hub_transport.dart';

class LanWebSocketTransport implements HubTransport {
  WebSocket? _socket;
  final StreamController<Uint8List> _messages = StreamController.broadcast();
  final StreamController<TransportState> _state = StreamController.broadcast();
  final HttpClient _directHttpClient = HttpClient()..findProxy = (_) => 'DIRECT';
  TransportState _currentState = TransportState.disconnected;

  String clientId = '';
  String campaignId = '';
  String role = 'player';
  String displayName = '';

  TransportState get currentState => _currentState;

  void _setState(TransportState value) {
    _currentState = value;
    if (!_state.isClosed) _state.add(value);
  }

  @override
  Stream<Uint8List> get messages => _messages.stream;

  @override
  Stream<TransportState> get state => _state.stream;

  @override
  Future<void> connect({
    required String host,
    required int port,
    required String token,
  }) async {
    await disconnect();
    _setState(TransportState.connecting);
    try {
      final uri = Uri(
        scheme: 'ws',
        host: host,
        port: port,
        path: '/ws',
        queryParameters: {
          'token': token,
          'client_id': clientId,
          'campaign_id': campaignId,
          'role': role,
          'display_name': displayName,
        },
      );
      final socket = await WebSocket.connect(
        uri.toString(),
        customClient: _directHttpClient,
      );
      _socket = socket;
      _setState(TransportState.connected);
      socket.listen(
        (data) {
          final text = data is String ? data : utf8.decode(data as List<int>);
          if (!_messages.isClosed) {
            _messages.add(Uint8List.fromList(utf8.encode(text)));
          }
        },
        onError: (_) => _setState(TransportState.failed),
        onDone: () {
          _socket = null;
          if (_currentState != TransportState.disconnected) {
            _setState(TransportState.disconnected);
          }
        },
        cancelOnError: true,
      );
    } catch (_) {
      _setState(TransportState.failed);
      rethrow;
    }
  }

  @override
  Future<void> send(Uint8List data) async {
    final socket = _socket;
    if (socket == null || _currentState != TransportState.connected) {
      throw StateError('Transport is not connected.');
    }
    socket.add(utf8.decode(data));
  }

  @override
  Future<void> disconnect() async {
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.normalClosure, 'client disconnect');
      } catch (_) {}
    }
    _setState(TransportState.disconnected);
  }

  Future<void> dispose() async {
    await disconnect();
    await _messages.close();
    await _state.close();
    _directHttpClient.close(force: true);
  }
}
