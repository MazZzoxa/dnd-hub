import 'dart:io';
import 'dart:typed_data';

import 'package:dnd_hub/data/import/pdf/pdf_importer.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/pdf_import_smoke.dart <file.pdf>');
    exitCode = 64;
    return;
  }

  final file = File(args.single);
  if (!await file.exists()) {
    stderr.writeln('File not found: ${file.path}');
    exitCode = 66;
    return;
  }

  final draft = PdfImporter().parse(Uint8List.fromList(await file.readAsBytes()));
  print('Character: ${draft.character.name}');
  print('Class: ${draft.character.className} ${draft.character.level}');
  print('Race: ${draft.character.race}');
  print('STR/DEX/CON: ${draft.character.strength}/${draft.character.dexterity}/${draft.character.constitution}');
  print('INT/WIS/CHA: ${draft.character.intelligence}/${draft.character.wisdom}/${draft.character.charisma}');
  print('HP: ${draft.character.hp}/${draft.character.maxHp}');
  print('AC: ${draft.character.armorClass}');
  print('Attacks: ${draft.attacks.length}');
  print('Spells: ${draft.spells.length}');
  print('Items: ${draft.items.length}');
  if (draft.warnings.isNotEmpty) {
    print('Warnings:');
    for (final warning in draft.warnings) print('- $warning');
  }
}
