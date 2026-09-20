import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'discovery/lan_discovery.dart';
import 'models/nearby_game.dart';
import 'protocol/network_message.dart';
import 'services/sync_ids.dart';
import 'services/client_identity.dart';
import 'transport/hub_transport.dart';
import 'transport/lan_websocket_transport.dart';

class ConnectionManager extends ChangeNotifier {
  final LanDiscovery discovery;
  final LanWebSocketTransport _transport = LanWebSocketTransport();
  Process? _serverProcess;
  StreamSubscription<TransportState>? _transportStateSubscription;
  Timer? _reconnectTimer;
  bool _intentionalDisconnect = false;
  bool _connectInProgress = false;
  bool _hostingStarting = false;
  int _reconnectAttempts = 0;
  final StreamController<TransportState> _states = StreamController.broadcast();

  late final String clientId;
  final String _defaultRole = 'player';

  String _role = 'player';
  String _displayName = '';
  String _campaignId = '';
  String _connectedHost = '';
  String _transportHost = '';
  int _connectedPort = 8765;
  String _connectedToken = '';
  int _lastSequence = 0;

  TransportState _state = TransportState.disconnected;

  ConnectionManager({LanDiscovery? discovery}) : discovery = discovery ?? LanDiscovery() {
    _transportStateSubscription = _transport.state.listen((state) {
      _state = state;
      _states.add(state);
      notifyListeners();

      if (state == TransportState.connected) {
        _reconnectAttempts = 0;
      } else if ((state == TransportState.failed || state == TransportState.disconnected) &&
          !_intentionalDisconnect &&
          !_connectInProgress &&
          _connectedHost.isNotEmpty &&
          _connectedToken.isNotEmpty) {
        _scheduleReconnect();
      }
    });
  }

  Future<void> initialize() async {
    clientId = await ClientIdentity().getOrCreateClientId();
  }

  TransportState get state => _state;
  Stream<TransportState> get stateStream => _states.stream;
  bool get connected => _state == TransportState.connected;
  bool get hosting => _serverProcess != null;
  bool get hostingStarting => _hostingStarting;
  String get role => _role;
  String get displayName => _displayName;
  String get campaignId => _campaignId;
  String get connectionHost => _connectedHost;
  int get connectionPort => _connectedPort;
  String get connectionToken => _connectedToken;

  Stream<String> get messageStream async* {
    await for (final bytes in _transport.messages) {
      final raw = utf8.decode(bytes);
      try {
        final message = NetworkMessage.fromEncoded(raw);
        if (message.sequence != null && message.sequence! > _lastSequence) {
          _lastSequence = message.sequence!;
        }
      } catch (_) {}
      yield raw;
    }
  }

  Future<List<NearbyGame>> findGames({Duration timeout = const Duration(seconds: 3)}) =>
      discovery.discover(timeout: timeout);

  Future<String?> _findSystemPythonExecutable() async {
    if (Platform.isWindows) {
      // Resolve py -3 to a real python.exe path before starting the server.
      // This avoids Inkscape's private Python when it appears first on PATH.
      try {
        final result = await Process.run(
          'py',
          ['-3', '-c', 'import sys; print(sys.executable)'],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
            final value = line.trim();
            if (value.isEmpty) continue;
            if (!_isBundledPythonPath(value)) return value;
          }
        }
      } catch (_) {}

      try {
        final result = await Process.run('where.exe', ['python']);
        for (final line in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final value = line.trim();
          if (value.isEmpty || _isBundledPythonPath(value)) continue;
          try {
            final check = await Process.run(
              value,
              ['-c', 'import sys; print(sys.executable)'],
            );
            if (check.exitCode == 0) return value;
          } catch (_) {}
        }
      } catch (_) {}
    }

    for (final candidate in Platform.isWindows
        ? <String>['python.exe', 'python']
        : <String>['python3', 'python']) {
      try {
        final result = await Process.run(
          candidate,
          ['-c', 'import sys; print(sys.executable)'],
          runInShell: true,
        );
        if (result.exitCode == 0) {
          final path = result.stdout.toString().trim().split(RegExp(r'\r?\n')).last.trim();
          if (path.isNotEmpty && !_isBundledPythonPath(path)) return path;
        }
      } catch (_) {}
    }
    return null;
  }

  bool _isBundledPythonPath(String path) {
    final normalized = path.replaceAll('\\', '/').toLowerCase();
    return normalized.contains('/inkscape/');
  }

  File? _findServerScript() {
    final candidates = <File>[];

    // Release/Profile: server/ is bundled beside the executable by CMake.
    final executableDir = File(Platform.resolvedExecutable).parent;
    candidates.add(
      File(
        '${executableDir.path}${Platform.pathSeparator}server${Platform.pathSeparator}run.py',
      ),
    );

    // Development: find the repository root from the working directory.
    var current = Directory.current.absolute;
    for (var i = 0; i < 8; i++) {
      candidates.add(
        File(
          '${current.path}${Platform.pathSeparator}server${Platform.pathSeparator}run.py',
        ),
      );
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    for (final candidate in candidates) {
      if (candidate.existsSync()) return candidate;
    }
    return null;
  }

  Future<void> hostGame({
    required String campaignId,
    required String campaignName,
    required String gmName,
    int port = 8765,
  }) async {
    if (_hostingStarting) return;
    _hostingStarting = true;
    notifyListeners();
    try {
      await disconnect();
      await stopHosting(resetStarting: false);
      _hostingStarting = true;
      notifyListeners();
      port = await _findAvailableServerPort(port);
      _role = 'gm';
      _displayName = gmName.trim().isEmpty ? 'GM' : gmName.trim();
      _campaignId = campaignId;
      _connectedPort = port;
      _connectedToken = SyncIds.newId().replaceAll('-', '');

      final script = _findServerScript();
      if (script == null) {
        throw StateError(
          'Не найден server/run.py. В Release-сборке папка server должна находиться рядом с dnd_hub.exe.',
        );
      }
      final serverDir = script.parent.parent;

      final args = [
        script.path,
        '--host', '0.0.0.0',
        '--port', '$port',
        '--campaign-id', campaignId,
        '--campaign-name', campaignName,
        '--gm-name', _displayName,
        '--invite-token', _connectedToken,
      ];

      final python = await _findSystemPythonExecutable();
      if (python == null) {
        throw StateError(
          'Не найден обычный Python 3. Установите Python 3 и повторите запуск Host Game.',
        );
      }

      final process = await Process.start(
        python,
        args,
        workingDirectory: serverDir.path,
        runInShell: false,
      );
      _serverProcess = process;
      notifyListeners();

      final serverOutput = <String>[];
      final serverErrors = <String>[];
      int? serverExitCode;

      void remember(List<String> target, String text) {
        for (final line in text.split(RegExp(r'\r?\n'))) {
          final value = line.trimRight();
          if (value.isEmpty) continue;
          target.add(value);
          if (target.length > 30) target.removeAt(0);
        }
      }

      process.stdout.transform(utf8.decoder).listen((text) => remember(serverOutput, text));
      process.stderr.transform(utf8.decoder).listen((text) => remember(serverErrors, text));
      process.exitCode.then((code) {
        serverExitCode = code;
        if (identical(_serverProcess, process)) {
          _serverProcess = null;
          if (_hostingStarting) {
            _hostingStarting = false;
            notifyListeners();
          }
        }
      });

      final deadline = DateTime.now().add(const Duration(seconds: 12));
      var serverReady = false;
      while (DateTime.now().isBefore(deadline)) {
        final client = HttpClient()..findProxy = (_) => 'DIRECT';
        try {
          final request = await client.getUrl(Uri.parse('http://127.0.0.1:$port/health'));
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          if (response.statusCode == 200) {
            try {
              final decoded = jsonDecode(body);
              if (decoded is Map &&
                  decoded['ok'] == true &&
                  decoded['protocol'] == NetworkMessage.protocolVersion &&
                  decoded['campaign_id'] == campaignId) {
                serverReady = true;
                break;
              }
            } catch (_) {
              // Ignore malformed readiness responses and keep waiting.
            }
          }
        } catch (_) {
          // The server may still be starting.
        } finally {
          client.close(force: true);
        }
        if (serverExitCode != null) break;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }

      if (!serverReady) {
        await stopHosting();
        final details = [...serverErrors, ...serverOutput];
        final tail = details.isEmpty
            ? 'Нет вывода от server/run.py.'
            : details.take(12).join('\n');
        throw StateError(
          'GM Server не запустился на 127.0.0.1:$port.'
          '${serverExitCode == null ? '' : ' Код завершения: $serverExitCode.'}\n$tail',
        );
      }

      _transport.clientId = clientId;
      _transport.campaignId = campaignId;
      _transport.role = 'gm';
      _transport.displayName = _displayName;
      final ips = await localIpv4();
      _connectedHost = ips.isNotEmpty ? ips.first : '127.0.0.1';
      _transportHost = '127.0.0.1';
      await _connect(host: _transportHost, port: port, token: _connectedToken);
    } finally {
      _hostingStarting = false;
      notifyListeners();
    }
  }

  Future<void> joinGame({required NearbyGame game, required String playerName}) async {
    await _join(
      host: game.host,
      port: game.port,
      token: game.inviteToken,
      campaignId: game.campaignId,
      role: _defaultRole,
      displayName: playerName,
    );
  }

  Future<void> joinManual({
    required String host,
    required int port,
    required String token,
    required String campaignId,
    required String playerName,
  }) => _join(
        host: host,
        port: port,
        token: token,
        campaignId: campaignId,
        role: _defaultRole,
        displayName: playerName,
      );

  Future<void> _join({
    required String host,
    required int port,
    required String token,
    required String campaignId,
    required String role,
    required String displayName,
  }) async {
    await disconnect();
    _role = role;
    _displayName = displayName.trim().isEmpty ? 'Player' : displayName.trim();
    _campaignId = campaignId;
    _connectedHost = host;
    _transportHost = host;
    _connectedPort = port;
    _connectedToken = token;
    _transport.clientId = clientId;
    _transport.campaignId = campaignId;
    _transport.role = role;
    _transport.displayName = _displayName;
    await _connect(host: host, port: port, token: token);
  }

  Future<void> _connect({
    required String host,
    required int port,
    required String token,
    bool resumeAfterConnect = false,
  }) async {
    _connectInProgress = true;
    _intentionalDisconnect = false;
    try {
      await _transport.connect(host: host, port: port, token: token);
      if (resumeAfterConnect && connected) {
        await resume();
      }
    } finally {
      _connectInProgress = false;
    }
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null ||
        _intentionalDisconnect ||
        _connectedHost.isEmpty ||
        _connectedToken.isEmpty) {
      return;
    }
    final exponent = _reconnectAttempts.clamp(0, 3).toInt();
    final delaySeconds = (1 << exponent).clamp(1, 8).toInt();
    _reconnectAttempts = (_reconnectAttempts + 1).clamp(0, 6).toInt();
    _state = TransportState.reconnecting;
    _states.add(_state);
    notifyListeners();

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _reconnectTimer = null;
      if (_intentionalDisconnect) return;
      try {
        await _connect(
          host: _transportHost.isNotEmpty ? _transportHost : _connectedHost,
          port: _connectedPort,
          token: _connectedToken,
          resumeAfterConnect: true,
        );
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  Future<String?> sendCommand(
    String command, {
    required Map<String, dynamic> payload,
  }) async {
    if (!connected) return null;
    final commandId = SyncIds.newId();
    final message = NetworkMessage(
      type: 'command',
      id: commandId,
      clientId: clientId,
      campaignId: _campaignId,
      payload: {'command': command, ...payload},
    );
    await _transport.send(Uint8List.fromList(utf8.encode(message.encode())));
    return commandId;
  }

  Future<void> resume() async {
    if (!connected) return;
    await sendCommand('resume', payload: {'last_sequence': _lastSequence});
  }

  String get connectionLabel {
    if (_role == 'gm' && hosting) return 'GM Server: $_connectedPort';
    if (connected) return 'Подключено: $_connectedHost:$_connectedPort';
    return switch (_state) {
      TransportState.connecting => 'Подключение…',
      TransportState.reconnecting => 'Переподключение…',
      TransportState.failed => 'Ошибка подключения',
      _ => 'Не подключено',
    };
  }

  Future<List<String>> localIpv4() async {
    final result = <String>[];
    try {
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('10.') || ip.startsWith('192.168.') || _is172Private(ip)) {
            result.add(ip);
          }
        }
      }
    } catch (_) {}
    return result.toSet().toList();
  }

  bool _is172Private(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4 || parts.first != '172') return false;
    final second = int.tryParse(parts[1]) ?? -1;
    return second >= 16 && second <= 31;
  }


  Future<int> _findAvailableServerPort(int preferred) async {
    for (var candidate = preferred; candidate < preferred + 25; candidate++) {
      ServerSocket? probe;
      try {
        probe = await ServerSocket.bind(InternetAddress.anyIPv4, candidate);
        return candidate;
      } on SocketException {
        // Another application (including an old D&D Hub server) is using it.
      } finally {
        await probe?.close();
      }
    }
    throw StateError('Не удалось найти свободный порт для GM Server начиная с $preferred.');
  }

  Future<void> stopHosting({bool resetStarting = true}) async {
    final process = _serverProcess;
    _serverProcess = null;
    if (resetStarting) _hostingStarting = false;
    notifyListeners();
    if (process != null) {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        process.kill();
      }
    }
  }

  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    await _transport.disconnect();
  }

  @override
  void dispose() {
    _intentionalDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _transportStateSubscription?.cancel();
    _transport.dispose();
    _states.close();
    super.dispose();
    // The hosting process is terminated by stopHosting() before app shutdown.
  }
}
