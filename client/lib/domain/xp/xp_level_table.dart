class XpLevelTable {
  static const List<int> thresholds = [
    0,
    300,
    900,
    2700,
    6500,
    14000,
    23000,
    34000,
    48000,
    64000,
    85000,
    100000,
    120000,
    140000,
    165000,
    195000,
    225000,
    265000,
    305000,
    355000,
  ];

  static int levelForXp(int xp) {
    final safeXp = xp < 0 ? 0 : xp;
    for (var i = thresholds.length - 1; i >= 0; i--) {
      if (safeXp >= thresholds[i]) return i + 1;
    }
    return 1;
  }

  /// D&D 5e proficiency bonus by character level.
  /// Levels 1–4: +2, 5–8: +3, 9–12: +4, 13–16: +5, 17–20: +6.
  static int proficiencyBonusForLevel(int level) {
    final safeLevel = level.clamp(1, 20);
    return 2 + ((safeLevel - 1) ~/ 4);
  }

  static int xpForLevel(int level) {
    final safeLevel = level.clamp(1, 20);
    return thresholds[safeLevel - 1];
  }

  static int? nextLevelXp(int level) {
    if (level >= 20) return null;
    return thresholds[level];
  }
}
