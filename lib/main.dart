import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/data/repositories/repositories.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/campus_provider.dart';
import 'core/providers/chat_provider.dart';
import 'core/providers/user_provider.dart' show UserProvider;
import 'core/models/chat_model.dart';
import 'core/services/presence_service.dart';
import 'core/services/push_service.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/screens/welcome_screen.dart';
import 'features/auth/screens/registration_wizard.dart';
import 'features/chat/screens/chat_detail_screen.dart';
import 'features/chat/screens/group_chat_screen.dart';
import 'features/navigation/main_navigation.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // No-op unless SUPABASE_URL / SUPABASE_ANON_KEY were passed via
  // --dart-define; the app falls back to mock data in that case.
  await SupabaseService.initialize();
  // Before runApp, so the notification that launched the app from cold is
  // read while it is still there to read.
  await PushService.initialize();
  runApp(const CampusConnectApp());
}

/// Lets a notification tap push a screen from outside the widget tree.
final navigatorKey = GlobalKey<NavigatorState>();

class CampusConnectApp extends StatelessWidget {
  const CampusConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    // The providers live inside the app widget so that tests can pump
    // CampusConnectApp on its own and get the whole wiring.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        // UserProvider needs to know who is signed in: Discover excludes the
        // student themselves, "same department" is relative to them, and
        // every connection row is directional. Feeding it through a proxy
        // rather than having Discover push it from `build()` means the
        // dependency is declared once, in the tree, instead of being a side
        // effect of a screen happening to be on screen.
        ChangeNotifierProxyProvider<AuthProvider, UserProvider>(
          create: (_) => UserProvider(),
          update: (_, auth, users) =>
              (users ?? UserProvider())..syncCurrentUser(auth.currentUser),
        ),
        // Chat is proxied for the same reason: the provider tree lives above
        // the auth gate, so without this a sign-out would leave one student's
        // threads and messages on screen for whoever signs in next.
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, auth, chats) =>
              (chats ?? ChatProvider())..syncCurrentUser(auth.currentUser),
        ),
        ChangeNotifierProvider(create: (_) => CampusProvider()),
      ],
      child: MaterialApp(
        title: 'Campus Connect',
        debugShowCheckedModeBanner: false,
        navigatorKey: navigatorKey,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const AuthGate(),
      ),
    );
  }
}

/// Decides between the welcome flow, the registration wizard and the app.
///
/// Also the one place that knows whether the app is in the foreground, which
/// is what `user_presence` needs. Stateful only for that observer — the tree
/// it builds is unchanged.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  /// The student the live presence channel is currently tracking, so a rebuild
  /// does not re-join it on every frame.
  String? _presenceFor;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // `programs` and `tags` are only readable to a signed-in student, so this
    // is attempted here and again once a session exists.
    unawaited(Repositories.loadReferenceData());
    // A notification is not raised for the thread already on screen, and this
    // is how the service finds out which one that is.
    PushService.currentConversation =
        () => context.read<ChatProvider>().openConversationId;
    PushService.pendingLink.addListener(_followPendingLink);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PushService.pendingLink.removeListener(_followPendingLink);
    PushService.currentConversation = null;
    unawaited(PresenceService.instance.stop());
    super.dispose();
  }

  /// Opens whatever a tapped notification pointed at.
  ///
  /// Only two links exist in V1 — `/chat/<conversation_id>` and
  /// `/connections` — and both land on a screen the app already has. The link
  /// is held rather than followed when it arrives before there is a session:
  /// a cold start from a notification reaches here well before sign-in has
  /// been restored.
  void _followPendingLink() {
    final link = PushService.pendingLink.value;
    if (link == null || link.isEmpty) return;

    final auth = context.read<AuthProvider>();
    if (auth.status != AuthStatus.loggedIn) return;

    PushService.pendingLink.value = null;
    unawaited(_openLink(link));
  }

  Future<void> _openLink(String link) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    if (link == '/connections') {
      // Index 2 is the Connections tab.
      navigator.popUntil((route) => route.isFirst);
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => const MainNavigation(initialIndex: 2),
      ));
      return;
    }

    if (!link.startsWith('/chat/')) return;
    final conversationId = link.substring('/chat/'.length);
    if (conversationId.isEmpty) return;

    final chats = context.read<ChatProvider>();
    // The thread may not be in memory yet — a notification that arrived while
    // the app was closed is exactly that case.
    var chat = chats.chatById(conversationId);
    GroupChat? group = _groupFor(chats, conversationId);
    if (chat == null && group == null) {
      await chats.refresh();
      if (!mounted) return;
      chat = chats.chatById(conversationId);
      group = _groupFor(chats, conversationId);
    }

    // Captured before the closure so the builder cannot see them change.
    final direct = chat;
    final thread = group;
    if (direct == null && thread == null) return;

    navigator.popUntil((route) => route.isFirst);
    navigator.push(MaterialPageRoute(
      builder: (_) => direct != null
          ? ChatDetailScreen(chat: direct)
          : GroupChatScreen(groupId: thread!.id),
    ));
  }

  static GroupChat? _groupFor(ChatProvider chats, String conversationId) {
    for (final g in chats.groupChats) {
      if (g.conversationId == conversationId) return g;
    }
    return null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final auth = context.read<AuthProvider>();
    if (auth.status != AuthStatus.loggedIn) return;

    switch (state) {
      case AppLifecycleState.resumed:
        auth.setPresence(online: true);
        // Badges and trust level can change while the app is backgrounded,
        // and neither arrives through an update response.
        auth.refreshProfile();
        final id = auth.currentUser?.id;
        if (id != null) {
          unawaited(PresenceService.instance
              .start(id, onHeartbeat: () => auth.setPresence(online: true)));
        }
        // Android freezes the socket with the app. Realtime re-joins on the
        // way back but replays nothing, so a message or a connection request
        // that landed in between exists only in Postgres until it is fetched
        // — which is what used to make pulling to refresh feel mandatory.
        unawaited(context.read<ChatProvider>().refresh());
        unawaited(context.read<UserProvider>().resync());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        auth.setPresence(online: false);
        // Leaving the channel is the event: the other side sees this student go
        // offline now rather than when `expire_stale_presence()` next runs.
        unawaited(PresenceService.instance.stop());
        _presenceFor = null;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  /// Reference data and the presence channel both need a session, so they are
  /// driven from the gate rather than from `main()`.
  void _syncSession(AuthProvider auth) {
    final id = auth.status == AuthStatus.loggedIn ? auth.currentUser?.id : null;

    if (id == null) {
      if (_presenceFor != null) {
        _presenceFor = null;
        unawaited(PresenceService.instance.stop());
        // Drops the FCM token, so the next person to sign in on this phone
        // does not receive the last person's messages.
        unawaited(PushService.signOut());
      }
      return;
    }

    if (_presenceFor == id) return;
    _presenceFor = id;
    unawaited(PresenceService.instance
        .start(id, onHeartbeat: () => auth.setPresence(online: true)));
    unawaited(Repositories.loadReferenceData());
    // Needs a session: `register_push_device` writes against auth.uid().
    unawaited(PushService.registerDevice());
    // A notification tapped before sign-in finished restoring.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _followPendingLink());
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    _syncSession(auth);

    switch (auth.status) {
      case AuthStatus.checking:
        return const _SplashScreen();
      case AuthStatus.loggedOut:
        return const WelcomeScreen();
      case AuthStatus.needsProfile:
        return const RegistrationWizard();
      case AuthStatus.loggedIn:
        return const MainNavigation();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              height: 96,
              width: 96,
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.school_outlined,
                  size: 48, color: theme.primaryColor),
            ),
            const SizedBox(height: 24),
            Text('Campus Connect', style: theme.textTheme.titleLarge),
            const SizedBox(height: 24),
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}
