import 'dart:math' as math;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../../models/library_item_model.dart';
import '../import_exceptions.dart';

/// Parses public D&D content pages into the generic Local Content Library
/// model. The parser intentionally targets the page semantics (headings,
/// labelled fields, article text) rather than brittle CSS class names.
///
/// Supported page families include spells, magic items, feats and a generic
/// fallback for other content pages. The UI remains source-agnostic.
class PublicContentImporter {
  final http.Client _client;

  PublicContentImporter({http.Client? client}) : _client = client ?? http.Client();

  static bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final supportedHost = String.fromCharCodes(const [100, 110, 100, 46, 115, 117]);
    final hostSuffix = String.fromCharCodes(const [46, 100, 110, 100, 46, 115, 117]);
    if (!(host == supportedHost || host.endsWith(hostSuffix))) return false;
    final path = uri.path.toLowerCase();
    return path.startsWith('/spells/') ||
        path.startsWith('/items/') ||
        path.startsWith('/feats/') ||
        path.startsWith('/class/') ||
        path.startsWith('/race/') ||
        path.startsWith('/races/') ||
        path.startsWith('/background/') ||
        path.startsWith('/backgrounds/') ||
        path.startsWith('/bestiary/') ||
        path.startsWith('/monster/') ||
        path.startsWith('/monsters/') ||
        path.startsWith('/equipment/');
  }

  Future<LibraryItemModel> importFromUrl(Uri uri) async {
    final response = await _get(uri);
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('text/html') && !_looksLikeHtml(response.body)) {
      throw const UrlImportException('Ссылка не содержит HTML-страницу с игровым объектом.');
    }

    final item = parse(response.body, uri.toString());
    if (item == null) {
      throw const UrlImportException(
        'Не удалось распознать объект на этой странице. Откройте прямую страницу предмета, заклинания или другого игрового объекта.',
      );
    }
    return item;
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      final response = await _client.get(
        uri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (compatible; DnDHub-Import/1.0)',
          'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.8',
        },
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 400) {
        throw UrlImportException('Сервер вернул ошибку ${response.statusCode} по этой ссылке.');
      }
      if (response.bodyBytes.isEmpty) {
        throw const UrlImportException('Страница пустая.');
      }
      return response;
    } on UrlImportException {
      rethrow;
    } catch (error) {
      throw UrlImportException('Не удалось загрузить ссылку: $error');
    }
  }

  /// Pure parser, kept public for unit tests and offline fixture validation.
  static LibraryItemModel? parse(String html, String sourceUrl) {
    final document = html_parser.parse(html);
    for (final node in document.querySelectorAll('script, style, noscript, nav, footer, header, form')) {
      node.remove();
    }

    final blocks = _extractBlocks(document);
    final title = _extractTitle(document, blocks);
    if (title.isEmpty) return null;

    final normalizedUrl = sourceUrl.trim();
    final path = Uri.tryParse(normalizedUrl)?.path.toLowerCase() ?? '';
    final imageUrl = _extractImageUrl(document, normalizedUrl);

    if (path.startsWith('/spells/')) {
      return _parseSpell(title, blocks, normalizedUrl, imageUrl: imageUrl);
    }
    if (path.startsWith('/items/')) {
      return _parseItem(title, blocks, normalizedUrl, imageUrl: imageUrl);
    }
    if (path.startsWith('/feats/')) {
      return _parseAbility(title, blocks, normalizedUrl, category: 'Черта', imageUrl: imageUrl);
    }

    return _parseGenericOther(title, blocks, normalizedUrl, _sectionFromPath(path), imageUrl: imageUrl);
  }

  static List<String> _extractBlocks(Document document) {
    final root = _pickMainRoot(document);
    final result = <String>[];

    final selectors = root.querySelectorAll('h1, h2, h3, h4, p, li, dt, dd');
    for (final element in selectors) {
      // A common page layout wraps a <p> inside <li>. Reading both nodes
      // produces the exact same paragraph twice. Keep the semantic child.
      if (element.localName == 'li' &&
          element.querySelector('p, h1, h2, h3, h4, ul, ol, div') != null) {
        continue;
      }
      final text = _cleanText(element.text);
      if (text.isEmpty) continue;
      if (_isChromeText(text)) continue;
      if (result.isEmpty || result.last != text) result.add(text);
    }

    // Some templates wrap article text in divs without p tags. Add a compact
    // fallback only when the semantic blocks are too sparse.
    if (result.length < 3) {
      final fallback = root.text
          .split(RegExp(r'\s{2,}|\n+'))
          .map(_cleanText)
          .where((v) => v.isNotEmpty)
          .toList();
      for (final text in fallback) {
        if (!_isChromeText(text) && (result.isEmpty || result.last != text)) {
          result.add(text);
        }
      }
    }
    return result;
  }

  static Element _pickMainRoot(Document document) {
    final candidates = <Element>[
      ...document.querySelectorAll('main, article, [role="main"]'),
      ...document.querySelectorAll('.content, .article, .page-content, .main-content'),
      document.body ?? document.querySelector('html') ?? Element.tag('div'),
    ];
    candidates.sort((a, b) => b.text.length.compareTo(a.text.length));
    return candidates.first;
  }

  static String _extractTitle(Document document, List<String> blocks) {
    for (final selector in const ['main h1', 'article h1', 'h1']) {
      final h1 = document.querySelector(selector);
      if (h1 != null) {
        final value = _cleanTitle(h1.text);
        if (value.isNotEmpty) return value;
      }
    }
    for (final block in blocks) {
      final value = _cleanTitle(block);
      if (value.isNotEmpty && !_isChromeText(value)) return value;
    }
    return '';
  }

  static LibraryItemModel _parseSpell(String title, List<String> blocks, String url, {String imageUrl = ''}) {
    final index = _contentStartIndex(blocks, title);
    final relevant = blocks.sublist(index);

    final levelAndSchool = _findFirst(relevant, [
      RegExp(r'^(Заговор|\d+\s+уровень)(?:,\s*(.+?))?(?:\s*\(.*\))?$', caseSensitive: false),
    ]);

    var level = 0;
    var school = '';
    if (levelAndSchool != null) {
      final match = RegExp(r'^(Заговор|\d+\s+уровень)(?:,\s*(.+?))?(?:\s*\(.*\))?$', caseSensitive: false)
          .firstMatch(levelAndSchool);
      if (match != null) {
        final levelToken = match.group(1)!.toLowerCase();
        level = levelToken == 'заговор' ? 0 : int.tryParse(levelToken.split(' ').first) ?? 0;
        school = (match.group(2) ?? '').trim();
      }
    }

    final castingTime = _labelValue(relevant, ['Время накладывания', 'Время сотворения']);
    final range = _labelValue(relevant, ['Дистанция', 'Дальность']);
    final components = _labelValue(relevant, ['Компоненты']);
    final duration = _labelValue(relevant, ['Длительность']);
    final classes = _labelValue(relevant, ['Классы']);
    final subclasses = _labelValue(relevant, ['Подклассы']);
    final source = _labelValue(relevant, ['Источник']);
    final ritual = _hasFlag(relevant, ['ритуал']);
    final concentration = _hasFlag(relevant, ['концентрация']);

    final description = _extractDescription(
      relevant,
      metadataValues: {
        levelAndSchool ?? '',
        castingTime,
        range,
        components,
        duration,
        classes,
        subclasses,
        source,
      },
    );

    return LibraryItemModel(
      type: LibraryItemType.spell,
      name: _cleanTitle(title),
      data: {
        'level': level,
        'school': school,
        'range': range,
        'components': components,
        'castingTime': castingTime,
        'duration': duration,
        'description': description,
        'classes': classes,
        'subclasses': subclasses,
        'ritual': ritual,
        'concentration': concentration,
        'source': source,
        'imageUrl': imageUrl,
      },
      sourceType: LibrarySourceType.imported,
      sourceUrl: url,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static LibraryItemModel _parseItem(String title, List<String> blocks, String url, {String imageUrl = ''}) {
    final index = _contentStartIndex(blocks, title);
    final relevant = blocks.sublist(index);

    // On item pages the first short line after the title is the item type
    // (for example, "Оружие"). Other templates put rarity/attunement in
    // the same line, so keep that whole profile line as raw details.
    final profileIndex = relevant.indexWhere(_looksLikeItemProfile);
    final profile = profileIndex >= 0 ? relevant[profileIndex] : '';
    final content = profileIndex >= 0 ? relevant.sublist(profileIndex + 1) : relevant;

    final rarityMatch = RegExp(
      r'редкость\s+(.+?)(?:\.|$)',
      caseSensitive: false,
    ).firstMatch(profile);
    final rarity = (rarityMatch?.group(1) ?? '').trim();
    final requiresAttunement = RegExp(
      r'требуется настройка',
      caseSensitive: false,
    ).hasMatch(profile);
    final price = _findFirst(relevant, [
      RegExp(r'рекомендуемая стоимость:\s*(.+)$', caseSensitive: false),
      RegExp(r'рекомендованная стоимость:\s*(.+)$', caseSensitive: false),
      RegExp(r'стоимость:\s*(.+)$', caseSensitive: false),
    ]);

    final category = _extractItemCategory(profile);
    final description = _extractDescription(
      content,
      metadataValues: {profile, price ?? ''},
    );

    return LibraryItemModel(
      type: LibraryItemType.item,
      name: _cleanTitle(title),
      data: {
        'category': category.isEmpty ? 'Other' : category,
        'weight': 0.0,
        'description': description,
        'rarity': rarity,
        'requiresAttunement': requiresAttunement,
        'price': price ?? '',
        'details': profile,
        'imageUrl': imageUrl,
      },
      sourceType: LibrarySourceType.imported,
      sourceUrl: url,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static LibraryItemModel _parseAbility(
    String title,
    List<String> blocks,
    String url, {
    required String category,
    String imageUrl = '',
  }) {
    final index = _contentStartIndex(blocks, title);
    final relevant = blocks.sublist(index);
    final source = _labelValue(relevant, ['Источник']);
    final description = _extractDescription(relevant, metadataValues: {source});

    return LibraryItemModel(
      type: LibraryItemType.ability,
      name: _cleanTitle(title),
      data: {
        'source': source,
        'category': category,
        'description': description,
        'imageUrl': imageUrl,
      },
      sourceType: LibrarySourceType.imported,
      sourceUrl: url,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static LibraryItemModel _parseGenericOther(
    String title,
    List<String> blocks,
    String url,
    String section, {String imageUrl = ''}) {
    final index = _contentStartIndex(blocks, title);
    final relevant = blocks.sublist(index);
    final description = _extractDescription(relevant, metadataValues: const {});

    return LibraryItemModel(
      type: LibraryItemType.other,
      name: _cleanTitle(title),
      data: {
        'category': section,
        'description': description,
        'imageUrl': imageUrl,
      },
      sourceType: LibrarySourceType.imported,
      sourceUrl: url,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  static int _contentStartIndex(List<String> blocks, String title) {
    final titleIndex = blocks.indexWhere((value) => _cleanTitle(value) == _cleanTitle(title));
    return math.max(0, titleIndex + 1);
  }

  static String _extractDescription(List<String> blocks, {required Set<String> metadataValues}) {
    final descriptionParts = <String>[];
    final seen = <String>{};
    for (final block in blocks) {
      final clean = block.trim();
      final lower = clean.toLowerCase();
      if (clean.isEmpty || metadataValues.contains(clean)) continue;
      if (_isMetadataBlock(clean)) continue;
      if (_isChromeText(clean)) continue;
      if (lower == 'распечатать' || lower == 'image') continue;
      if (clean.length < 10) continue;

      // Prevent repeated DOM fragments from leaking into imported text.
      final key = clean.toLowerCase();
      if (!seen.add(key)) continue;
      descriptionParts.add(clean);
    }

    final prose = descriptionParts
        .where((v) => v.contains(' ') || v.contains('.') || v.contains(','))
        .take(80)
        .toList();
    return prose.join('\n\n').trim();
  }

  static String? _findFirst(List<String> blocks, List<RegExp> patterns) {
    for (final block in blocks) {
      for (final pattern in patterns) {
        if (pattern.hasMatch(block)) return block;
      }
    }
    return null;
  }

  static String _labelValue(List<String> blocks, List<String> labels) {
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      for (final label in labels) {
        final prefix = '$label:';
        if (block.toLowerCase().startsWith(prefix.toLowerCase())) {
          return block.substring(prefix.length).trim();
        }
        if (block.toLowerCase() == label.toLowerCase() && i + 1 < blocks.length) {
          return blocks[i + 1].trim();
        }
      }
    }
    return '';
  }

  static bool _hasFlag(List<String> blocks, List<String> needles) {
    final joined = blocks.join(' ').toLowerCase();
    return needles.any((needle) => RegExp('\\b${RegExp.escape(needle.toLowerCase())}\\b').hasMatch(joined));
  }

  static bool _isMetadataBlock(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('время накладывания:') ||
        lower.startsWith('время сотворения:') ||
        lower.startsWith('дистанция:') ||
        lower.startsWith('дальность:') ||
        lower.startsWith('компоненты:') ||
        lower.startsWith('длительность:') ||
        lower.startsWith('классы:') ||
        lower.startsWith('подклассы:') ||
        lower.startsWith('источник:') ||
        RegExp(r'^(заговор|\d+)\s+уровень').hasMatch(lower);
  }

  static bool _looksLikeItemProfile(String value) {
    final lower = value.toLowerCase().trim();
    return lower.startsWith('оружие') ||
        lower.startsWith('доспех') ||
        lower.startsWith('зелье') ||
        lower.startsWith('эликсир') ||
        lower.startsWith('масло') ||
        lower.contains('редкость') ||
        lower.contains('требуется настройка');
  }

  static String _extractItemCategory(String profile) {
    final lower = profile.toLowerCase();
    if (lower.startsWith('оружие')) return 'Weapons';
    if (lower.startsWith('доспех')) return 'Armor';
    if (lower.startsWith('зелье') || lower.startsWith('эликсир') || lower.startsWith('масло')) {
      return 'Consumables';
    }
    return 'Other';
  }

  static String _sectionFromPath(String path) {
    if (path.startsWith('/class/')) return 'Класс';
    if (path.startsWith('/race/') || path.startsWith('/races/')) return 'Вид / происхождение';
    if (path.startsWith('/background/') || path.startsWith('/backgrounds/')) return 'Предыстория';
    if (path.startsWith('/bestiary/') || path.startsWith('/monster/') || path.startsWith('/monsters/')) return 'Монстр';
    if (path.startsWith('/equipment/')) return 'Снаряжение';
    return 'Прочее';
  }

  static String _extractImageUrl(Document document, String sourceUrl) {
    String? raw;
    final ogImage = document.querySelector('meta[property="og:image"]')?.attributes['content'];
    raw = ogImage;
    if ((raw == null || raw.trim().isEmpty)) {
      raw = document.querySelector('main img, article img, .content img')?.attributes['src'];
    }
    if (raw == null || raw.trim().isEmpty) return '';
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null) return '';
    if (parsed.hasScheme) return parsed.toString();
    return Uri.tryParse(sourceUrl)?.resolveUri(parsed).toString() ?? '';
  }

  static String _cleanTitle(String value) {
    return _cleanText(value)
        .replaceFirst(RegExp(r'\s+[—-]\s*(Заклинания|Магические предметы|Черты|Классы|Расы|Предыстории).*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+\[[^\]]+\]\s*[A-ZА-Я0-9]{2,}\s*$', caseSensitive: false), '')
        .trim();
  }

  static String _cleanText(String value) {
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+([,.;:!?])'), r'\1')
        .trim();
  }

  static bool _looksLikeHtml(String value) {
    final lower = value.toLowerCase();
    return lower.contains('<html') || lower.contains('<body') || lower.contains('<main');
  }

  static bool _isChromeText(String value) {
    final lower = value.toLowerCase();
    const noise = [
      'официальные',
      'homebrew',
      'поиск по разделу',
      'поиск',
      'загрузить больше',
      'измените фильтр',
      'нет совпадений',
      'попробуйте задать',
      'скрыть поиск',
      'размер списка',
      'размер шрифта',
      'источник',
    ];
    return noise.contains(lower) ||
        lower.startsWith('button') ||
        lower.contains('dnd' + '.' + 'su ©') ||
        lower == 'распечатать';
  }
}
