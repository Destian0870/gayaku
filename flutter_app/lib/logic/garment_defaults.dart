/// What a freshly scanned garment inherits from its Category.
///
/// A Scan reads pixels, and formality plus occasion are not visible in pixels,
/// so the scanner cannot honestly detect them (see docs/adr/0005-classify-the-cutout.md).
/// Scanned items therefore start from a mid-range default for their Category and
/// the user corrects them later in the wardrobe; the recommender keeps working
/// in the meantime because every WardrobeItem still carries both fields.
library;

/// 1 = santai, 5 = formal — the scale `WardrobeItem.formality` already uses.
int defaultFormality(String category) => switch (category) {
  'Tops' => 3,
  'Bottoms' => 3,
  'Outerwear' => 4,
  'Shoes' => 3,
  'Accessories' => 3,
  _ => 3,
};

/// Occasion tags the recommender matches on: `Formal`, `Kasual`,
/// `Smart-Casual`, `Sport`. The middle ground is the safe default.
List<String> defaultOccasions(String category) => switch (category) {
  'Tops' => const ['Kasual', 'Smart-Casual'],
  'Bottoms' => const ['Kasual', 'Smart-Casual'],
  'Outerwear' => const ['Formal', 'Smart-Casual'],
  'Shoes' => const ['Kasual', 'Smart-Casual'],
  'Accessories' => const ['Kasual', 'Smart-Casual'],
  _ => const ['Kasual'],
};
