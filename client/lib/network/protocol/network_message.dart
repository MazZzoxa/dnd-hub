import 'dart:convert';

/// Transport-independent envelope used by D&D Hub v0.5 LAN sync.
class NetworkMessage {
  static const int protocolVersion = 2;

  final int protocol;
  final String type;
  final String id;
  final String clientId;
  final String campaignId;
  final int? sequence;
  final Map<String, dynamic> payload;

  const NetworkMessage({
    this.protocol = protocolVersion,
    required this.type,
    required this.id,
    required this.clientId,
    required this.campaignId,
    this.sequence,
    this.payload = const {},
  });

  bool get isCommand => type == 'command';
  bool get isEvent => type == 'event';

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'type': type,
        'id': id,
        'client_id': clientId,
        'campaign_id': campaignId,
        if (sequence != null) 'sequence': sequence,
        'payload': payload,
      };

  String encode() => jsonEncode(toJson());

  factory NetworkMessage.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return NetworkMessage(
      protocol: (json['protocol'] as num?)?.toInt() ?? protocolVersion,
      type: json['type']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      clientId: json['client_id']?.toString() ?? '',
      campaignId: json['campaign_id']?.toString() ?? '',
      sequence: (json['sequence'] as num?)?.toInt(),
      payload: rawPayload is Map
          ? rawPayload.map((key, value) => MapEntry(key.toString(), value))
          : const {},
    );
  }

  factory NetworkMessage.fromEncoded(String data) =>
      NetworkMessage.fromJson(jsonDecode(data) as Map<String, dynamic>);
}
