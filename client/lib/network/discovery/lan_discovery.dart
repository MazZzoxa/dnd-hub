import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/nearby_game.dart';

class LanDiscovery {
  static const int discoveryPort = 42817;
  static const String query = 'DNDHUB_DISCOVER_V1';

  Future<List<NearbyGame>> discover({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final games = <String, NearbyGame>{};
    final sockets = <RawDatagramSocket>[];
    final subscriptions = <StreamSubscription<RawSocketEvent>>[];

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final localIps = <String>{};
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          localIps.add(address.address);
        }
      }

      // Bind one socket per local IPv4 interface so a phone with Wi-Fi +
      // mobile data can issue the discovery packet through the LAN interface
      // instead of relying solely on Android's global default route.
      if (localIps.isEmpty) {
        localIps.add(InternetAddress.anyIPv4.address);
      }

      for (final ip in localIps) {
        RawDatagramSocket socket;
        try {
          socket = await RawDatagramSocket.bind(
            ip == InternetAddress.anyIPv4.address ? InternetAddress.anyIPv4 : InternetAddress(ip),
            0,
            reuseAddress: true,
            reusePort: true,
          );
        } catch (_) {
          if (ip == InternetAddress.anyIPv4.address) continue;
          socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        }
        socket.broadcastEnabled = true;
        sockets.add(socket);
        subscriptions.add(socket.listen((event) {
          if (event != RawSocketEvent.read) return;
          Datagram? packet;
          while ((packet = socket.receive()) != null) {
            try {
              final decoded = jsonDecode(utf8.decode(packet!.data));
              if (decoded is! Map<String, dynamic>) continue;
              final game = NearbyGame.fromJson(decoded, packet.address.address);
              final key = '${game.host}:${game.port}:${game.campaignId}';
              games[key] = game;
            } catch (_) {
              // Ignore malformed advertisements.
            }
          }
        }));
        socket.send(
          utf8.encode(query),
          InternetAddress('255.255.255.255'),
          discoveryPort,
        );
      }

      await Future<void>.delayed(timeout);
      return games.values.toList();
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      for (final socket in sockets) {
        socket.close();
      }
    }
  }
}
