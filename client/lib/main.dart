import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
import 'network/connection_manager.dart';
import 'network/services/sync_service.dart';
import 'presentation/screens/character_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final connectionManager = ConnectionManager();
  await connectionManager.initialize();
  final syncService = SyncService(connectionManager);
  runApp(DndHubApp(connectionManager: connectionManager, syncService: syncService));
}

class DndHubApp extends StatelessWidget {
  final ConnectionManager connectionManager;
  final SyncService syncService;

  const DndHubApp({super.key, required this.connectionManager, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: connectionManager),
        Provider.value(value: syncService),
        ChangeNotifierProvider(create: (_) => CharacterProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => InventoryProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => SpellProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => SpellSlotProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => AbilityProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => AttackProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => NoteProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => LibraryProvider()),
        ChangeNotifierProvider(create: (_) => CampaignProvider(syncService: syncService, connectionManager: connectionManager)),
        ChangeNotifierProvider(create: (_) => XpProvider(syncService: syncService)),
        ChangeNotifierProvider(create: (_) => SessionProvider(syncService: syncService)),
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
