import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class SyncClient {
  final void Function(Map<String, dynamic> message) onMessage;
  final void Function()? onDisconnected;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  int _clockOffsetMs = 0;
  final List<int> _offsetSamples = [];
  Timer? _calibrationTimer;

  SyncClient({required this.onMessage, this.onDisconnected});

  int get serverNowMs => DateTime.now().millisecondsSinceEpoch + _clockOffsetMs;

  Future<void> connect(String hostIp, {int port = 8080, required String password}) async {
    _channel = IOWebSocketChannel.connect(Uri.parse('ws://$hostIp:$port/ws'));

    _channel!.sink.add(jsonEncode({
      'type': 'auth',
      'password': password,
    }));

    _sub = _channel!.stream.listen(
          (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        if (msg['type'] == 'pong') {
          _handlePong(msg);
        } else if (msg['type'] == 'auth_fail') {
          onDisconnected?.call();
          dispose();
        } else if (msg['type'] != 'auth_success') {
          onMessage(msg);
        }
      },
      onDone: () => onDisconnected?.call(),
      onError: (_) => onDisconnected?.call(),
    );

    _sendPing();
    _calibrationTimer = Timer.periodic(const Duration(seconds: 4), (_) => _sendPing());
  }

  /// Adds songs to the party queue without interrupting current playback.
  void sendAddToQueue(List<String> filePaths, String guestName) {
    _channel?.sink.add(jsonEncode({
      'type': 'request_tracks_queue',
      'paths': filePaths,
      'guestName': guestName,
    }));
  }

  /// DJ Takeover: enqueues songs and immediately starts playing them.
  void sendTakeover(List<String> filePaths, String guestName) {
    _channel?.sink.add(jsonEncode({
      'type': 'request_takeover',
      'paths': filePaths,
      'guestName': guestName,
    }));
  }

  /// Legacy alias kept for any existing callers.
  void sendSongRequest(List<String> filePaths, String guestName) =>
      sendTakeover(filePaths, guestName);

  void _sendPing() {
    _channel?.sink.add(jsonEncode({
      'type': 'ping',
      'clientTime': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  void _handlePong(Map<String, dynamic> msg) {
    final t2 = DateTime.now().millisecondsSinceEpoch;
    final t0 = msg['clientTime'] as int;
    final serverTime = msg['serverTime'] as int;
    final rtt = t2 - t0;
    final estimatedServerNow = serverTime + rtt ~/ 2;
    final offset = estimatedServerNow - t2;

    _offsetSamples.add(offset);
    if (_offsetSamples.length > 8) _offsetSamples.removeAt(0);

    final sorted = List<int>.from(_offsetSamples)..sort();
    _clockOffsetMs = sorted[sorted.length ~/ 2];
  }

  void dispose() {
    _calibrationTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }
}