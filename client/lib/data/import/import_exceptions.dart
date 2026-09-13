/// Thrown by [UrlImporter]/[CharacterSheetRemoteImporter] when a pasted URL can't be
/// fetched, or its contents can't be recognised as importable data — the
/// message is user-facing (shown directly in the import dialog).
class UrlImportException implements Exception {
  final String message;
  const UrlImportException(this.message);

  @override
  String toString() => message;
}
