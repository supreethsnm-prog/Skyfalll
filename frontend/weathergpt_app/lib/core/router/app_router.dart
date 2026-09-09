import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/chat/chat_screen.dart';
import '../../features/gallery/gallery_screen.dart';
import '../../features/shell/placeholder_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => Scaffold(
        body: navigationShell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: navigationShell.goBranch,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.chat_outlined), label: 'Chat'),
            NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              label: 'Forecast',
            ),
            NavigationDestination(icon: Icon(Icons.apps_outlined), label: 'More'),
          ],
        ),
      ),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const PlaceholderScreen(title: 'Home'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/chat',
              builder: (context, state) => const ChatScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/forecast',
              builder: (context, state) => const PlaceholderScreen(title: 'Forecast'),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/more',
              builder: (context, state) => const PlaceholderScreen(title: 'More'),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/gallery',
      builder: (context, state) => const GalleryScreen(),
    ),
  ],
);
