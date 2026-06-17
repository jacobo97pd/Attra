enum SubscriptionTier {
  free('free', 0, 'Free'),
  plus('plus', 1, 'Plus'),
  premium('premium', 2, 'Premium'),
  pro('pro', 3, 'Pro IA');

  const SubscriptionTier(this.wireName, this.rank, this.label);

  final String wireName;
  final int rank;
  final String label;

  bool get isPaid => this != SubscriptionTier.free;
  bool get includesAiVisual => this == SubscriptionTier.pro;

  bool atLeast(SubscriptionTier minimum) => rank >= minimum.rank;

  static SubscriptionTier fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final SubscriptionTier tier in SubscriptionTier.values) {
      if (tier.wireName == raw || tier.name == raw) {
        return tier;
      }
    }
    return SubscriptionTier.free;
  }
}
