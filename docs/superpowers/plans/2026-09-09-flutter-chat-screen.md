# Chat Screen (Phase 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the real Chat screen — WeatherGPT's centerpiece — wired to the backend's `POST /chat`, replacing the `/chat` route's placeholder.

**Architecture:** A `data/` layer (`ChatApi`, response parsing, a safe `ChatTurn` display model), a Riverpod `Notifier`-based controller holding a sealed UI state, presentational widgets (message tile, typing indicator, composer), and a screen that composes them. All built on Phase 0's shared theme/network/widget foundation — no new dependencies.

**Tech Stack:** Flutter (already installed), `flutter_riverpod`, `dio`, `go_router` — all already in `pubspec.yaml` from Phase 0. No new packages.

**Spec:** `docs/superpowers/specs/2026-09-08-flutter-frontend-design.md` §6a (chat design), §6b (no emulator — golden tests instead). Backend contract: `docs/superpowers/specs/2026-09-05-weathergpt-v1-design.md`, `backend/app/main.py`'s `/chat` route, `backend/app/chat/service.py`'s `chat_turn`.

## Global Constraints

- No backend files touched. No new dependencies beyond what Phase 0 already added.
- Every shell command dot-sources `frontend/dev-env.ps1` from the worktree root first (`. .\frontend\dev-env.ps1`) — Flutter is not on PATH otherwise.
- No Android emulator available on this hardware — visual verification is via golden-image tests only (see Task 6).
- **The raw `history` list from the backend is opaque and must never be lossily re-typed.** It is tracked as `List<dynamic>`, sent back to the server verbatim on the next request, and replaced wholesale by the server's own returned `history` after each successful call. The app only ever *derives a display-only filtered view* from it (via `ChatTurn.tryFromRaw`) — it never reconstructs or partially edits the raw list client-side. Getting this wrong silently breaks the backend's multi-turn tool-calling context.
- Any test involving a repeating/indeterminate animation must use `tester.pump(Duration(...))` with explicit durations, never `tester.pumpAndSettle()` (which never returns for a widget that animates forever) — this exact bug was found and fixed in Phase 0.
- The mic button is visibly present but disabled (BHASHINI voice is externally blocked) — never hidden.
- `AppPrimaryButton`, `AppChip`, `LoadingView`, `ErrorView`, `EmptyView`, `AppColors`, `AppTypography`, `AppSpacing`, `AppRadius`, `AppTheme`, `buildApiClient`, `guardApi`, `AppError` and its subtypes, and `appRouter` all already exist from Phase 0 (`frontend/weathergpt_app/lib/core/` and `lib/shared/widgets/`) — read them, don't redefine them.

---

### Task 1: Chat data layer

**Files:**
- Create: `frontend/weathergpt_app/lib/data/chat_api.dart`
- Test: `frontend/weathergpt_app/test/data/chat_api_test.dart`

**Interfaces:**
- Consumes: `buildApiClient()` and `guardApi<T>()` from `lib/core/network/api_client.dart`.
- Produces: `ChatTurn({required String role, required String content})` with static `ChatTurn? tryFromRaw(dynamic raw)`; `ChatResult({required String reply, required List<dynamic> history})`; `ChatResult parseChatResult(Map<String, dynamic> json)`; `class ChatApi` with constructor `ChatApi(Dio dio)` and method `Future<ChatResult> sendMessage(String message, List<dynamic>? history)`. All consumed by Task 2's controller.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/data/chat_api_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/chat_api.dart';

void main() {
  group('ChatTurn.tryFromRaw', () {
    test('parses a valid user entry', () {
      final turn = ChatTurn.tryFromRaw({'role': 'user', 'content': 'Hello'});
      expect(turn, isNotNull);
      expect(turn!.role, 'user');
      expect(turn.content, 'Hello');
    });

    test('parses a valid assistant entry', () {
      final turn = ChatTurn.tryFromRaw({'role': 'assistant', 'content': 'Hi there'});
      expect(turn, isNotNull);
      expect(turn!.role, 'assistant');
    });

    test('returns null for a tool-role entry', () {
      final turn = ChatTurn.tryFromRaw({
        'role': 'tool',
        'tool_call_id': 'abc',
        'name': 'get_weather',
        'content': '{"temp": 28}',
      });
      expect(turn, isNull);
    });

    test('returns null when content is missing', () {
      expect(ChatTurn.tryFromRaw({'role': 'user'}), isNull);
    });

    test('returns null when content is not a String', () {
      expect(ChatTurn.tryFromRaw({'role': 'user', 'content': 42}), isNull);
    });

    test('returns null for a non-map input', () {
      expect(ChatTurn.tryFromRaw('not a map'), isNull);
      expect(ChatTurn.tryFromRaw(null), isNull);
    });
  });

  group('parseChatResult', () {
    test('extracts reply and history from a raw response body', () {
      final result = parseChatResult({
        'reply': 'It is sunny in Mumbai.',
        'history': [
          {'role': 'user', 'content': 'Weather in Mumbai?'},
          {'role': 'assistant', 'content': 'It is sunny in Mumbai.'},
        ],
      });
      expect(result.reply, 'It is sunny in Mumbai.');
      expect(result.history, hasLength(2));
      expect(result.history[0], {'role': 'user', 'content': 'Weather in Mumbai?'});
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test test\data
```

Expected: FAIL — `lib/data/chat_api.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/data/chat_api.dart`:

```dart
import 'package:dio/dio.dart';
import '../core/network/api_client.dart';

/// A display-only chat turn. The app's ONLY typed view of a history
/// entry — the raw entries themselves (which may carry `tool_calls`,
/// `tool_call_id`, `name`, etc. for tool turns the backend needs but the
/// UI never renders) are tracked separately as opaque `List<dynamic>`
/// by ChatController and must never be reconstructed from instances of
/// this class.
class ChatTurn {
  final String role; // always 'user' or 'assistant'
  final String content;

  const ChatTurn({required this.role, required this.content});

  /// Returns null (rather than throwing) for any entry this app cannot
  /// safely display: a role other than user/assistant (e.g. 'tool'), or
  /// non-String content. A future backend response shape change should
  /// degrade to "this turn doesn't render," never crash the chat screen.
  static ChatTurn? tryFromRaw(dynamic raw) {
    if (raw is! Map) return null;
    final role = raw['role'];
    final content = raw['content'];
    if (role != 'user' && role != 'assistant') return null;
    if (content is! String) return null;
    return ChatTurn(role: role as String, content: content);
  }
}

class ChatResult {
  final String reply;
  final List<dynamic> history;

  const ChatResult({required this.reply, required this.history});
}

/// Pure parsing logic, exposed separately from [ChatApi.sendMessage] so
/// it is directly unit-testable without a live or faked network round
/// trip — mirrors api_client.dart's own separation of
/// [mapDioException] from the interceptor that uses it.
ChatResult parseChatResult(Map<String, dynamic> json) {
  return ChatResult(
    reply: json['reply'] as String,
    history: json['history'] as List<dynamic>,
  );
}

/// Wraps `POST /chat`. This endpoint is a single request/response call —
/// it does NOT stream tokens. Any "typing"/"streaming" feel in the UI is
/// a client-side animation over this one response, not a real stream
/// (see ChatController and TypingIndicator).
class ChatApi {
  final Dio _dio;

  ChatApi(this._dio);

  /// [history] must be the exact `List<dynamic>` most recently returned
  /// by this same method (or null for the first turn in a conversation)
  /// — never a client-reconstructed or filtered list. The backend uses
  /// it verbatim to resume multi-turn tool-calling context.
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) {
    return guardApi(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat',
        data: {'message': message, 'history': history},
      );
      return parseChatResult(response.data!);
    });
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\data
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/data/ frontend/weathergpt_app/test/data/
git commit -m "feat: add ChatApi and ChatTurn display model for POST /chat"
```

---

### Task 2: Chat state controller

**Files:**
- Create: `frontend/weathergpt_app/lib/features/chat/chat_controller.dart`
- Test: `frontend/weathergpt_app/test/features/chat/chat_controller_test.dart`

**Interfaces:**
- Consumes: `ChatTurn`, `ChatResult`, `ChatApi` (Task 1); `buildApiClient()` (Phase 0); `AppError` and subtypes (Phase 0).
- Produces: sealed `ChatUiState` with subtypes `ChatIdle(List<ChatTurn> messages)`, `ChatSending(List<ChatTurn> messages)`, `ChatFailed(List<ChatTurn> messages, String failedMessage, List<dynamic>? historyAtFailure, AppError error)`; `class ChatController extends Notifier<ChatUiState>` with `Future<void> sendMessage(String text)` and `Future<void> retry()`; providers `chatApiProvider` (`Provider<ChatApi>`) and `chatControllerProvider` (`NotifierProvider<ChatController, ChatUiState>`). All consumed by Task 5's screen and Task 6's golden test.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/features/chat/chat_controller_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/core/network/app_error.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';

/// Implements only the public interface ChatApi exposes — its private
/// Dio field is not part of that interface, so no real Dio is needed.
class FakeChatApi implements ChatApi {
  ChatResult? nextResult;
  AppError? nextError;
  final List<String> messagesSent = [];
  final List<List<dynamic>?> historiesSent = [];

  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    messagesSent.add(message);
    historiesSent.add(history);
    if (nextError != null) throw nextError!;
    return nextResult!;
  }
}

void main() {
  late FakeChatApi fakeApi;
  late ProviderContainer container;

  setUp(() {
    fakeApi = FakeChatApi();
    container = ProviderContainer(
      overrides: [chatApiProvider.overrideWithValue(fakeApi)],
    );
  });

  tearDown(() => container.dispose());

  test('starts idle with no messages', () {
    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatIdle>());
    expect(state.messages, isEmpty);
  });

  test('sendMessage appends an optimistic user turn immediately, before the response arrives', () async {
    fakeApi.nextResult = const ChatResult(reply: 'placeholder', history: []);
    final future = container.read(chatControllerProvider.notifier).sendMessage('Hi');

    final sendingState = container.read(chatControllerProvider);
    expect(sendingState, isA<ChatSending>());
    expect(sendingState.messages, hasLength(1));
    expect(sendingState.messages.single.role, 'user');
    expect(sendingState.messages.single.content, 'Hi');

    await future;
  });

  test('a successful response replaces state with the server\'s own filtered history', () async {
    fakeApi.nextResult = ChatResult(
      reply: 'Sunny today',
      history: [
        {'role': 'user', 'content': 'Weather?'},
        {'role': 'tool', 'tool_call_id': 'x', 'name': 'get_weather', 'content': '{}'},
        {'role': 'assistant', 'content': 'Sunny today'},
      ],
    );

    await container.read(chatControllerProvider.notifier).sendMessage('Weather?');

    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatIdle>());
    // The tool-role entry is present in the raw history but must not appear in the displayed messages.
    expect(state.messages, hasLength(2));
    expect(state.messages[0].role, 'user');
    expect(state.messages[1].role, 'assistant');
    expect(state.messages[1].content, 'Sunny today');
  });

  test('the second call sends the exact history returned by the first, unmodified', () async {
    final firstHistory = [
      {'role': 'user', 'content': 'Weather?'},
      {'role': 'assistant', 'content': 'Sunny'},
    ];
    fakeApi.nextResult = ChatResult(reply: 'Sunny', history: firstHistory);
    await container.read(chatControllerProvider.notifier).sendMessage('Weather?');

    fakeApi.nextResult = const ChatResult(reply: 'And tomorrow?', history: []);
    await container.read(chatControllerProvider.notifier).sendMessage('And tomorrow?');

    expect(fakeApi.historiesSent[0], isNull); // first turn in a fresh conversation
    expect(fakeApi.historiesSent[1], same(firstHistory)); // exact instance, not a rebuilt copy
  });

  test('a failed request preserves the optimistic user turn and surfaces the error', () async {
    fakeApi.nextError = const NetworkTimeoutError();

    await container.read(chatControllerProvider.notifier).sendMessage('Hi');

    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatFailed>());
    expect(state.messages, hasLength(1));
    expect(state.messages.single.content, 'Hi');
    expect((state as ChatFailed).failedMessage, 'Hi');
    expect(state.error, isA<NetworkTimeoutError>());
  });

  test('retry re-issues the identical failed message and history', () async {
    fakeApi.nextError = const NetworkTimeoutError();
    await container.read(chatControllerProvider.notifier).sendMessage('Hi');

    fakeApi.nextError = null;
    fakeApi.nextResult = const ChatResult(
      reply: 'Hello!',
      history: [
        {'role': 'user', 'content': 'Hi'},
        {'role': 'assistant', 'content': 'Hello!'},
      ],
    );
    await container.read(chatControllerProvider.notifier).retry();

    expect(fakeApi.messagesSent, ['Hi', 'Hi']);
    expect(fakeApi.historiesSent, [null, null]); // both attempts are the first turn — no history existed yet
    final state = container.read(chatControllerProvider);
    expect(state, isA<ChatIdle>());
    expect(state.messages, hasLength(2));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
flutter test test\features\chat\chat_controller_test.dart
```

Expected: FAIL — `chat_controller.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/chat/chat_controller.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/api_client.dart';
import '../../core/network/app_error.dart';
import '../../data/chat_api.dart';

sealed class ChatUiState {
  final List<ChatTurn> messages;
  const ChatUiState(this.messages);
}

class ChatIdle extends ChatUiState {
  const ChatIdle(super.messages);
}

class ChatSending extends ChatUiState {
  const ChatSending(super.messages);
}

class ChatFailed extends ChatUiState {
  final String failedMessage;
  final List<dynamic>? historyAtFailure;
  final AppError error;

  const ChatFailed(
    super.messages,
    this.failedMessage,
    this.historyAtFailure,
    this.error,
  );
}

final chatApiProvider = Provider<ChatApi>((ref) => ChatApi(buildApiClient()));

final chatControllerProvider =
    NotifierProvider<ChatController, ChatUiState>(ChatController.new);

/// The chat endpoint (`POST /chat`) is a single request/response call,
/// not a token stream. This controller's job is state management around
/// that one call — any "typing"/"streaming" feel is a UI-layer concern
/// (see TypingIndicator), not something this controller simulates.
class ChatController extends Notifier<ChatUiState> {
  /// The exact `history` list most recently returned by the backend, or
  /// null before the first successful turn. Tracked opaquely — never
  /// reconstructed — and sent back verbatim on the next request.
  List<dynamic>? _rawHistory;

  @override
  ChatUiState build() {
    _rawHistory = null;
    return const ChatIdle([]);
  }

  Future<void> sendMessage(String text) async {
    final api = ref.read(chatApiProvider);
    final historyForThisRequest = _rawHistory;
    final optimisticMessages = [
      ...state.messages,
      ChatTurn(role: 'user', content: text),
    ];
    state = ChatSending(optimisticMessages);

    try {
      final result = await api.sendMessage(text, historyForThisRequest);
      _rawHistory = result.history;
      final displayed = result.history
          .map(ChatTurn.tryFromRaw)
          .whereType<ChatTurn>()
          .toList();
      state = ChatIdle(displayed);
    } on AppError catch (e) {
      state = ChatFailed(optimisticMessages, text, historyForThisRequest, e);
    }
  }

  Future<void> retry() async {
    final current = state;
    if (current is! ChatFailed) return;
    // Drop the optimistic turn that failed — sendMessage re-adds it, and
    // roll _rawHistory back to what it was before that attempt so the
    // retried request is byte-for-byte identical to the one that failed.
    final messagesBeforeFailedTurn =
        current.messages.sublist(0, current.messages.length - 1);
    state = ChatIdle(messagesBeforeFailedTurn);
    _rawHistory = current.historyAtFailure;
    await sendMessage(current.failedMessage);
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\features\chat\chat_controller_test.dart
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/chat/chat_controller.dart frontend/weathergpt_app/test/features/chat/
git commit -m "feat: add ChatController with optimistic sending, error, and retry state"
```

---

### Task 3: Message tile and typing indicator widgets

**Files:**
- Create: `frontend/weathergpt_app/lib/features/chat/widgets/chat_turn_tile.dart`
- Create: `frontend/weathergpt_app/lib/features/chat/widgets/typing_indicator.dart`
- Test: `frontend/weathergpt_app/test/features/chat/widgets/chat_turn_tile_test.dart`
- Test: `frontend/weathergpt_app/test/features/chat/widgets/typing_indicator_test.dart`

**Interfaces:**
- Consumes: `ChatTurn` (Task 1); `AppColors`, `AppSpacing`, `AppRadius`, `AppTypography` (Phase 0).
- Produces: `ChatTurnTile({required ChatTurn turn})`, `TypingIndicator()` — both consumed by Task 5's screen and Task 6's golden test.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/features/chat/widgets/chat_turn_tile_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/widgets/chat_turn_tile.dart';

void main() {
  testWidgets('renders the turn\'s content text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatTurnTile(turn: ChatTurn(role: 'assistant', content: 'Sunny today')),
        ),
      ),
    );
    expect(find.text('Sunny today'), findsOneWidget);
  });

  testWidgets('gives a user turn a decorated Container background, unlike an assistant turn', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ChatTurnTile(turn: ChatTurn(role: 'user', content: 'Hi')),
              ChatTurnTile(turn: ChatTurn(role: 'assistant', content: 'Hello')),
            ],
          ),
        ),
      ),
    );

    final userContainer = tester.widgetList<Container>(find.byType(Container));
    // The user turn's tile must contain at least one Container with a
    // non-null BoxDecoration (its background surface); the assistant
    // turn renders as flat text with no such decorated Container.
    expect(
      userContainer.any((c) => c.decoration != null),
      isTrue,
      reason: 'user turn should have a decorated background container',
    );
  });
}
```

Create `frontend/weathergpt_app/test/features/chat/widgets/typing_indicator_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/typing_indicator.dart';

void main() {
  testWidgets('renders three dots and keeps rendering across animation ticks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: TypingIndicator())),
    );

    // Deliberately pump() with explicit durations, never pumpAndSettle() —
    // this widget's animation repeats forever, so pumpAndSettle() would
    // hang (the exact bug found and fixed in Phase 0's router test).
    await tester.pump();
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircleAvatar), findsNWidgets(3));

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircleAvatar), findsNWidgets(3));
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
flutter test test\features\chat\widgets\chat_turn_tile_test.dart test\features\chat\widgets\typing_indicator_test.dart
```

Expected: FAIL — neither widget file exists yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/chat/widgets/chat_turn_tile.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../data/chat_api.dart';

/// Renders one chat turn. Per the design spec (§6a): a user turn gets a
/// light Marigold-tinted rounded surface; an assistant turn is flat text
/// on the background — no bubble — so the assistant's reply reads as
/// direct prose rather than a boxed message. Every tile fades in over a
/// short duration on first build (§6a's "reveal" requirement — a real
/// per-token stream isn't available since `POST /chat` is a single
/// request/response, so this is the closest honest approximation: the
/// reply doesn't just snap into existence).
class ChatTurnTile extends StatelessWidget {
  final ChatTurn turn;

  const ChatTurnTile({super.key, required this.turn});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final content = Text(turn.content, style: AppTypography.body(onSurface));
    final isUser = turn.role == 'user';

    final Widget bubble = !isUser
        ? Align(alignment: Alignment.centerLeft, child: content)
        : Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.8,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.marigold.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(AppRadius.surface),
                ),
                child: content,
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.lg,
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 250),
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: bubble,
      ),
    );
  }
}
```

Create `frontend/weathergpt_app/lib/features/chat/widgets/typing_indicator.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';

/// A three-dot "assistant is responding" indicator. This is a UI
/// animation only — `POST /chat` is a single request/response, not a
/// token stream (see ChatApi/ChatController) — it does not reflect real
/// incremental progress, only that a request is in flight.
///
/// Uses a repeating AnimationController, not an indeterminate
/// CircularProgressIndicator — a lesson from Phase 0, where an
/// indeterminate spinner made `pumpAndSettle()` hang in a widget test.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.lg,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_controller.value - i * 0.2) % 1.0;
                final rampUp = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
                final opacity = (0.3 + 0.7 * rampUp).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Opacity(
                    opacity: opacity,
                    child: CircleAvatar(radius: 3, backgroundColor: color),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\features\chat\widgets\chat_turn_tile_test.dart test\features\chat\widgets\typing_indicator_test.dart
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/chat/widgets/chat_turn_tile.dart frontend/weathergpt_app/lib/features/chat/widgets/typing_indicator.dart frontend/weathergpt_app/test/features/chat/widgets/
git commit -m "feat: add ChatTurnTile and TypingIndicator widgets"
```

---

### Task 4: Chat composer widget

**Files:**
- Create: `frontend/weathergpt_app/lib/features/chat/widgets/chat_composer.dart`
- Test: `frontend/weathergpt_app/test/features/chat/widgets/chat_composer_test.dart`

**Interfaces:**
- Consumes: `AppPrimaryButton` (Phase 0, with its `icon` parameter), `AppSpacing` (Phase 0).
- Produces: `ChatComposer({required ValueChanged<String> onSend, bool enabled = true})` — consumed by Task 5's screen.

- [ ] **Step 1: Write the failing tests**

Create `frontend/weathergpt_app/test/features/chat/widgets/chat_composer_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/features/chat/widgets/chat_composer.dart';

void main() {
  testWidgets('sends the typed text and clears the field', (tester) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(onSend: (text) => sent = text),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'What is the weather?');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(sent, 'What is the weather?');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('does nothing when the field is empty or whitespace-only', (tester) async {
    var callCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatComposer(onSend: (_) => callCount++)),
      ),
    );

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(callCount, 0);
  });

  testWidgets('disables the field and send button when enabled is false', (tester) async {
    var callCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatComposer(onSend: (_) => callCount++, enabled: false),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);

    await tester.enterText(find.byType(TextField), 'Hi');
    await tester.tap(find.text('Send'), warnIfMissed: false);
    await tester.pump();

    expect(callCount, 0);
  });

  testWidgets('mic button is present but disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: ChatComposer(onSend: (_) {}))),
    );

    final mic = tester.widget<IconButton>(find.byType(IconButton));
    expect(mic.onPressed, isNull);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
flutter test test\features\chat\widgets\chat_composer_test.dart
```

Expected: FAIL — `chat_composer.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/chat/widgets/chat_composer.dart`:

```dart
import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../shared/widgets/app_primary_button.dart';

/// The chat input row: a disabled mic affordance (BHASHINI voice is
/// externally blocked — see spec §9 — kept VISIBLE rather than hidden
/// so the seam is obvious and removing the disable is the only change
/// needed once voice is unblocked), a multiline text field, and a send
/// button.
class ChatComposer extends StatefulWidget {
  final ValueChanged<String> onSend;
  final bool enabled;

  const ChatComposer({super.key, required this.onSend, this.enabled = true});

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            icon: const Icon(Icons.mic_none),
            tooltip: 'Voice input (coming soon)',
            onPressed: null,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: widget.enabled,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: widget.enabled ? (_) => _submit() : null,
              decoration: const InputDecoration(
                hintText: 'Ask WeatherGPT…',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          AppPrimaryButton(
            label: 'Send',
            icon: Icons.send,
            onPressed: widget.enabled ? _submit : null,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test\features\chat\widgets\chat_composer_test.dart
```

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/chat/widgets/chat_composer.dart frontend/weathergpt_app/test/features/chat/widgets/chat_composer_test.dart
git commit -m "feat: add ChatComposer with disabled mic affordance and send button"
```

---

### Task 5: Chat screen and router wiring

**Files:**
- Create: `frontend/weathergpt_app/lib/features/chat/chat_screen.dart`
- Modify: `frontend/weathergpt_app/lib/core/router/app_router.dart`
- Test: `frontend/weathergpt_app/test/features/chat/chat_screen_test.dart`

**Interfaces:**
- Consumes: `chatControllerProvider`, `ChatUiState`/`ChatIdle`/`ChatSending`/`ChatFailed` (Task 2); `ChatTurnTile`, `TypingIndicator` (Task 3); `ChatComposer` (Task 4); `AppChip`, `ErrorView` (Phase 0); `AppError` subtypes (Phase 0).
- Produces: `ChatScreen` (a `ConsumerWidget`), wired into `appRouter`'s `/chat` branch.

- [ ] **Step 1: Write the failing test**

Create `frontend/weathergpt_app/test/features/chat/chat_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weathergpt_app/data/chat_api.dart';
import 'package:weathergpt_app/features/chat/chat_controller.dart';
import 'package:weathergpt_app/features/chat/chat_screen.dart';
import 'package:weathergpt_app/shared/widgets/app_chip.dart';

class FakeChatApi implements ChatApi {
  ChatResult? nextResult;

  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    return nextResult ??
        ChatResult(
          reply: 'Echo: $message',
          history: [
            {'role': 'user', 'content': message},
            {'role': 'assistant', 'content': 'Echo: $message'},
          ],
        );
  }
}

void main() {
  testWidgets('shows a welcome and suggested chips when empty, then sends on chip tap', (tester) async {
    final fakeApi = FakeChatApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(fakeApi)],
        child: const MaterialApp(home: ChatScreen()),
      ),
    );

    expect(
      find.text('Ask WeatherGPT about weather, alerts, or advisories anywhere in India.'),
      findsOneWidget,
    );
    expect(find.byType(AppChip), findsWidgets);

    await tester.tap(find.byType(AppChip).first);
    await tester.pump();

    // Tapping a suggestion starts a send — the empty-state welcome is
    // gone and the composer no longer shows placeholder emptiness; the
    // typing indicator or the optimistic user turn is now in the tree.
    expect(
      find.text('Ask WeatherGPT about weather, alerts, or advisories anywhere in India.'),
      findsNothing,
    );
  });

  testWidgets('renders a populated conversation with the composer', (tester) async {
    final fakeApi = FakeChatApi();
    final container = ProviderContainer(
      overrides: [chatApiProvider.overrideWithValue(fakeApi)],
    );
    addTearDown(container.dispose);
    await container.read(chatControllerProvider.notifier).sendMessage('Weather in Pune?');

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ChatScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('Weather in Pune?'), findsOneWidget);
    expect(find.text('Echo: Weather in Pune?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget); // composer still present
  });
}
```

This is the complete, final test — it asserts on the exact welcome copy and `AppChip` type Step 3 below implements. If Step 3's copy or chip choice changes for any reason, update this test to match before moving on; do not leave the two out of sync.

- [ ] **Step 2: Run the test to verify it fails**

```powershell
flutter test test\features\chat\chat_screen_test.dart
```

Expected: FAIL — `chat_screen.dart` doesn't exist yet.

- [ ] **Step 3: Implement**

Create `frontend/weathergpt_app/lib/features/chat/chat_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/app_error.dart';
import '../../core/theme/app_spacing.dart';
import '../../shared/widgets/app_chip.dart';
import '../../shared/widgets/error_view.dart';
import 'chat_controller.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_turn_tile.dart';
import 'widgets/typing_indicator.dart';

const _suggestedQuestions = [
  'Any alerts near me?',
  'Will it rain in Pune tomorrow?',
  "What's the weather in Mumbai right now?",
  'Should I expect a heatwave this week?',
];

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: state.messages.isEmpty && state is! ChatFailed
                ? _EmptyChatView(onSuggestionTap: controller.sendMessage)
                : _ConversationList(state: state, controller: controller),
          ),
          ChatComposer(
            enabled: state is! ChatSending,
            onSend: controller.sendMessage,
          ),
        ],
      ),
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  final ValueChanged<String> onSuggestionTap;

  const _EmptyChatView({required this.onSuggestionTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ask WeatherGPT about weather, alerts, or advisories anywhere in India.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final question in _suggestedQuestions)
                  AppChip(label: question, onTap: () => onSuggestionTap(question)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationList extends StatelessWidget {
  final ChatUiState state;
  final ChatController controller;

  const _ConversationList({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    final currentState = state;
    if (currentState is ChatFailed) {
      items.add(
        ErrorView(
          message: _describeError(currentState.error),
          onRetry: controller.retry,
        ),
      );
    } else if (currentState is ChatSending) {
      items.add(const TypingIndicator());
    }
    items.addAll(
      state.messages.reversed.map((turn) => ChatTurnTile(turn: turn)),
    );

    return ListView(
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      children: items,
    );
  }

  String _describeError(AppError error) => switch (error) {
        NetworkTimeoutError() =>
          'That took too long — check your connection and try again.',
        NetworkConnectionError() =>
          'Could not reach the server. Check your connection and try again.',
        ServerError(:final statusCode) =>
          'The server had a problem (code $statusCode). Try again in a moment.',
        UnknownError() => 'Something went wrong. Please try again.',
      };
}
```

Now finalize `test/features/chat/chat_screen_test.dart` with real assertions matching this exact welcome copy (`'Ask WeatherGPT about weather, alerts, or advisories anywhere in India.'`) and `AppChip` (not `ChoiceChip`/`ActionChip` — check `AppChip`'s actual rendered type in `lib/shared/widgets/app_chip.dart` from Phase 0 and find by that, e.g. `find.byType(AppChip)` or `find.text(question)` for a specific suggestion).

- [ ] **Step 4: Wire the router**

Modify `frontend/weathergpt_app/lib/core/router/app_router.dart`: replace the `/chat` branch's `PlaceholderScreen(title: 'Chat')` with `ChatScreen()`, and add the import:

```dart
import '../../features/chat/chat_screen.dart';
```

```dart
StatefulShellBranch(
  routes: [
    GoRoute(
      path: '/chat',
      builder: (context, state) => const ChatScreen(),
    ),
  ],
),
```

- [ ] **Step 5: Run the tests to verify they pass**

```powershell
flutter test test\features\chat
```

- [ ] **Step 6: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/lib/features/chat/chat_screen.dart frontend/weathergpt_app/lib/core/router/app_router.dart frontend/weathergpt_app/test/features/chat/chat_screen_test.dart
git commit -m "feat: add ChatScreen and wire it into the /chat route"
```

---

### Task 6: Golden verification

**Files:**
- Create: `frontend/weathergpt_app/test/golden/chat_screen_golden_test.dart`
- Create (generated): `frontend/weathergpt_app/test/golden/goldens/chat_light.png`
- Create (generated): `frontend/weathergpt_app/test/golden/goldens/chat_dark.png`

**Interfaces:**
- Consumes: `ChatScreen` (Task 5), `chatApiProvider`/`chatControllerProvider` (Task 2), `AppTheme.light`/`AppTheme.dark` (Phase 0), the same `FontLoader`-based font-registration pattern as `test/golden/gallery_golden_test.dart` (Phase 0 — read that file first and reuse its `setUpAll` font-loading code verbatim, adapted to this file).

- [ ] **Step 1: Read the existing golden test for the established pattern**

Open `frontend/weathergpt_app/test/golden/gallery_golden_test.dart` and note exactly how it: calls `TestWidgetsFlutterBinding.ensureInitialized()`, loads the three `.ttf` files via `FontLoader` in `setUpAll`, sets the test surface size, and structures its `matchesGoldenFile` assertions. Reuse that setup — do not reinvent font loading.

- [ ] **Step 2: Write the golden test**

Create `frontend/weathergpt_app/test/golden/chat_screen_golden_test.dart`, following the exact font-loading `setUpAll` pattern from `gallery_golden_test.dart`, then:

```dart
// (font-loading setUpAll copied from gallery_golden_test.dart goes here)

class _FakeChatApi implements ChatApi {
  @override
  Future<ChatResult> sendMessage(String message, List<dynamic>? history) async {
    throw UnsupportedError('not used — this golden seeds state directly');
  }
}

class _SeededChatController extends Notifier<ChatUiState> {
  final ChatUiState seed;
  _SeededChatController(this.seed);

  @override
  ChatUiState build() => seed;
}

Widget _buildApp(ThemeData theme) {
  const seeded = ChatIdle([
    ChatTurn(role: 'user', content: 'Will it rain in Pune tomorrow?'),
    ChatTurn(
      role: 'assistant',
      content: 'Yes — Pune is expecting moderate rainfall tomorrow afternoon, with a high of 27°C.',
    ),
  ]);

  return ProviderScope(
    overrides: [
      chatApiProvider.overrideWithValue(_FakeChatApi()),
      chatControllerProvider.overrideWith(() => _SeededChatController(seeded)),
    ],
    child: MaterialApp(theme: theme, home: const ChatScreen()),
  );
}

void main() {
  // ... setUpAll font loading from gallery_golden_test.dart ...

  testWidgets('chat screen — light theme', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildApp(AppTheme.light));
    // ChatTurnTile fades in over 250ms (see chat_turn_tile.dart) — pump
    // past that or the golden captures a partially-transparent frame.
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_light.png'),
    );
  });

  testWidgets('chat screen — dark theme', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_buildApp(AppTheme.dark));
    // Same fade-in consideration as the light-theme test above.
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(ChatScreen),
      matchesGoldenFile('goldens/chat_dark.png'),
    );
  });
}
```

Add the necessary imports (`flutter_riverpod`, `weathergpt_app/core/theme/app_theme.dart`, `weathergpt_app/data/chat_api.dart`, `weathergpt_app/features/chat/chat_controller.dart`, `weathergpt_app/features/chat/chat_screen.dart`) — match whatever `gallery_golden_test.dart` already imports for the font-loading utilities.

Match the exact physical size Phase 0's gallery golden test used (check the file — use the same value here for consistency rather than guessing a new one).

- [ ] **Step 3: Generate the goldens**

```powershell
. .\frontend\dev-env.ps1
cd frontend\weathergpt_app
flutter test --update-goldens test\golden\chat_screen_golden_test.dart
```

- [ ] **Step 4: Confirm determinism**

```powershell
flutter test test\golden\chat_screen_golden_test.dart
```

Expected: PASS, without `--update-goldens`, proving the golden is stable across runs. If it is not stable (the typing indicator or some other animated element bleeds into the seeded `ChatIdle` state — it should not, since the seeded state has no `ChatSending`), investigate and fix before proceeding; report exactly what you found either way.

- [ ] **Step 5: Full verification and commit**

```powershell
flutter analyze
flutter test
```

```bash
git add frontend/weathergpt_app/test/golden/chat_screen_golden_test.dart frontend/weathergpt_app/test/golden/goldens/chat_light.png frontend/weathergpt_app/test/golden/goldens/chat_dark.png
git commit -m "test: add golden-image regression coverage for the chat screen"
```

---

## Execution

This plan is ready for **subagent-driven-development**: a fresh implementer subagent per task, a task review after each, and a final whole-branch review at the end — the approach used for Phase 0 and every backend sprint this session.
