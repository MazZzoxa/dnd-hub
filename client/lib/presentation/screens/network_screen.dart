import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/campaign_model.dart';
import '../../network/connection_manager.dart';
import '../../network/models/nearby_game.dart';
import '../../network/protocol/network_message.dart';
import '../../network/services/sync_service.dart';
import '../../network/transport/hub_transport.dart';

class NetworkScreen extends StatefulWidget {
  final CampaignModel? campaign;

  const NetworkScreen({super.key, this.campaign});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  bool _searching = false;
  List<NearbyGame> _games = const [];
  final List<String> _logs = [];
  StreamSubscription<NetworkMessage>? _events;
  final _manualHost = TextEditingController();
  final _manualPort = TextEditingController(text: '8765');
  final _manualCampaign = TextEditingController();
  final _manualToken = TextEditingController();

  @override
  void initState() {
    super.initState();
    final sync = context.read<SyncService>();
    _events = sync.events.listen((event) {
      final name = event.payload['event']?.toString();
      if (name == null) return;
      final detail = switch (name) {
        'session.ready' => 'Сессия готова',
        'player.joined' => 'Подключился: ${event.payload['display_name'] ?? 'Player'}',
        'player.left' => 'Отключился: ${event.payload['display_name'] ?? 'Player'}',
        'character.updated' => 'Получено изменение персонажа',
        'pong' => 'Pong от GM Server',
        'ack' => 'Команда подтверждена',
        'error' => 'Ошибка: ${event.payload['message'] ?? 'unknown'}',
        _ => name,
      };
      if (!mounted) return;
      setState(() {
        _logs.insert(0, detail);
        if (_logs.length > 12) _logs.removeLast();
      });
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _manualHost.dispose();
    _manualPort.dispose();
    _manualCampaign.dispose();
    _manualToken.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.watch<ConnectionManager>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Локальная игра'),
        actions: [
          if (manager.connected)
            IconButton(
              tooltip: 'Ping',
              onPressed: () => context.read<SyncService>().ping(),
              icon: const Icon(Icons.sync_outlined),
            ),
          if (manager.connected || manager.hosting)
            IconButton(
              tooltip: 'Отключиться',
              onPressed: () async {
                await manager.disconnect();
                await manager.stopHosting();
              },
              icon: const Icon(Icons.link_off_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statusCard(manager),
          const SizedBox(height: 12),
          _hostCard(manager),
          const SizedBox(height: 12),
          if (!manager.hosting) ...[
            _findCard(manager),
            const SizedBox(height: 12),
            _manualJoinCard(manager),
          ],
          if (_logs.isNotEmpty) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Сетевые события', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  for (final log in _logs) Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(log, style: const TextStyle(color: AppTheme.textSecondary)),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusCard(ConnectionManager manager) {
    final icon = switch (manager.state) {
      TransportState.connected => Icons.check_circle_outline,
      TransportState.connecting || TransportState.reconnecting => Icons.sync,
      TransportState.failed => Icons.error_outline,
      _ => Icons.wifi_tethering_outlined,
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: manager.connected ? AppTheme.success : AppTheme.accent),
        title: Text(manager.connectionLabel),
        subtitle: Text(manager.hostingStarting
            ? 'Запускается GM Server…'
            : (manager.hosting ? 'Локальный GM Server • GM не считается игроком' : (manager.connected ? 'Транспорт: LAN / WebSocket' : 'Транспорт: не подключён'))),
      ),
    );
  }

  Widget _hostCard(ConnectionManager manager) {
    final campaign = widget.campaign;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Host Game', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            campaign == null
                ? 'Откройте нужную кампанию и запустите Host Game из её раздела.'
                : 'GM управляет этой кампанией и запускает локальный сервер. Подключившиеся игроки будут автоматически добавлены в список участников.',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 12),
          if (campaign != null)
            FilledButton.icon(
              onPressed: (manager.hosting || manager.hostingStarting) ? null : () => _host(manager, campaign),
              icon: manager.hostingStarting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.wifi_tethering),
              label: Text(
                manager.hostingStarting
                    ? 'Запуск сервера…'
                    : (manager.hosting ? 'Сервер запущен' : 'Host Game'),
              ),
            ),
          if (manager.hostingStarting) ...[
            const SizedBox(height: 10),
            const Text(
              'Запускается GM Server. Это может занять несколько секунд…',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
          if (manager.hosting && !manager.hostingStarting) ...[
            const SizedBox(height: 14),
            _invitePanel(manager),
          ],
        ]),
      ),
    );
  }

  Widget _invitePanel(ConnectionManager manager) {
    return FutureBuilder<List<String>>(
      future: manager.localIpv4(),
      builder: (context, snapshot) {
        final ips = snapshot.data ?? const <String>[];
        final host = ips.isNotEmpty ? ips.first : '127.0.0.1';
        final token = _tokenFromManager(manager);
        final invite = 'dndhub://join?host=$host&port=${manager.connectionPort}&campaign=${manager.campaignId}&token=$token';
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (token.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                child: QrImageView(data: invite, size: 160),
              ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Приглашение', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(invite, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 10),
                if (ips.isNotEmpty) Text('LAN: ${ips.join(', ')}', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Clipboard.setData(ClipboardData(text: invite)),
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Скопировать invite'),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 10),
          const Text(
            'QR — резервный способ. В обычном сценарии игрок использует Find Game и выбирает кампанию из списка.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ]);
      },
    );
  }

  String _tokenFromManager(ConnectionManager manager) {
    return manager.connectionToken;
  }

  Future<void> _host(ConnectionManager manager, CampaignModel campaign) async {
    if (campaign.syncId.isEmpty) {
      _showError('У кампании нет sync_id. Закройте и откройте кампании, чтобы применить миграцию базы.');
      return;
    }
    try {
      await manager.hostGame(
        campaignId: campaign.syncId,
        campaignName: campaign.name,
        gmName: _gmName(campaign),
      );
    } catch (error) {
      _showError('$error');
    }
  }

  String _gmName(CampaignModel campaign) {
    return 'GM';
  }

  Widget _findCard(ConnectionManager manager) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Find Game', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
            FilledButton.icon(
              onPressed: _searching ? null : () => _findGames(manager),
              icon: _searching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
              label: Text(_searching ? 'Поиск…' : 'Найти'),
            ),
          ]),
          const SizedBox(height: 6),
          const Text('Поиск идёт только в текущей локальной сети.', style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          if (_games.isEmpty)
            const Text('Игры не найдены.', style: TextStyle(color: AppTheme.textSecondary))
          else
            ..._games.map((game) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.casino_outlined)),
                    title: Text(game.campaignName),
                    subtitle: Text('${game.gmName} · ${game.players}/${game.maxPlayers} игроков · ${game.host}:${game.port}'),
                    trailing: FilledButton(onPressed: () => _join(manager, game), child: const Text('Join')),
                  ),
                )),
        ]),
      ),
    );
  }

  Future<void> _findGames(ConnectionManager manager) async {
    setState(() => _searching = true);
    try {
      final games = await manager.findGames();
      if (!mounted) return;
      setState(() => _games = games);
    } catch (error) {
      _showError('$error');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _join(ConnectionManager manager, NearbyGame game) async {
    final controller = TextEditingController(text: 'Player');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Войти: ${game.campaignName}'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Имя игрока')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Join')),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    try {
      await manager.joinGame(game: game, playerName: name);
    } catch (error) {
      _showError('$error');
    }
  }

  Widget _manualJoinCard(ConnectionManager manager) {
    final host = _manualHost;
    final port = _manualPort;
    final campaign = _manualCampaign;
    final token = _manualToken;
    return Card(
      child: ExpansionTile(
        title: const Text('QR / ручное подключение'),
        subtitle: const Text('Резерв на случай, если discovery не проходит через Wi-Fi изоляцию.'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(controller: host, decoration: const InputDecoration(labelText: 'GM IP')),
          const SizedBox(height: 8),
          TextField(controller: port, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Порт')),
          const SizedBox(height: 8),
          TextField(controller: campaign, decoration: const InputDecoration(labelText: 'Campaign sync_id')),
          const SizedBox(height: 8),
          TextField(controller: token, decoration: const InputDecoration(labelText: 'Invite token')),
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: FilledButton.icon(onPressed: () => _joinManual(manager, host, port, campaign, token), icon: const Icon(Icons.login), label: const Text('Подключиться'))),
        ],
      ),
    );
  }

  Future<void> _joinManual(
    ConnectionManager manager,
    TextEditingController host,
    TextEditingController port,
    TextEditingController campaign,
    TextEditingController token,
  ) async {
    final player = await _askPlayerName();
    if (player == null || !mounted) return;
    try {
      await manager.joinManual(
        host: host.text.trim(),
        port: int.tryParse(port.text.trim()) ?? 8765,
        token: token.text.trim(),
        campaignId: campaign.text.trim(),
        playerName: player,
      );
    } catch (error) {
      _showError('$error');
    }
  }

  Future<String?> _askPlayerName() async {
    final controller = TextEditingController(text: 'Player');
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Имя игрока'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Join')),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  void _showError(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}
