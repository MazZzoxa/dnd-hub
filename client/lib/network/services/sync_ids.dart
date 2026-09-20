import 'dart:math';

class SyncIds {
  SyncIds._();

  static final Random _random = Random.secure();

  static String newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    // RFC 4122 UUID v4 bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
