import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class TrackItem {
  final String title;
  final File file;
  final String url;
  final String ownerName;

  /// Absolute file path — used for deduplication.
  String get filePath => file.path;

  TrackItem({required this.title, required this.file, required this.url, required this.ownerName});
}

class SyncServer {
  HttpServer? _httpServer;
  final List<WebSocket> _clients = [];

  String? partyName;
  String? password;
  String? hostUserName;

  final List<TrackItem> playlist = [];
  int currentIndex = 0;
  String currentPlayingUser = '';

  // Current playback state
  bool _isPlaying = false;
  int _positionMsAtLastUpdate = 0;
  int _serverTimeAtLastUpdate = 0;

  RawDatagramSocket? _broadcastSocket;
  Timer? _broadcastTimer;

  int get connectedListeners => _clients.length;
  TrackItem? get currentTrack => playlist.isNotEmpty && currentIndex < playlist.length ? playlist[currentIndex] : null;

  /// Set of titles (filenames) already in the queue — primary dedup key.
  /// Title is derived from the filename and is stable even when the full path
  /// differs between file-picker sessions (content URIs, cache copies, etc.).
  Set<String> get existingTitles => playlist.map((t) => t.title).toSet();

  /// Returns true if a file is already in the queue, checking by TITLE first
  /// (reliable on mobile) and by path as a secondary check.
  bool _isDuplicate(String path, Set<String> titles) {
    final title = path.split(Platform.pathSeparator).last;
    return titles.contains(title);
  }

  static final List<String> _fruits = [
    'Apple', 'Banana', 'Mango', 'Strawberry', 'Pineapple',
    'Orange', 'Peach', 'Cherry', 'Blueberry', 'Kiwi', 'Papaya', 'Lemon'
  ];

  static String getRandomFruitName() {
    return _fruits[Random().nextInt(_fruits.length)];
  }

  Future<String> start({
    required List<File> audioFiles,
    required String name,
    required String pass,
    required String hostName,
    int port = 8080,
  }) async {
    partyName = name;
    password = pass;
    hostUserName = hostName;
    currentPlayingUser = hostName;

    playlist.clear();
    _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _httpServer!.listen(_handleRequest);

    final ip = await _localIp();

    for (int i = 0; i < audioFiles.length; i++) {
      final file = audioFiles[i];
      final title = file.path.split(Platform.pathSeparator).last;
      playlist.add(TrackItem(title: title, file: file, url: 'http://$ip:$port/audio_$i', ownerName: hostName));
    }

    currentIndex = 0;
    await _startBroadcasting(port);

    return currentTrack?.url ?? '';
  }

  Future<void> _startBroadcasting(int port) async {
    _broadcastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _broadcastSocket?.broadcastEnabled = true;

    final ip = await _localIp();
    _broadcastTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_broadcastSocket == null) return;
      final message = jsonEncode({
        'partyName': partyName,
        'ip': ip,
        'port': port,
        'currentDj': currentPlayingUser,
      });
      _broadcastSocket?.send(
        utf8.encode(message),
        InternetAddress('255.255.255.255'),
        45454,
      );
    });
  }

  Future<void> stop() async {
    _broadcastTimer?.cancel();
    _broadcastSocket?.close();
    _broadcastSocket = null;

    for (final ws in _clients) {
      await ws.close();
    }
    _clients.clear();
    await _httpServer?.close(force: true);
  }

  void loadCurrentTrack() {
    final track = currentTrack;
    if (track == null) return;
    currentPlayingUser = track.ownerName;
    _broadcast({
      'type': 'load',
      'audioUrl': track.url,
      'title': track.title,
      'dj': currentPlayingUser,
    });
  }

  void playFrom(Duration position, {int leadMs = 700}) {
    final startAt = DateTime.now().millisecondsSinceEpoch + leadMs;
    _isPlaying = true;
    _positionMsAtLastUpdate = position.inMilliseconds;
    _serverTimeAtLastUpdate = startAt;
    _broadcast({
      'type': 'play',
      'serverStartTime': startAt,
      'positionMs': position.inMilliseconds,
      'dj': currentPlayingUser,
    });
  }

  void pauseAt(Duration position) {
    _isPlaying = false;
    _positionMsAtLastUpdate = position.inMilliseconds;
    _serverTimeAtLastUpdate = DateTime.now().millisecondsSinceEpoch;
    _broadcast({'type': 'pause', 'positionMs': position.inMilliseconds});
  }

  void skipNext() {
    if (playlist.isEmpty) return;
    currentIndex = (currentIndex + 1) % playlist.length;
    loadCurrentTrack();
    playFrom(Duration.zero);
  }

  void skipPrevious() {
    if (playlist.isEmpty) return;
    currentIndex = (currentIndex - 1 + playlist.length) % playlist.length;
    loadCurrentTrack();
    playFrom(Duration.zero);
  }

  void shufflePlaylist() {
    if (playlist.length > 1) {
      final current = currentTrack;
      playlist.shuffle();
      if (current != null) {
        currentIndex = playlist.indexOf(current);
      }
    }
  }

  /// Appends tracks to the end of the queue WITHOUT interrupting current playback.
  /// Skips files already present in the queue (deduplication by file path).
  /// Returns ({int added, int skipped}).
  ({int added, int skipped}) addTracksToQueue(List<File> files, String ownerName) {
    final ip = _httpServer?.address.address ?? '127.0.0.1';
    final port = _httpServer?.port ?? 8080;
    final titles = existingTitles;
    int added = 0, skipped = 0;

    for (final file in files) {
      if (_isDuplicate(file.path, titles)) { skipped++; continue; }
      final title = file.path.split(Platform.pathSeparator).last;
      final newIndex = playlist.length;
      playlist.add(TrackItem(title: title, file: file, url: 'http://$ip:$port/audio_$newIndex', ownerName: ownerName));
      titles.add(title);
      added++;
    }
    if (added > 0) _broadcastQueueUpdate();
    return (added: added, skipped: skipped);
  }

  /// Adds guest tracks to the end of the queue WITHOUT interrupting playback.
  /// Skips files already present (deduplication by title/filename).
  ({int added, int skipped}) addGuestTracks(List<String> filePaths, String guestName) {
    final ip = _httpServer?.address.address ?? '127.0.0.1';
    final port = _httpServer?.port ?? 8080;
    final titles = existingTitles;
    int added = 0, skipped = 0;

    for (var path in filePaths) {
      if (_isDuplicate(path, titles)) { skipped++; continue; }
      final file = File(path);
      final title = file.path.split(Platform.pathSeparator).last;
      final newIndex = playlist.length;
      playlist.add(TrackItem(title: title, file: file, url: 'http://$ip:$port/audio_$newIndex', ownerName: guestName));
      titles.add(title);
      added++;
    }
    if (added > 0) _broadcastQueueUpdate();
    return (added: added, skipped: skipped);
  }

  /// Guest DJ takeover: enqueue tracks (skip dupes by title) and immediately jump + play the first new one.
  ({int added, int skipped}) guestTakeover(List<String> filePaths, String guestName) {
    final ip = _httpServer?.address.address ?? '127.0.0.1';
    final port = _httpServer?.port ?? 8080;
    final titles = existingTitles;
    final int firstNewIndex = playlist.length;
    int added = 0, skipped = 0;

    for (var path in filePaths) {
      if (_isDuplicate(path, titles)) { skipped++; continue; }
      final file = File(path);
      final title = file.path.split(Platform.pathSeparator).last;
      final newIndex = playlist.length;
      playlist.add(TrackItem(title: title, file: file, url: 'http://$ip:$port/audio_$newIndex', ownerName: guestName));
      titles.add(title);
      added++;
    }
    if (added > 0) {
      currentIndex = firstNewIndex;
      loadCurrentTrack();
      playFrom(Duration.zero);
      _broadcastQueueUpdate();
    }
    return (added: added, skipped: skipped);
  }


  /// Removes a track at [index] from the playlist (host only).
  /// Adjusts currentIndex if needed.
  void removeTrackAt(int index) {
    if (index < 0 || index >= playlist.length) return;
    // Don't allow removing the currently playing track
    if (index == currentIndex) return;
    playlist.removeAt(index);
    if (index < currentIndex) currentIndex--;
    _broadcastQueueUpdate();
  }

  /// Moves a track from [oldIndex] to [newIndex] (host drag-to-reorder).
  void moveTrack(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    if (oldIndex < 0 || oldIndex >= playlist.length) return;
    if (newIndex < 0 || newIndex >= playlist.length) return;
    final item = playlist.removeAt(oldIndex);
    playlist.insert(newIndex, item);
    // Adjust currentIndex to follow the currently playing track
    if (oldIndex == currentIndex) {
      currentIndex = newIndex;
    } else if (oldIndex < currentIndex && newIndex >= currentIndex) {
      currentIndex--;
    } else if (oldIndex > currentIndex && newIndex <= currentIndex) {
      currentIndex++;
    }
    _broadcastQueueUpdate();
  }

  /// Broadcasts the full queue to all connected clients.
  void _broadcastQueueUpdate() {
    _broadcast({
      'type': 'queue_update',
      'currentIndex': currentIndex,
      'tracks': playlist
          .map((t) => {'title': t.title, 'ownerName': t.ownerName})
          .toList(),
    });
  }

  void _broadcast(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    for (final ws in _clients) {
      ws.add(data);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/ws') {
      final ws = await WebSocketTransformer.upgrade(request);

      ws.first.timeout(const Duration(seconds: 5), onTimeout: () {
        ws.close();
        return '';
      }).then((data) {
        try {
          final authMsg = jsonDecode(data as String) as Map<String, dynamic>;
          if (authMsg['type'] == 'auth' && authMsg['password'] == password) {
            ws.add(jsonEncode({'type': 'auth_success'}));
            _clients.add(ws);
            _sendCurrentStateTo(ws);

            ws.listen(
                  (d) => _handleClientMessage(ws, d),
              onDone: () => _clients.remove(ws),
              onError: (_) => _clients.remove(ws),
            );
          } else {
            ws.add(jsonEncode({'type': 'auth_fail', 'reason': 'Incorrect password'}));
            ws.close();
          }
        } catch (_) {
          ws.close();
        }
      });
    } else if (request.uri.path.startsWith('/audio_')) {
      final indexStr = request.uri.path.replaceFirst('/audio_', '');
      final index = int.tryParse(indexStr);
      if (index != null && index >= 0 && index < playlist.length) {
        await _serveAudioFile(request, playlist[index].file);
        return;
      }
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  void _sendCurrentStateTo(WebSocket ws) {
    final track = currentTrack;
    if (track == null) return;
    ws.add(jsonEncode({'type': 'load', 'audioUrl': track.url, 'title': track.title, 'dj': currentPlayingUser}));
    // Send full queue state
    ws.add(jsonEncode({
      'type': 'queue_update',
      'currentIndex': currentIndex,
      'tracks': playlist
          .map((t) => {'title': t.title, 'ownerName': t.ownerName})
          .toList(),
    }));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_isPlaying) {
      final elapsed = now - _serverTimeAtLastUpdate;
      ws.add(jsonEncode({
        'type': 'play',
        'serverStartTime': now,
        'positionMs': _positionMsAtLastUpdate + elapsed,
      }));
    } else {
      ws.add(jsonEncode({'type': 'pause', 'positionMs': _positionMsAtLastUpdate}));
    }
  }

  void _handleClientMessage(WebSocket ws, dynamic data) {
    try {
      final msg = jsonDecode(data as String) as Map<String, dynamic>;
      if (msg['type'] == 'ping') {
        ws.add(jsonEncode({
          'type': 'pong',
          'clientTime': msg['clientTime'],
          'serverTime': DateTime.now().millisecondsSinceEpoch,
        }));
      } else if (msg['type'] == 'request_tracks_queue') {
        // Listener wants to add tracks to queue without interrupting playback
        final paths = (msg['paths'] as List).cast<String>();
        final guestName = msg['guestName'] as String;
        addGuestTracks(paths, guestName);
      } else if (msg['type'] == 'request_takeover') {
        // Listener wants to DJ takeover (immediate play)
        final paths = (msg['paths'] as List).cast<String>();
        final guestName = msg['guestName'] as String;
        guestTakeover(paths, guestName);
      }
    } catch (_) {}
  }

  Future<void> _serveAudioFile(HttpRequest request, File file) async {
    if (!await file.exists()) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }
    final length = await file.length();
    request.response.headers.set('Content-Type', 'audio/mpeg');
    request.response.headers.set('Content-Length', '$length');
    await request.response.addStream(file.openRead());
    await request.response.close();
  }

  Future<String> _localIp() async {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return '127.0.0.1';
  }
}