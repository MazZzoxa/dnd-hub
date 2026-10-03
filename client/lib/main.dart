import 'package:flutter/material.dart';

import 'package:provider/provider.dart';

import 'core/android_backup_service.dart';

import 'core/theme/app_theme.dart';
import 'domain/providers/ability_provider.dart';
import 'domain/providers/campaign_provider.dart';
import 'domain/providers/xp_provider.dart';
import 'domain/providers/attack_provider.dart';
import 'domain/providers/character_provider.dart';
import 'domain/providers/inventory_provider.dart';
import 'domain/providers/library_provider.dart';
import 'domain/providers/note_provider.dart';
import 'domain/providers/spell_provider.dart';
import 'domain/providers/spell_slot_provider.dart';
import 'domain/providers/session_provider.dart';
import 'domain/providers/battle_provider.dart';
import 'domain/providers/session_workspace_provider.dart';
import 'domain/providers/gameplay_state_provider.dart';
import 'network/connection_manager.dart';
import 'network/services/sync_service.dart';
import 'presentation/screens/character_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('D&D Hub FlutterError: ${details.exception}');
    debugPrintStack(stackTrace: details.stack);
  };
  final connectionManager = ConnectionManager();
  await connectionManager.initialize();
  final syncService = SyncService(connectionManager);

  runApp(DndHubApp(connectionManager: connectionManager, syncService: syncService));
}

class DndHubApp extends StatefulWidget {
  final ConnectionManager connectionManager;
  final SyncService syncService;

  const DndHubApp({super.key, required this.connectionManager, required this.syncService});

  @override
  State<DndHubApp> createState() => _DndHubAppState();
}

class _DndHubAppState extends State<DndHubApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AndroidBackupService.dataChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.connectionManager),
        Provider.value(value: widget.syncService),
        ChangeNotifierProvider(create: (_) => CharacterProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => InventoryProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => SpellProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => SpellSlotProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => AbilityProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => AttackProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => NoteProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => CampaignProvider(syncService: widget.syncService, connectionManager: widget.connectionManager)),
        ChangeNotifierProvider(create: (_) => XpProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => SessionProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => SessionWorkspaceProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => BattleProvider(syncService: widget.syncService)),
        ChangeNotifierProvider(create: (_) => GameplayStateProvider(syncService: widget.syncService)),
      ],
      child: MaterialApp(
        title: 'D&D Hub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        home: const CharacterListScreen(),
      ),
    );
  }
}
