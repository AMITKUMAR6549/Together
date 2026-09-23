import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'app_theme.dart';
import 'playback_sync.dart';
import 'queue_screen.dart';
import 'sync_client.dart';
import 'sync_server.dart';
import 'ui_components.dart';

class PartyInfo {
  final String partyName;
  final String ip;
  final int port;
  String currentDj;

  PartyInfo({
    required this.partyName,
    required this.ip,
    required this.port,
    required this.currentDj,
  });
}

class PartyDiscovery {
  RawDatagramSocket? _socket;
  StreamSubscription? _subscription;
  final _partiesController = StreamController<List<PartyInfo>>.broadcast();
  final Map<String, PartyInfo> _discoveredParties = {};

  Stream<List<PartyInfo>> get partiesStream => _partiesController.stream;

  Future<void> startListening() async {
    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 45454);
    _socket?.broadcastEnabled = true;

    _subscription = _socket?.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket?.receive();
        if (dg != null) {
          try {
            final data = utf8.decode(dg.data);
            final json = jsonDecode(data) as Map<String, dynamic>;
            final name = json['partyName'] as String;
            final ip = json['ip'] as String;
            final port = json['port'] as int;
            final dj = json['currentDj'] as String? ?? 'Host';

            _discoveredParties['$ip:$port'] = PartyInfo(
              partyName: name,
              ip: ip,
              port: port,
              currentDj: dj,
            );
            _partiesController.add(_discoveredParties.values.toList());
          } catch (_) {}
        }
      }
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _socket?.close();
    _socket = null;
    _discoveredParties.clear();
  }
}

class ListenerScreen extends StatefulWidget {
  const ListenerScreen({super.key});

  @override
  State<ListenerScreen> createState() => _ListenerScreenState();
}

class _ListenerScreenState extends State<ListenerScreen> {
  final PartyDiscovery _discovery = PartyDiscovery();
  final _player = AudioPlayer();
  SyncClient? _client;
  bool _connected = false;
  String _activePartyName = '';
  late String _listenerFruitName;
  String _currentDj = '';
  String _currentSongTitle = 'Synced Audio Stream';

  // Live queue state received from the host
  List<Map<String, dynamic>> _queueTracks = [];
  int _queueCurrentIndex = 0;

  @override
  void initState() {
    super.initState();
    _listenerFruitName = SyncServer.getRandomFruitName();
    _discovery.startListening();
  }

  @override
  void dispose() {
    _discovery.stopListening();
    _client?.dispose();
    _player.dispose();
    super.dispose();
  }

  Future<void> _connectToParty(PartyInfo party) async {
    final passwordController = TextEditingController();

    final password = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: TogetherTheme.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: TogetherTheme.glassBorder),
        ),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: TogetherTheme.primaryPurpleLight),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Join "${party.partyName}"',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Party Password',
            hintText: 'Enter access password',
            prefixIcon: Icon(Icons.key_rounded),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: TogetherTheme.textMuted)),
          ),
          GradientButton(
            label: 'Connect',
            onPressed: () => Navigator.pop(context, passwordController.text.trim()),
          ),
        ],
      ),
    );

    if (password == null || password.isEmpty) return;

    final client = SyncClient(
      onMessage: (msg) {
        if (msg['dj'] != null) {
          setState(() => _currentDj = msg['dj']);
        }
        if (msg['title'] != null) {
          setState(() => _currentSongTitle = msg['title']);
        }
        if (msg['type'] == 'queue_update') {
          setState(() {
            _queueTracks = (msg['tracks'] as List).cast<Map<String, dynamic>>();
            _queueCurrentIndex = (msg['currentIndex'] as num).toInt();
          });
          return; // Don't pass queue_update to audio sync
        }
        applySyncMessage(_player, msg, () => _client!.serverNowMs);
      },
      onDisconnected: () => setState(() {
        _connected = false;
      }),
    );

    try {
      await client.connect(party.ip, port: party.port, password: password);
      _client = client;
      setState(() {
        _connected = true;
        _activePartyName = party.partyName;
        _currentDj = party.currentDj;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect. Check password or connection.')),
        );
      }
    }
  }

  /// Add songs to the party queue without interrupting current playback.
  Future<void> _addToQueue() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
    if (paths.isEmpty) return;

    _client?.sendAddToQueue(paths, _listenerFruitName);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${paths.length} track(s) added to the queue!'),
        backgroundColor: TogetherTheme.primaryPurple,
      ),
    );
  }

  /// DJ Takeover: immediately plays your songs for everyone.
  Future<void> _djTakeover() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;

    final paths = result.files.where((f) => f.path != null).map((f) => f.path!).toList();
    if (paths.isEmpty) return;

    _client?.sendTakeover(paths, _listenerFruitName);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('DJ Takeover active! Playing as $_listenerFruitName 🎧'),
        backgroundColor: TogetherTheme.accentPink,
      ),
    );
  }

  /// Opens the full QueueScreen in read-only mode for listeners.
  void _openQueueScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QueueScreen(
          readOnlyTracks: List<Map<String, dynamic>>.from(_queueTracks),
          readOnlyCurrentIndex: _queueCurrentIndex,
        ),
      ),
    );
  }

  Future<void> _leaveParty() async {
    _client?.dispose();
    _player.stop();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_connected ? 'Listening Room' : 'Join Party'),
        actions: [
          if (_connected)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _leaveParty,
                icon: const Icon(Icons.logout_rounded, size: 18, color: Colors.redAccent),
                label: const Text('Leave', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: _connected ? _buildConnectedView() : _buildDiscoveryView(),
        ),
      ),
    );
  }

  Widget _buildDiscoveryView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Listener Identity Banner
        GlassContainer(
          child: Row(
            children: [
              DjAvatar(name: _listenerFruitName, radius: 24),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'YOUR LISTENER NAME',
                      style: TextStyle(
                        color: TogetherTheme.accentCyan,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _listenerFruitName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: TogetherTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.wifi_find_rounded, color: TogetherTheme.accentCyan),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Radar Scanning Visualizer
        Center(
          child: Column(
            children: const [
              RadarPulse(size: 100),
              SizedBox(height: 12),
              Text(
                'Searching nearby Wi-Fi network...',
                style: TextStyle(color: TogetherTheme.textSecondary, fontSize: 13),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'AVAILABLE PARTIES',
          style: TextStyle(
            color: TogetherTheme.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),

        const SizedBox(height: 12),

        // Parties List
        Expanded(
          child: StreamBuilder<List<PartyInfo>>(
            stream: _discovery.partiesStream,
            initialData: const [],
            builder: (context, snapshot) {
              final parties = snapshot.data ?? [];
              if (parties.isEmpty) {
                return GlassContainer(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.wifi_off_rounded, size: 40, color: TogetherTheme.textMuted),
                        SizedBox(height: 12),
                        Text(
                          'No active parties found yet.',
                          style: TextStyle(fontWeight: FontWeight.bold, color: TogetherTheme.textPrimary),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Make sure the host is connected to the same Wi-Fi and has started a party.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: TogetherTheme.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                itemCount: parties.length,
                itemBuilder: (context, index) {
                  final party = parties[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: GlassContainer(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: TogetherTheme.cyanGradient,
                            ),
                            child: const Icon(Icons.radio_rounded, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  party.partyName,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: TogetherTheme.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    DjAvatar(name: party.currentDj, radius: 10),
                                    const SizedBox(width: 6),
                                    Text(
                                      'DJ: ${party.currentDj}',
                                      style: const TextStyle(
                                        color: TogetherTheme.accentCyan,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          GradientButton(
                            label: 'Join',
                            gradient: TogetherTheme.cyanGradient,
                            onPressed: () => _connectToParty(party),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Party Title Card
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _activePartyName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: TogetherTheme.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    const DjAvatar(name: 'DJ', radius: 10),
                    const SizedBox(width: 6),
                    Text(
                      'Current DJ: $_currentDj',
                      style: const TextStyle(
                        color: TogetherTheme.primaryPurpleLight,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: TogetherTheme.liveGreen.withOpacity(0.15),
                border: Border.all(color: TogetherTheme.liveGreen.withOpacity(0.5)),
              ),
              child: Row(
                children: const [
                  EqualizerVisualizer(isPlaying: true, barColor: TogetherTheme.liveGreen, height: 12),
                  SizedBox(width: 6),
                  Text(
                    'SYNCED',
                    style: TextStyle(
                      color: TogetherTheme.liveGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const Spacer(),

        // Vinyl Artwork & Now Playing Hero
        StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return Center(
              child: Column(
                children: [
                  VinylDisc(
                    isPlaying: playing,
                    title: _currentSongTitle,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _currentSongTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: TogetherTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: TogetherTheme.cardSurfaceLight,
                      border: Border.all(color: TogetherTheme.glassBorder),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.headphones_rounded, size: 16, color: TogetherTheme.liveGreen),
                        SizedBox(width: 8),
                        Text(
                          'Synced Audio Connected',
                          style: TextStyle(color: TogetherTheme.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        const Spacer(),

        // View Queue Button
        OutlinedButton.icon(
          onPressed: _openQueueScreen,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: TogetherTheme.primaryPurpleLight),
            foregroundColor: TogetherTheme.primaryPurpleLight,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.queue_music_rounded),
          label: Text(
            _queueTracks.isEmpty
                ? 'View Queue'
                : 'View Queue  •  ${_queueTracks.length} tracks',
          ),
        ),

        const SizedBox(height: 12),

        // Add to Queue + DJ Takeover Card
        GlassContainer(
          borderColor: TogetherTheme.accentPink.withOpacity(0.4),
          gradient: const LinearGradient(
            colors: [Color(0xFF2C1020), Color(0xFF1A0A18)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: TogetherTheme.accentPink, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ADD YOUR MUSIC',
                          style: TextStyle(
                            color: TogetherTheme.accentPink,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          'Join the party as DJ $_listenerFruitName',
                          style: const TextStyle(
                            color: TogetherTheme.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Add to Queue button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _addToQueue,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: TogetherTheme.primaryPurpleLight),
                        foregroundColor: TogetherTheme.primaryPurpleLight,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Add to Queue', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // DJ Takeover button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _djTakeover,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TogetherTheme.accentPink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text('DJ Takeover', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        OutlinedButton.icon(
          onPressed: _leaveParty,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent),
            foregroundColor: Colors.redAccent,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Leave Party'),
        ),

        const SizedBox(height: 10),
      ],
    );
  }
}
