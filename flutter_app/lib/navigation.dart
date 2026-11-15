import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/scan_screen.dart';
import 'screens/wardrobe_screen.dart';
import 'screens/weekly_planner.dart';
import 'theme/app_theme.dart';
import 'widgets/home_bottom_nav.dart';

/// Route name for each bottom-nav destination. Index 0 is home, the root route.
const _navRouteNames = <int, String>{
  1: '/wardrobe',
  2: '/add-item',
  3: '/planner',
  4: '/profile',
};

/// How far a page travels while it swaps, as a fraction of the width. The bar
/// stays put, so the motion has to read as the page changing, not the app.
const _slideFraction = 0.18;

/// The frame the app runs inside: one static floating bar, and the page above
/// it slides in from the side the user is heading towards — home → wardrobe
/// enters from the right, wardrobe → home from the left.
///
/// The bar lives outside the animated area on purpose. Every screen used to
/// carry its own copy, so a push slid the bar along with the page and the
/// taskbar looked like it moved instead of the page.
class NavShell extends StatefulWidget {
  const NavShell({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  State<NavShell> createState() => _NavShellState();
}

class _NavShellState extends State<NavShell> {
  late int _index = widget.initialIndex;
  int _tab = 0;
  bool _favoritesOnly = false;

  /// 1 while moving to a higher index, -1 while going back.
  int _direction = 1;

  void _go(int index, {int initialTab = 0, bool initialFavoritesOnly = false}) {
    if (index == _index) {
      // Same page: only the tab it should show can change.
      if (initialTab == _tab && initialFavoritesOnly == _favoritesOnly) return;
      setState(() {
        _tab = initialTab;
        _favoritesOnly = initialFavoritesOnly;
      });
      return;
    }
    setState(() {
      _direction = index > _index ? 1 : -1;
      _index = index;
      _tab = initialTab;
      _favoritesOnly = initialFavoritesOnly;
    });
  }

  Widget _page() => switch (_index) {
    1 => WardrobeScreen(
      initialTab: _tab,
      initialFavoritesOnly: _favoritesOnly,
      showNav: false,
    ),
    2 => const ScanScreen(),
    3 => const WeeklyPlanner(showNav: false),
    4 => const ProfileScreen(showNav: false),
    _ => const HomeScreen(showNav: false),
  };

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return PopScope(
      // Back on any page but home walks back to home instead of closing the
      // app: the shell holds a single route, so there is nothing to pop.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: _shell(palette),
    );
  }

  Widget _shell(AppPalette palette) {
    return NavScope(
      go: _go,
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: Column(
          children: [
            Expanded(
              child: AnimatedSwitcher(
                duration: AppMotion.route,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: _slide,
                child: KeyedSubtree(
                  key: ValueKey<int>(_index),
                  child: _page(),
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: HomeBottomNav(
                  currentIndex: _index,
                  onTap: _go,
                  onWardrobeLongPress:
                      ({initialTab = 0, favoritesOnly = false}) => _go(
                        1,
                        initialTab: initialTab,
                        initialFavoritesOnly: favoritesOnly,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The incoming page starts off to the side being travelled from; the
  /// outgoing one leaves the other way, since its animation runs backwards.
  Widget _slide(Widget child, Animation<double> animation) {
    final entering = (child.key as ValueKey<int>).value == _index;
    final begin = Offset(
      (entering ? _direction : -_direction) * _slideFraction,
      0,
    );
    return SlideTransition(
      position: animation.drive(Tween(begin: begin, end: Offset.zero)),
      child: child,
    );
  }
}

/// Hands the shell's page switcher to the screens inside it, so a deep widget
/// (a quick action, a card) can move the shell instead of pushing a route.
class NavScope extends InheritedWidget {
  const NavScope({super.key, required this.go, required super.child});

  final void Function(int index, {int initialTab, bool initialFavoritesOnly})
  go;

  @override
  bool updateShouldNotify(NavScope oldWidget) => false;
}

/// True when [context] sits inside a [NavShell] page rather than a pushed
/// route, so a screen can send the user home instead of popping.
bool navEmbedded(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<NavScope>() != null;

/// Single source of truth for where a bottom-nav tap goes. Inside the shell it
/// switches pages; a screen pumped on its own (tests, a pushed route) still
/// pushes, and re-tapping the tab you are on does nothing.
void openNavDestination(
  BuildContext context,
  int index, {
  int initialTab = 0,
  bool initialFavoritesOnly = false,
}) {
  final scope = context.dependOnInheritedWidgetOfExactType<NavScope>();
  if (scope != null) {
    scope.go(
      index,
      initialTab: initialTab,
      initialFavoritesOnly: initialFavoritesOnly,
    );
    return;
  }
  final navigator = Navigator.of(context);
  final screen = switch (index) {
    1 => WardrobeScreen(
      initialTab: initialTab,
      initialFavoritesOnly: initialFavoritesOnly,
    ),
    2 => const ScanScreen(),
    3 => const WeeklyPlanner(),
    4 => const ProfileScreen(),
    _ => null,
  };
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
