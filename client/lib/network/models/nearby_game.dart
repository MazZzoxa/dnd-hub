class NearbyGame {
  final String host;
  final int port;
  final String campaignId;
  final String campaignName;
  final String gmName;
  final int players;
  final int maxPlayers;
  final String inviteToken;

  const NearbyGame({
    required this.host,
    required this.port,
    required this.campaignId,
    required this.campaignName,
    required this.gmName,
    required this.players,
    required this.maxPlayers,
    required this.inviteToken,
  });

  String get inviteUri =>
      'dndhub://join?host=$host&port=$port&campaign=$campaignId&token=$inviteToken';

  factory NearbyGame.fromJson(Map<String, dynamic> json, String sourceHost) {
    return NearbyGame(
      host: (json['host']?.toString().trim().isNotEmpty ?? false)
          ? json['host'].toString()
          : sourceHost,
      port: (json['port'] as num?)?.toInt() ?? 8765,
      campaignId: json['campaign_id']?.toString() ?? '',
      campaignName: json['campaign_name']?.toString() ?? 'D&D Hub',
      gmName: json['gm_name']?.toString() ?? 'GM',
      players: (json['players'] as num?)?.toInt() ?? 0,
      maxPlayers: (json['max_players'] as num?)?.toInt() ?? 5,
      inviteToken: json['invite_token']?.toString() ?? '',
    );
  }
}
