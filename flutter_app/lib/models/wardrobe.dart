/// Domain models for the wardrobe home screen.
///
/// A [Look] is a styled outfit suggestion rendered as "Today's Look".
/// A [WardrobeItem] is a single owned garment rendered in "Recently Added".
/// A Look may reference multiple WardrobeItems but is not itself one.
library;

import 'package:flutter/material.dart';

class Look {
  const Look({
    required this.id,
    required this.title,
    required this.styleTag,
    required this.subtitle,
    required this.imagePath,
    this.colorHarmony = 0,
    this.items = const [],
    this.savedAt,
  });

  final String id;
  final String title;

  /// Short occasion label shown as a pill on the look card.
  final String styleTag;
  final String subtitle;
  final String imagePath;

  /// Percentage match from the outfit matcher; 0 when not scored yet.
  final int colorHarmony;

  /// Garments that make up this look, for the detail view.
  final List<LookItem> items;

  /// When the user saved this look; null for a suggestion not saved yet.
  final DateTime? savedAt;
}

/// A single garment inside a [Look].
class LookItem {
  const LookItem({
    required this.type,
    required this.name,
    required this.imagePath,
    required this.icon,
  });

  final String type;
  final String name;
  final String imagePath;
  final String icon;
}

/// Ordering applied to the saved looks list.
enum LookSortOption { newest, oldest, titleAscending, titleDescending }

class WardrobeItem {
  const WardrobeItem({
    required this.name,
    required this.category,
    required this.imagePath,
    this.brand = '',
    this.colorName = '',
    this.color = const Color(0xFFD3A277),
    this.formality = 3,
    this.occasions = const [],
  });

  final String name;
  final String category;
  final String imagePath;

  /// Optional maker label, rendered as `Category • Brand` under the name.
  final String brand;

  /// Indonesian color label shown on the detail page, e.g. `Krem`.
  final String colorName;

  /// Dominant garment color, used for HSV color-harmony scoring.
  final Color color;

  /// 1 = santai, 5 = formal. Compared against a partner item's level.
  final int formality;

  /// Occasions this item suits: `Formal`, `Kasual`, `Smart-Casual`, `Sport`.
  final List<String> occasions;
}

/// Catalog shown on the Wardrobe screen, grouped by the chips below.
const wardrobeItems = <WardrobeItem>[
  WardrobeItem(
    name: 'Silk Blouse',
    category: 'Tops',
    brand: 'Zara',
    colorName: 'Krem',
    color: Color(0xFFEFE3D0),
    formality: 4,
    occasions: ['Formal', 'Smart-Casual'],
    imagePath: 'assets/images/silk_blouse.png',
  ),
  WardrobeItem(
    name: 'Beige Trench',
    category: 'Outerwear',
    brand: 'Burberry',
    colorName: 'Beige',
    color: Color(0xFFD8C3A5),
    formality: 4,
    occasions: ['Formal', 'Smart-Casual'],
    imagePath: 'assets/images/beige_trench.jpg',
  ),
  WardrobeItem(
    name: 'Classic Sneakers',
    category: 'Shoes',
    brand: 'Nike',
    colorName: 'Putih',
    color: Color(0xFFF5F5F0),
    formality: 2,
    occasions: ['Kasual', 'Sport'],
    imagePath: 'assets/images/classic_sneakers.jpg',
  ),
  WardrobeItem(
    name: 'Gold Link Chain',
    category: 'Accessories',
    brand: 'Mejuri',
    colorName: 'Emas',
    color: Color(0xFFC9A227),
    formality: 4,
    occasions: ['Formal', 'Smart-Casual'],
    imagePath: 'assets/images/gold_link_chain.jpg',
  ),
  WardrobeItem(
    name: 'Straight Leg Jeans',
    category: 'Bottoms',
    brand: "Levi's",
    colorName: 'Biru Denim',
    color: Color(0xFF3B5A80),
    formality: 2,
    occasions: ['Kasual', 'Smart-Casual'],
    imagePath: 'assets/images/straight_leg_jeans.jpg',
  ),
  WardrobeItem(
    name: 'Linen Shirt',
    category: 'Tops',
    brand: 'Uniqlo',
    colorName: 'Putih Gading',
    color: Color(0xFFF2EDE3),
    formality: 3,
    occasions: ['Kasual', 'Smart-Casual'],
    imagePath: 'assets/images/linen_shirt.jpg',
  ),
  WardrobeItem(
    name: 'Pleated Midi Skirt',
    category: 'Bottoms',
    brand: 'COS',
    colorName: 'Cokelat Tanah',
    color: Color(0xFF8B5E3C),
    formality: 4,
    occasions: ['Formal', 'Smart-Casual'],
    imagePath: 'assets/images/pleated_midi_skirt.jpg',
  ),
  WardrobeItem(
    name: 'Leather Loafers',
    category: 'Shoes',
    brand: 'Dr. Martens',
    colorName: 'Cokelat Tua',
    color: Color(0xFF5A3A22),
    formality: 4,
    occasions: ['Formal', 'Smart-Casual'],
    imagePath: 'assets/images/leather_loafers.jpg',
  ),
  WardrobeItem(
    name: 'Tote Bag Canvas',
    category: 'Accessories',
    brand: 'Muji',
    colorName: 'Abu Muda',
    color: Color(0xFFBFBCB4),
    formality: 2,
    occasions: ['Kasual'],
    imagePath: 'assets/images/tote_bag_canvas.jpg',
  ),
];

/// Chip labels: the leading chip clears the category filter.
const wardrobeCategories = <String>[
  'All Items',
  'Tops',
  'Bottoms',
  'Outerwear',
  'Shoes',
  'Accessories',
];

/// Sample content for the static home screen.
const todaysLook = Look(
  id: 'todays-look',
  title: 'Effortless Linen Dress',
  subtitle: 'Breezy layers for a warm afternoon out',
  styleTag: 'Casual Chic',
  imagePath: 'assets/images/todays_look.png',
);

const recentItems = <WardrobeItem>[
  WardrobeItem(
    name: 'White Sneakers',
    category: 'Shoes',
    imagePath: 'assets/images/white_sneakers.png',
  ),
  WardrobeItem(
    name: 'Gold Chain',
    category: 'Accessories',
    imagePath: 'assets/images/gold_chain.png',
  ),
  WardrobeItem(
    name: 'Silk Blouse',
    category: 'Tops',
    imagePath: 'assets/images/silk_blouse.png',
  ),
];

/// Saved looks shown on the Favorites screen.
final favoriteLooks = <Look>[
  Look(
    id: 'beige-trench-denim',
    title: 'Beige Trench & Denim',
    styleTag: 'Casual Chic',
    subtitle: 'Perfect for a sunny coffee run.',
    imagePath: 'assets/images/beige_trench_denim.png',
    colorHarmony: 94,
    savedAt: DateTime(2026, 10, 8, 14, 30),
    items: [
      LookItem(
        type: 'Top',
        name: 'Silk Blouse',
        imagePath: 'assets/images/silk_blouse.png',
        icon: 'top',
      ),
      LookItem(
        type: 'Bottom',
        name: 'Straight Leg Jeans',
        imagePath: 'assets/images/straight_leg_jeans.jpg',
        icon: 'bottom',
      ),
      LookItem(
        type: 'Shoes',
        name: 'Classic Sneakers',
        imagePath: 'assets/images/white_sneakers.png',
        icon: 'shoes',
      ),
      LookItem(
        type: 'Accessory',
        name: 'Gold Link Chain',
        imagePath: 'assets/images/gold_chain.png',
        icon: 'accessory',
      ),
    ],
  ),
  Look(
    id: 'linen-office-set',
    title: 'Linen Office Set',
    styleTag: 'Office',
    subtitle: 'Polished layers for a focused workday.',
    imagePath: 'assets/images/linen_office_set.jpg',
    colorHarmony: 91,
    savedAt: DateTime(2026, 10, 9, 9, 15),
    items: [
      LookItem(
        type: 'Top',
        name: 'Linen Shirt',
        imagePath: 'assets/images/linen_shirt.jpg',
        icon: 'top',
      ),
      LookItem(
        type: 'Bottom',
        name: 'Tailored Trousers',
        imagePath: 'assets/images/tailored_trousers.jpg',
        icon: 'bottom',
      ),
      LookItem(
        type: 'Shoes',
        name: 'Leather Loafers',
        imagePath: 'assets/images/leather_loafers.jpg',
        icon: 'shoes',
      ),
      LookItem(
        type: 'Accessory',
        name: 'Minimal Watch',
        imagePath: 'assets/images/minimal_watch.jpg',
        icon: 'accessory',
      ),
    ],
  ),
];
