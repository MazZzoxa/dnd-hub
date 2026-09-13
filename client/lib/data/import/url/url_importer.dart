import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../character_sheet_remote/character_sheet_remote_importer.dart';
import '../import_exceptions.dart';
import '../models/pdf_import_draft.dart';
import '../pdf/pdf_importer.dart';
import 'generic_character_extractor.dart';
import 'public_content_importer.dart';
import '../../models/library_item_model.dart';

export '../import_exceptions.dart' show UrlImportException;

/// Result of fetching and classifying a pasted URL.
sealed class UrlFetchResult {
  final String sourceUrl;
  const UrlFetchResult(this.sourceUrl);
}

/// The URL served D&D Hub's own JSON export format directly — routed back
/// through [ImportManager]'s existing JSON pipeline unchanged.
class UrlJsonResult extends UrlFetchResult {
  final Uint8List bytes;
  const UrlJsonResult(this.bytes, super.sourceUrl);
}

/// The URL served (or contained) character-shaped data that was mapped into
/// a semantic draft — the same draft type and downstream handling as the
/// AcroForm PDF importer uses.
class UrlCharacterDraftResult extends UrlFetchResult {
  final PdfImportDraft draft;
  const UrlCharacterDraftResult(this.draft, super.sourceUrl);
}

class UrlLibraryItemResult extends UrlFetchResult {
  final LibraryItemModel item;
  const UrlLibraryItemResult(this.item, super.sourceUrl);
}

/// Universal "import by link" entry point (docs/D&D Hub.md, п.25): the user
/// pastes one URL and D&D Hub tries to work out what it is, rather than
/// exposing provider-specific import buttons.
///
/// Supported today, in order of reliability:
/// 1. A direct link to a PDF file → delegated to the existing, tested
///    [PdfImporter] (same code path as picking a PDF from disk).
/// 2. A URL that returns D&D Hub's own JSON export format
///    (`schema: "dnd-hub"`) → delegated to the existing JSON import
///    pipeline unchanged.
/// 3. A URL that returns (or an HTML page that embeds) JSON containing a
///    character-shaped object → best-effort mapping via
///    [GenericCharacterExtractor].
///
/// Anything else fails explicitly with [UrlImportException] instead of
/// guessing — consistent with the PDF importer's "fail rather than guess"
/// approach for unreadable documents.
class UrlImporter {
  final http.Client _client;

  UrlImporter({http.Client? client}) : _client = client ?? http.Client();

  Future<UrlFetchResult> fetch(String rawUrl) async {
    final uri = _parseUri(rawUrl);

    // The supported remote sheet format has its own JSON sync endpoint.
    // captured sheet page) that's far more reliable than guessing at HTML/
    // embedded JSON, so it gets a dedicated path ahead of the generic one.
    // The user sees only one generic URL import action.
    // Well-known public content pages are parsed into the local library.
    // This remains an internal implementation detail: the user only sees
    // one generic URL import action.
    if (PublicContentImporter.matches(uri)) {
      final item = await PublicContentImporter(client: _client).importFromUrl(uri);
      return UrlLibraryItemResult(item, uri.toString());
    }

    if (CharacterSheetRemoteImporter.matches(uri)) {
      final draft = await CharacterSheetRemoteImporter(client: _client).importFromUrl(uri);
      return UrlCharacterDraftResult(draft, uri.toString());
    }

    final http.Response response;
    try {
      response = await _client.get(
        uri,
        headers: const {
          'User-Agent': 'Mozilla/5.0 (compatible; DnDHub-Import/1.0)',
          'Accept': 'application/json, text/html;q=0.9, */*;q=0.8',
        },
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const UrlImportException('Сервер не ответил за отведённое время.');
    } catch (e) {
      throw UrlImportException('Не удалось загрузить ссылку: $e');
    }

    if (response.statusCode >= 400) {
      throw UrlImportException(
        'Сервер вернул ошибку ${response.statusCode} по этой ссылке.',
      );
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw const UrlImportException('По этой ссылке не найдено данных.');
    }

    // 1. Direct PDF link.
    if (bytes.length >= 4 && String.fromCharCodes(bytes.take(4)) == '%PDF') {
      final draft = await PdfImporter().parseAdaptive(bytes);
      return UrlCharacterDraftResult(draft, uri.toString());
    }

    final bodyText = _decodeBody(bytes, response.headers['content-type']);

    // 2/3. The whole response is JSON.
    final directJson = _tryDecodeJson(bodyText);
    if (directJson != null) {
      final classified = _classify(directJson, bytes, uri.toString());
      if (classified != null) return classified;
    }

    // 3b. HTML page that embeds JSON somewhere (common for JS-rendered
    // sheet/SPA sites, e.g. Next.js `__NEXT_DATA__`, Nuxt `__NUXT__`, or a
    // plain `<script type="application/json">` blob).
    for (final embedded in _extractEmbeddedJsonBlobs(bodyText)) {
      final decoded = _tryDecodeJson(embedded);
      if (decoded == null) continue;
      final classified = _classify(decoded, bytes, uri.toString());
      if (classified != null) return classified;
    }

    throw const UrlImportException(
      'Не удалось распознать содержимое по этой ссылке. Поддерживаются прямые '
      'ссылки на PDF, JSON-экспорт D&D Hub и страницы с распознаваемыми игровыми объектами.',
    );
  }

  UrlFetchResult? _classify(dynamic decoded, Uint8List rawBytes, String sourceUrl) {
    if (decoded is Map && decoded['schema'] == 'dnd-hub') {
      return UrlJsonResult(rawBytes, sourceUrl);
    }
    final draft = GenericCharacterExtractor.tryExtract(decoded, sourceUrl: sourceUrl);
    if (draft != null) {
      return UrlCharacterDraftResult(draft, sourceUrl);
    }
    return null;
  }

  Uri _parseUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) {
      throw const UrlImportException('Вставьте ссылку.');
    }
    final withScheme = trimmed.contains('://') ? trimmed : 'https://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasAuthority || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const UrlImportException('Это не похоже на корректную ссылку.');
    }
    return uri;
  }

  String _decodeBody(Uint8List bytes, String? contentType) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      // Fall back to latin1 for non-UTF-8 servers rather than failing outright;
      // JSON/embedded-JSON detection below will simply find nothing usable.
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  dynamic _tryDecodeJson(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
  }

  /// Finds candidate JSON blobs embedded in an HTML document. This is
  /// deliberately simple (brace-matching from a handful of known markers)
  /// rather than a full HTML/JS parser — good enough to pull out
  /// `__NEXT_DATA__`-style state blobs without adding an HTML parsing
  /// dependency.
  List<String> _extractEmbeddedJsonBlobs(String html) {
    final results = <String>[];

    void tryMarker(RegExp marker) {
      for (final match in marker.allMatches(html)) {
        final start = match.end - 1; // position of the opening brace/bracket
        final blob = _extractBalanced(html, start);
        if (blob != null) results.add(blob);
      }
    }

    // <script id="__NEXT_DATA__" type="application/json">{...}</script>
    tryMarker(RegExp(r'__NEXT_DATA__"[^>]*>\s*\{'));
    // window.__NUXT__ = {...}; / window.__INITIAL_STATE__ = {...};
    tryMarker(RegExp(r'__NUXT__\s*=\s*\{'));
    tryMarker(RegExp(r'__INITIAL_STATE__\s*=\s*\{'));
    // Generic <script type="application/json">{...}</script> blocks.
    tryMarker(RegExp(r'type="application/json"[^>]*>\s*\{'));

    return results;
  }

  /// Given [text] and the index of an opening `{`, returns the substring up
  /// to (and including) its matching closing `}` using simple depth
  /// counting. Returns null if the braces never balance (malformed/truncated
  /// HTML).
  String? _extractBalanced(String text, int openIndex) {
    if (openIndex < 0 || openIndex >= text.length || text[openIndex] != '{') {
      return null;
    }
    var depth = 0;
    var inString = false;
    var escape = false;
    for (var i = openIndex; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escape) {
          escape = false;
        } else if (char == r'\') {
          escape = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
      } else if (char == '{') {
        depth++;
      } else if (char == '}') {
        depth--;
        if (depth == 0) return text.substring(openIndex, i + 1);
      }
    }
    return null;
  }
}
