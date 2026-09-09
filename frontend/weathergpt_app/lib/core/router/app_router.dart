import 'package:go_router/go_router.dart';

import '../../features/chat/chat_screen.dart';
import '../../features/gallery/gallery_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/saved/saved_places_screen.dart';

/// A plain route stack — deliberately **no** bottom navigation bar.
///
/// The previous shell used `StatefulShellRoute.indexedStack` with a
/// four-tab `NavigationBar`. Neither reference app has one, and it was the
/// single biggest reason the first build read as a generic Android app
/// rather than the product the references show. Navigation now lives in
/// the drawer (`AppDrawer`), reachable from the chrome on every screen.
///
/// `app_router_test.dart` asserts the absence of `NavigationBar`, so the
/// tab bar cannot quietly come back.
final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatScreen(),
    ),
    GoRoute(
      path: '/saved',
      builder: (context, state) => const SavedPlacesScreen(),
    ),
    GoRoute(
      path: '/gallery',
      builder: (context, state) => const GalleryScreen(),
    ),
  ],
);
