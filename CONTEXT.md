# Gayaku — Ubiquitous Language

Glossary of domain terms. No implementation details.

## Wardrobe

**WardrobeItem**:
A single garment the user owns. Rendered in "Recently Added" and in the Wardrobe tab. A Look may reference multiple WardrobeItems but is not itself one.
_Avoid_: garment, clothing item, piece, product

**Category**:
One of the five wardrobe groupings: Tops, Bottoms, Outerwear, Shoes, Accessories. Filters the wardrobe and decides which items may be worn together.
_Avoid_: slot, type, class

**Subcategory**:
The specific garment type within a Category, such as Jeans, Denim jacket or Kemeja. Comes from a Scan's detection or from the user's own edit.
_Avoid_: label, article type, subtype, fine label

**Dominant colour**:
The one colour reported for a WardrobeItem by a Scan, shown as a name next to a swatch of that colour.
_Avoid_: base colour, primary colour

## Scanner

**Scan**:
Turning a photo of one garment into a wardrobe entry: cut out, classified into a Category, colour read, then corrected by the user.
_Avoid_: capture, upload, import

**Cutout**:
The garment image with its background removed. Becomes the WardrobeItem's image.
_Avoid_: matte, mask, transparent image

**Correction**:
The user fixing what a Scan detected — name, Category, Dominant colour — before the item is saved.
_Avoid_: review, adjustment, manual fix

## Outfits

**Look**:
A styled outfit suggestion (title, subtitle, style tag, image). Rendered as "Today's Look". Distinct from a garment.
_Avoid_: outfit idea, recommendation card

**Style tag**:
Short occasion label on a Look, e.g. "Casual Chic".
_Avoid_: occasion tag, category label

**Batas minimum**:
The lowest match the user accepts for a combination, set per combination and shown against its live match percentage.
_Avoid_: threshold, minimum score, target

## Home

**QuickAction**:
A shortcut card to a destination not yet built (e.g. Your Favorite, Plan Week).
_Avoid_: shortcut card, tile

**Greeting**:
Time-of-day salutation plus the user's name (e.g. "Good Evening, Isabella").
_Avoid_: salutation, header
