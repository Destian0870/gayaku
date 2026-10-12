import 'package:flutter/material.dart';

import 'screens/add_item_stub.dart';
import 'screens/profile_screen.dart';
import 'screens/wardrobe_screen.dart';
import 'screens/weekly_planner.dart';

/// Route name for each bottom-nav destination. Index 0 is home, the root route.
const _navRouteNames = <int, String>{
  1: '/wardrobe',
  2: '/add-item',
  3: '/planner',
  4: '/profile',
};

Widget? _screenFor(int index) => switch (index) {
  1 => const WardrobeScreen(),
  2 => const AddItemStub(),
  3 => const WeeklyPlanner(),
  4 => const ProfileScreen(),
  _ => null,
};

/// Single source of truth for where a bottom-nav tap goes, so every screen's
/// bar behaves the same. Home pops back to the root route; the rest push, and
/// re-tapping the tab you are already on does nothing.
void openNavDestination(BuildContext context, int index) {
  final navigator = Navigator.of(context);
  final screen = _screenFor(index);
  if (screen == null) {
    navigator.popUntil((route) => route.isFirst);
    return;
  }
  if (ModalRoute.of(context)?.settings.name == _navRouteNames[index]) return;
  navigator.push(
    MaterialPageRoute<void>(
      settings: RouteSettings(name: _navRouteNames[index]),
      builder: (_) => screen,
    ),
  );
}
