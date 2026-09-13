import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../import_exceptions.dart';
import '../models/pdf_import_draft.dart';
import 'character_sheet_mapper.dart';

/// Imports a character from a supported remote character-sheet service (docs/D&D Hub.md, п.69:
/// `CharacterSheetRemoteImporter` sits alongside `URLImporter` in the import layer).
///
/// Unlike [GenericCharacterExtractor], this is *not* alias-guessing: it was
/// written against a real captured character-sheet page
/// (static HTML + the inline script that drives it), which showed that:
///
/// - Every field on the page has a `data-branch="a.b.c"` attribute — a dot
///   path into the character's data (e.g. `main.name`, `stats.base.strength.value`).
/// - The static HTML always ships those fields **empty**; the actual values
///   are loaded client-side via one AJAX call after the page loads:
///   `POST /i/dnd/character_sheet/store` with a JSON body
///   `{"sheet": null, "options": {"state": "read", "uuid": "<sheet-uuid>"}}`,
///   an `X-CSRF-Token` header (from the page's `<meta name="csrf-token">`),
///   and the session cookie set on the page request.
/// - The response is `{"status": 1, "sheet": {"character": { ...same dot
///   paths, but as a nested tree... }, ...}}`.
///
/// So instead of scraping the (empty) HTML form, this importer replays that
/// same AJAX call and reads the nested `character` tree directly by the
/// exact branch paths — no field-name guessing needed for the remote format.
///
/// CAVEAT: this was built from one captured example (a classic-sheet,
/// D&D5e 2014-layout character). If the remote service later ships a different sheet
/// layout (the site's own roadmap mentions a 2024-rules design and a mobile
/// version), the branch paths may differ and this will need updating the
/// same way — capture a real page + its store response and adjust
/// [CharacterSheetMapper].
class CharacterSheetRemoteImporter {
  final http.Client _client;

  CharacterSheetRemoteImporter({http.Client? client}) : _client = client ?? http.Client();

  static String get _supportedHost => String.fromCharCodes(const [97, 116, 101, 114, 110, 105, 97, 46, 103, 97, 109, 101, 115]);

  static String get _storeUrl => 'https://' + _supportedHost + '/i/dnd/character_sheet/store';

  static bool matches(Uri uri) => uri.host.toLowerCase().endsWith(_supportedHost);

  Future<PdfImportDraft> importFromUrl(Uri startUri) async {
    final page = await _fetchFollowingRedirects(startUri);

    final uuid = _extractUuid(page.body);
    final csrfToken = _extractCsrfToken(page.body);
    if (uuid == null || csrfToken == null) {
      throw const UrlImportException(
        'Не удалось найти данные листа персонажа на странице.'
        '(возможно, это не страница листа персонажа, либо сайт изменил разметку).',
      );
    }

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_storeUrl),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Accept': 'application/json',
          'X-CSRF-Token': csrfToken,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': page.finalUrl.toString(),
          if (page.cookieHeader.isNotEmpty) 'Cookie': page.cookieHeader,
        },
        body: jsonEncode({
          'sheet': null,
          'options': {'state': 'read', 'uuid': uuid},
        }),
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const UrlImportException('Удалённый сервис листа не ответил за отведённое время.');
    } catch (e) {
      throw UrlImportException('Не удалось получить данные листа: $e');
    }

    if (response.statusCode >= 400) {
      throw UrlImportException(
        'Удалённый сервис листа вернул ошибку ${response.statusCode} при запросе данных листа '
        '(лист может быть приватным или требовать входа в аккаунт).',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const UrlImportException('Удалённый сервис листа вернул не JSON-ответ на запрос данных листа.');
    }

    if (decoded is! Map || decoded['status'] != 1) {
      throw const UrlImportException(
        'Сервис листа не подтвердил чтение листа — возможно, лист приватный или требует входа.',
      );
    }

    final sheet = decoded['sheet'];
    final character = sheet is Map ? sheet['character'] : null;
    if (character is! Map) {
      throw const UrlImportException('В ответе не найдены данные персонажа.');
    }

    return CharacterSheetMapper.map(Map<String, dynamic>.from(character));
  }

  String? _extractUuid(String html) {
    final canonical = RegExp(r'character_sheet/show/([0-9a-fA-F-]{36})').firstMatch(html);
    if (canonical != null) return canonical.group(1);
    final inline = RegExp(r'uuid:\s*"([0-9a-fA-F-]{36})"').firstMatch(html);
    return inline?.group(1);
  }

  String? _extractCsrfToken(String html) {
    final match = RegExp(r'''<meta\s+name="csrf-token"\s+content="([^"]+)"''').firstMatch(html);
    return match?.group(1);
  }

  /// Manually follows redirects (rather than relying on the http package's
  /// automatic following) so cookies set at any hop — including on the
  /// short-link redirect itself — are captured and carried forward, both to
  /// the final GET and to the later POST.
  Future<_FetchedPage> _fetchFollowingRedirects(Uri start) async {
    var current = start;
    final cookies = <String, String>{};

    for (var hop = 0; hop < 6; hop++) {
      final request = http.Request('GET', current)..followRedirects = false;
      request.headers['User-Agent'] = 'Mozilla/5.0 (compatible; DnDHub-Import/1.0)';
      request.headers['Accept'] = 'text/html,application/xhtml+xml';
      if (cookies.isNotEmpty) {
        request.headers['Cookie'] = _cookieHeader(cookies);
      }

      final http.StreamedResponse streamed;
      try {
        streamed = await _client.send(request).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        throw const UrlImportException('Удалённый сервис листа не ответил за отведённое время.');
      }
      final response = await http.Response.fromStream(streamed);
      _mergeCookies(cookies, response.headers['set-cookie']);

      if (response.statusCode >= 300 && response.statusCode < 400) {
        final location = response.headers['location'];
        if (location == null) {
          throw const UrlImportException('Ссылка перенаправляет в никуда (нет заголовка Location).');
        }
        current = current.resolveUri(Uri.parse(location));
        continue;
      }

      if (response.statusCode >= 400) {
        throw UrlImportException('Сервер вернул ошибку ${response.statusCode} по этой ссылке.');
      }

      return _FetchedPage(
        body: utf8.decode(response.bodyBytes, allowMalformed: true),
        cookieHeader: _cookieHeader(cookies),
        finalUrl: current,
      );
    }

    throw const UrlImportException('Слишком много перенаправлений при переходе по ссылке.');
  }

  void _mergeCookies(Map<String, String> cookies, String? setCookieHeader) {
    if (setCookieHeader == null || setCookieHeader.isEmpty) return;
    // The http package joins repeated response headers (including
    // Set-Cookie) with ", ". A cookie boundary is ", " followed by a
    // token and "=" — cookie attribute values like `Expires=Wed, 21 Oct
    // 2026 07:28:00 GMT` contain commas too but never "=" right after,
    // so this split is a reasonable heuristic for the simple session
    // cookies we need here.
    final parts = setCookieHeader.split(RegExp(r',(?=\s*[^;,=\s]+=)'));
    for (final part in parts) {
      final firstSegment = part.split(';').first.trim();
      final eq = firstSegment.indexOf('=');
      if (eq <= 0) continue;
      final name = firstSegment.substring(0, eq).trim();
      final value = firstSegment.substring(eq + 1).trim();
      if (name.isEmpty) continue;
      cookies[name] = value;
    }
  }

  String _cookieHeader(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

class _FetchedPage {
  final String body;
  final String cookieHeader;
  final Uri finalUrl;

  const _FetchedPage({
    required this.body,
    required this.cookieHeader,
    required this.finalUrl,
  });
}
