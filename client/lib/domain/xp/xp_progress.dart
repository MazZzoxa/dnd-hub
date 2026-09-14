class XpProgress {
  final int currentXp;
  final int level;
  final int currentLevelXp;
  final int? nextLevelXp;
  final double progress;

  const XpProgress({
    required this.currentXp,
    required this.level,
    required this.currentLevelXp,
    required this.nextLevelXp,
    required this.progress,
  });
}
