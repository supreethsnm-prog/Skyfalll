import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/env/app_env.dart';
import 'alerts_api.dart';

/// Live push of newly-ingested alerts from `GET /ws/alerts`.
///
/// The backend broadcasts `{"type": "new_alerts", "alerts": [...]}` each
/// time ingestion finds warnings it had not seen before (see
/// `app/realtime/manager.py`). Without this the app only learns about a
/// new warning when someone pulls to refresh — which, for a
/// disaster-advisory product, is the wrong way round.
abstract class AlertsSocket {
  /// Batches of newly-published alerts, unfiltered by location. Callers
  /// decide what is near enough to matter.
  Stream<List<AlertSummary>> get newAlerts;

  void dispose();
}

class WebSocketAlertsSocket implements AlertsSocket {
  WebSocketAlertsSocket({String? baseUrl})
      : _url = _toWebSocketUrl(baseUrl ?? AppEnv.apiBaseUrl) {
    _connect();
  }

  final String _url;
  final _controller = StreamController<List<AlertSummary>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  /// Backoff between reconnect attempts. A dropped socket is normal — the
  /// dev backend restarts constantly and phones lose signal — so this
  /// reconnects quietly rather than surfacing an error the user cannot
  /// act on. Capped so a long outage does not spin.
  static const _initialBackoff = Duration(seconds: 2);
  static const _maxBackoff = Duration(seconds: 30);
  Duration _backoff = _initialBackoff;

  /// `http://host:8000` -> `ws://host:8000/ws/alerts`, and https -> wss.
  static String _toWebSocketUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return uri.replace(scheme: scheme, path: '/ws/alerts').toString();
  }

  void _connect() {
    if (_disposed) return;

    try {
      final channel = WebSocketChannel.connect(Uri.parse(_url));
      _channel = channel;
      _subscription = channel.stream.listen(
        _onMessage,
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    // A connection that delivers anything is a working connection, so the
    // backoff resets here rather than on connect — `connect` succeeds
    // optimistically before the handshake completes.
    _backoff = _initialBackoff;

    try {
      final decoded = jsonDecode(raw as String);
      if (decoded is! Map || decoded['type'] != 'new_alerts') return;

      final alerts = (decoded['alerts'] as List<dynamic>?)
              ?.map((e) => AlertSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <AlertSummary>[];

      if (alerts.isNotEmpty) _controller.add(alerts);
    } catch (_) {
      // A malformed frame must never take down the socket: the next
      // broadcast may be the one that matters.
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;

    _subscription?.cancel();
    _subscription = null;
    _channel = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(_backoff, _connect);

    final next = _backoff * 2;
    _backoff = next > _maxBackoff ? _maxBackoff : next;
  }

  @override
  Stream<List<AlertSummary>> get newAlerts => _controller.stream;

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
