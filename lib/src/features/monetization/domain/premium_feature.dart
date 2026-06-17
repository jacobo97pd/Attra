enum PremiumFeature {
  expandedLikes('expanded_likes'),
  unlimitedLikes('unlimited_likes'),
  rewind('rewind'),
  plusFilters('plus_filters'),
  limitedLikesPreview('limited_likes_preview'),
  seeAllLikes('see_all_likes'),
  discoveryPriority('discovery_priority'),
  incognitoMode('incognito_mode'),
  advancedDeclaredFilters('advanced_declared_filters'),
  monthlyBoost('monthly_boost'),
  readReceipts('read_receipts'),
  attrasMonthlyGrant('attras_monthly_grant'),
  aiVisualEngine('ai_visual_engine'),
  aiVisualTraitFilters('ai_visual_trait_filters'),
  visualReferenceSearch('visual_reference_search'),
  aiVisualRanking('ai_visual_ranking'),
  aiExplanations('ai_explanations'),
  aiDataControls('ai_data_controls');

  const PremiumFeature(this.wireName);

  final String wireName;

  bool get isAiVisual {
    switch (this) {
      case PremiumFeature.aiVisualEngine:
      case PremiumFeature.aiVisualTraitFilters:
      case PremiumFeature.visualReferenceSearch:
      case PremiumFeature.aiVisualRanking:
      case PremiumFeature.aiExplanations:
      case PremiumFeature.aiDataControls:
        return true;
      case PremiumFeature.expandedLikes:
      case PremiumFeature.unlimitedLikes:
      case PremiumFeature.rewind:
      case PremiumFeature.plusFilters:
      case PremiumFeature.limitedLikesPreview:
      case PremiumFeature.seeAllLikes:
      case PremiumFeature.discoveryPriority:
      case PremiumFeature.incognitoMode:
      case PremiumFeature.advancedDeclaredFilters:
      case PremiumFeature.monthlyBoost:
      case PremiumFeature.readReceipts:
      case PremiumFeature.attrasMonthlyGrant:
        return false;
    }
  }

  static PremiumFeature? fromValue(Object? value) {
    final String raw = (value ?? '').toString().trim().toLowerCase();
    for (final PremiumFeature feature in PremiumFeature.values) {
      if (feature.wireName == raw || feature.name == raw) {
        return feature;
      }
    }
    return null;
  }
}
