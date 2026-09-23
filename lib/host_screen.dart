import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'app_theme.dart';
import 'playback_sync.dart';
import 'queue_screen.dart';
import 'sync_server.dart';
import 'ui_components.dart';

final SyncServer _globalServer = SyncServer();
final AudioPlayer _globalPlayer = AudioPlayer();
bool _globalServerRunning = false;
String _hostFruitName = '';

bool get isHostPartyRunning => _globalServerRunning;

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  Timer? _listenerCountTimer;
  final _partyNameController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_hostFruitName.isEmpty) {
      _hostFruitName = SyncServer.getRandomFruitName();
    }
    if (_globalServerRunning) {
      _startTimer();
    }
    _globalPlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && _globalServerRunning) {
        _skipNext();
      }
    });
  }

  @override
  void dispose() {
    _listenerCountTimer?.cancel();
    _partyNameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _listenerCountTimer?.cancel();
    _listenerCountTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  void _randomizeDjName() {
    setState(() {
      _hostFruitName = SyncServer.getRandomFruitName();
    });
  }

  Future<void> _pickAndStart() async {
    final partyName = _partyNameController.text.trim();
    final password = _passwordController.text.trim();

    if (partyName.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both Party Name and Password')),
      );
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final files = result.files.where((f) => f.path != null).map((f) => File(f.path!)).toList();
    if (files.isEmpty) return;

    final firstUrl = await _globalServer.start(
      audioFiles: files,
      name: partyName,
      pass: password,
      hostName: _hostFruitName,
    );

    _globalServer.loadCurrentTrack();
    await applySyncMessage(
      _globalPlayer,
      {'type': 'load', 'audioUrl': firstUrl, 'title': _globalServer.currentTrack?.title},
      () => DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      _globalServerRunning = true;
    });

    _startTimer();
  }

  Future<void> _endParty() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Listening Party?'),
        content: const Text('This will disconnect all connected listeners and stop playback.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('End Party'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    _listenerCountTimer?.cancel();
    await _globalServer.stop();
    await _globalPlayer.stop();

    _globalServerRunning = false;
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _playForEveryone() {
    final pos = _globalPlayer.position;
    _globalServer.playFrom(pos);
    applySyncMessage(
      _globalPlayer,
      {
        'type': 'play',
        'serverStartTime': DateTime.now().millisecondsSinceEpoch + 700,
        'positionMs': pos.inMilliseconds,
      },
      () => DateTime.now().millisecondsSinceEpoch,
    );
  }

  void _pauseForEveryone() {
    final pos = _globalPlayer.position;
    _globalServer.pauseAt(pos);
    _globalPlayer.pause();
  }

  Future<void> _skipNext() async {
    _globalServer.skipNext();
    final track = _globalServer.currentTrack;
    if (track != null) {
      await applySyncMessage(
        _globalPlayer,
        {'type': 'load', 'audioUrl': track.url, 'title': track.title},
        () => DateTime.now().millisecondsSinceEpoch,
      );
      _playForEveryone();
    }
    setState(() {});
  }

  Future<void> _skipPrevious() async {
    _globalServer.skipPrevious();
    final track = _globalServer.currentTrack;
    if (track != null) {
      await applySyncMessage(
        _globalPlayer,
        {'type': 'load', 'audioUrl': track.url, 'title': track.title},
        () => DateTime.now().millisecondsSinceEpoch,
      );
      _playForEveryone();
    }
    setState(() {});
  }

  void _shuffle() {
    setState(() {
      _globalServer.shufflePlaylist();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playlist shuffled!')),
    );
  }

  /// Opens the dedicated Queue Screen where the host can add/remove/reorder tracks.
  Future<void> _openQueueScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QueueScreen(
          server: _globalServer,
          isHost: true,
          hostName: _hostFruitName,
          onQueueChanged: () {
            if (mounted) setState(() {});
          },
          onTrackSelected: (index) async {
            // Load and play the selected track for everyone
            _globalServer.loadCurrentTrack();
            final track = _globalServer.currentTrack;
            if (track == null) return;
            await applySyncMessage(
              _globalPlayer,
              {'type': 'load', 'audioUrl': track.url, 'title': track.title},
              () => DateTime.now().millisecondsSinceEpoch,
            );
            _playForEveryone();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  void _showListenersList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: TogetherTheme.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_rounded, color: TogetherTheme.primaryPurpleLight),
                  const SizedBox(width: 12),
                  Text(
                    'Connected Listeners (${_globalServer.connectedListeners})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: TogetherTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_globalServer.connectedListeners == 0)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Waiting for friends to connect over Wi-Fi...',
                      style: TextStyle(color: TogetherTheme.textSecondary),
                    ),
                  ),
                )
              else
                ListTile(
                  leading: const DjAvatar(name: 'Host', radius: 18),
                  title: Text('DJ Host ($_hostFruitName)'),
                  subtitle: const Text('Host Device', style: TextStyle(color: TogetherTheme.liveGreen)),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = _globalServer.currentTrack;

    return Scaffold(
      appBar: AppBar(
        title: Text(_globalServerRunning ? 'Host Console' : 'Party Setup'),
        actions: [
          if (_globalServerRunning) ...[
            IconButton(
              icon: const Icon(Icons.people_alt_rounded, color: TogetherTheme.primaryPurpleLight),
              onPressed: _showListenersList,
              tooltip: 'Listeners',
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: TextButton.icon(
                onPressed: _endParty,
                icon: const Icon(Icons.power_settings_new_rounded, size: 18, color: Colors.redAccent),
                label: const Text('End', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: !_globalServerRunning
              ? _buildSetupView()
              : _buildActivePartyView(currentTrack),
        ),
      ),
    );
  }

  Widget _buildSetupView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          // DJ Profile Card
          GlassContainer(
            child: Row(
              children: [
                DjAvatar(name: _hostFruitName, radius: 28),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR DJ IDENTITY',
                        style: TextStyle(
                          color: TogetherTheme.primaryPurpleLight,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'DJ $_hostFruitName',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: TogetherTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _randomizeDjName,
                  icon: const Icon(Icons.casino_rounded, color: TogetherTheme.accentPink),
                  tooltip: 'Change DJ Name',
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Party Settings Card
          GlassContainer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PARTY DETAILS',
                  style: TextStyle(
                    color: TogetherTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _partyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Party Name',
                    hintText: 'e.g. Chill Beats Lounge',
                    prefixIcon: Icon(Icons.celebration_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Party Password', hintText: 'Enter access password', prefixIcon: Icon(Icons.lock_rounded)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          GradientButton(
            label: 'Select Songs & Launch Party',
            icon: Icons.library_music_rounded,
            onPressed: _pickAndStart,
          ),
        ],
      ),
    );
  }

  Widget _buildActivePartyView(TrackItem? currentTrack) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top Header Info
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _globalServer.partyName ?? 'Together Party',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: TogetherTheme.textPrimary,
                  ),
                ),
                Row(
                  children: [
                    const DjAvatar(name: 'Host', radius: 10),
                    const SizedBox(width: 6),
                    Text(
                      'DJ: ${_globalServer.currentPlayingUser}',
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
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: TogetherTheme.liveGreen,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_globalServer.connectedListeners} Listeners',
                    style: const TextStyle(
                      color: TogetherTheme.liveGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Vinyl Artwork & Now Playing Hero
        StreamBuilder<PlayerState>(
          stream: _globalPlayer.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return Center(
              child: Column(
                children: [
                  VinylDisc(
                    isPlaying: playing,
                    title: currentTrack?.title ?? 'No Track',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    currentTrack?.title ?? 'No song playing',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: TogetherTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (currentTrack != null)
                    Text(
                      'Requested by ${currentTrack.ownerName}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: TogetherTheme.textSecondary,
                      ),
                    ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Progress Bar
        StreamBuilder<Duration>(
          stream: _globalPlayer.positionStream,
          builder: (context, snapshot) {
            final pos = snapshot.data ?? Duration.zero;
            final total = _globalPlayer.duration ?? Duration.zero;
            return Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context),
                  child: Slider(
                    value: pos.inMilliseconds.toDouble().clamp(0, total.inMilliseconds.toDouble()),
                    max: total.inMilliseconds.toDouble() == 0 ? 1 : total.inMilliseconds.toDouble(),
                    onChanged: (v) {
                      _globalPlayer.seek(Duration(milliseconds: v.toInt()));
                    },
                    onChangeEnd: (v) {
                      final newPos = Duration(milliseconds: v.toInt());
                      if (_globalPlayer.playing) {
                        _globalServer.playFrom(newPos);
                      } else {
                        _globalServer.pauseAt(newPos);
                      }
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_fmt(pos), style: const TextStyle(color: TogetherTheme.textMuted, fontSize: 12)),
                      Text(_fmt(total), style: const TextStyle(color: TogetherTheme.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        const SizedBox(height: 12),

        // Playback Control Bar
        StreamBuilder<PlayerState>(
          stream: _globalPlayer.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shuffle_rounded, color: TogetherTheme.textSecondary),
                    onPressed: _shuffle,
                    tooltip: 'Shuffle',
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 32, color: TogetherTheme.textPrimary),
                    onPressed: _skipPrevious,
                  ),
                  GestureDetector(
                    onTap: playing ? _pauseForEveryone : _playForEveryone,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: TogetherTheme.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: TogetherTheme.primaryPurple,
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Icon(
                        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 32, color: TogetherTheme.textPrimary),
                    onPressed: _skipNext,
                  ),
                  // Queue button — navigates to full QueueScreen
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded, color: TogetherTheme.primaryPurpleLight),
                        onPressed: _openQueueScreen,
                        tooltip: 'Queue',
                      ),
                      if (_globalServer.playlist.length > 1)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: TogetherTheme.accentPink,
                            ),
                            child: Center(
                              child: Text(
                                '${_globalServer.playlist.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 16),

        // Up Next / Queue Preview row — taps open full QueueScreen
        GestureDetector(
          onTap: _openQueueScreen,
          child: GlassContainer(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.queue_music_rounded,
                    size: 18, color: TogetherTheme.primaryPurpleLight),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UP NEXT',
                        style: TextStyle(
                          color: TogetherTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Builder(builder: (_) {
                        final nextIndex = _globalServer.currentIndex + 1;
                        final hasNext = nextIndex < _globalServer.playlist.length;
                        return Text(
                          hasNext
                              ? _globalServer.playlist[nextIndex].title
                              : 'End of queue',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasNext
                                ? TogetherTheme.textSecondary
                                : TogetherTheme.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${_globalServer.playlist.length} tracks',
                      style: const TextStyle(
                        color: TogetherTheme.textMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right_rounded,
                        color: TogetherTheme.textMuted, size: 20),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
