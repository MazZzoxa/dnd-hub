import '../../models/attack_model.dart';
import '../../models/character_model.dart';
import '../../models/item_model.dart';
import '../../models/spell_model.dart';

class PdfImportField {
  final String key;
  final String value;
  final double confidence;
  final String source;
  final int page;

  const PdfImportField({
    required this.key,
    required this.value,
    required this.confidence,
    required this.source,
    required this.page,
  });
}

class PdfImportDraft {
  final CharacterModel character;
  final List<AttackModel> attacks;
  final List<SpellModel> spells;
  final List<ItemModel> items;
  final List<PdfImportField> fields;
  final List<String> warnings;

  const PdfImportDraft({
    required this.character,
    this.attacks = const [],
    this.spells = const [],
    this.items = const [],
    this.fields = const [],
    this.warnings = const [],
  });
}
