import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/character_model.dart';

/// Универсальный круглый аватар персонажа.
///
/// Если у персонажа есть изображение из раздела «Био», оно отображается
/// с обрезкой по кругу. При отсутствии или повреждении изображения
/// используется первая буква имени.
class CharacterAvatar extends StatelessWidget {
  final CharacterModel character;
  final double radius;

  const CharacterAvatar({
    super.key,
    required this.character,
    this.radius = 24,
  });

  Uint8List? _decodeImage() {
    final encoded = character.bioImageBase64.trim();
    if (encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }

  String get _fallbackLabel =>
      character.name.isNotEmpty ? character.name[0].toUpperCase() : '?';

  @override
  Widget build(BuildContext context) {
    final bytes = _decodeImage();
    final diameter = radius * 2;

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: ColoredBox(
          color: AppTheme.primary.withOpacity(0.2),
          child: bytes == null
              ? Center(
                  child: Text(
                    _fallbackLabel,
                    style: TextStyle(
                      color: AppTheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: radius * 0.75,
                    ),
                  ),
                )
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  width: diameter,
                  height: diameter,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Text(
                      _fallbackLabel,
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: radius * 0.75,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
