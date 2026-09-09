import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'domain/providers/ability_provider.dart';
import 'domain/providers/attack_provider.dart';
import 'domain/providers/character_provider.dart';
import 'domain/providers/inventory_provider.dart';
import 'domain/providers/note_provider.dart';
import 'domain/providers/spell_provider.dart';
import 'domain/providers/spell_slot_provider.dart';
import 'presentation/screens/character_list_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DndHubApp());
}

class DndHubApp extends StatelessWidget {
  const DndHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => CharacterProvider()),
        ChangeNotifierProvider(create: (_) => InventoryProvider()),
        ChangeNotifierProvider(create: (_) => SpellProvider()),
        ChangeNotifierProvider(create: (_) => SpellSlotProvider()),
        ChangeNotifierProvider(create: (_) => AbilityProvider()),
        ChangeNotifierProvider(create: (_) => AttackProvider()),
        ChangeNotifierProvider(create: (_) => NoteProvider()),
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
