import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'sync_server.dart';
import 'ui_components.dart';

/// Full-screen queue manager.
///
/// [server]    — the live [SyncServer] instance (host only; null for listener view).
/// [isHost]    — if true, shows add / remove / reorder controls.
/// [hostName]  — used as ownerName when the host adds tracks.
/// [readOnlyTracks] — pre-built list of {title, ownerName} maps for listener view.
/// [readOnlyCurrentIndex] — current track index for listener view.
/// [onQueueChanged] — called after any mutation so the caller can setState.
/// [onTrackSelected] — called when the host taps a track; receives the track index.
///   The caller is responsible for loading and playing the selected track.
class QueueScreen extends StatefulWidget {
  final SyncServer? server;
  final bool isHost;
  final String hostName;
  final List<Map<String, dynamic>> readOnlyTracks;
  final int readOnlyCurrentIndex;
  final VoidCallback? onQueueChanged;
  final void Function(int index)? onTrackSelected;

  const QueueScreen({
    super.key,
    this.server,
    this.isHost = false,
    this.hostName = '',
    this.readOnlyTracks = const [],
    this.readOnlyCurrentIndex = 0,
    this.onQueueChanged,
    this.onTrackSelected,
  });

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  bool _isAdding = false;

  SyncServer? get _server => widget.server;

  List<TrackItem> get _playlist => _server?.playlist ?? [];
  int get _currentIndex => _server?.currentIndex ?? 0;

  // ─── Host: Add more songs ───────────────────────────────────────────────────

  Future<void> _addSongs() async {
    setState(() => _isAdding = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final files = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      if (files.isEmpty) return;

      final (:added, :skipped) =
          _server!.addTracksToQueue(files, widget.hostName);

      if (!mounted) return;
      setState(() {});
      widget.onQueueChanged?.call();

      final msg = skipped > 0
          ? '$added track(s) added • $skipped already in queue, skipped'
          : '$added track(s) added to queue!';
      _showSnack(msg, skipped > 0 ? Colors.orange : TogetherTheme.primaryPurple);
    } finally {
      if (mounted) setState(() => _isAdding = false);
    }
  }

  // ─── Host: Remove a track ──────────────────────────────────────────────────

  void _removeAt(int index, String title) {
    _server!.removeTrackAt(index);
    setState(() {});
    widget.onQueueChanged?.call();
    _showSnack('Removed "$title" from queue', Colors.redAccent);
  }

  // ─── Host: Reorder ─────────────────────────────────────────────────────────

  void _onReorder(int oldIndex, int newIndex) {
    _server!.moveTrack(oldIndex, newIndex);
    setState(() {});
    widget.onQueueChanged?.call();
  }

  // ─── Host: Jump to track ───────────────────────────────────────────────────

  void _jumpToTrack(int index) {
    if (_server == null) return;
    if (index == _server!.currentIndex) return; // already playing
    _server!.currentIndex = index;
    setState(() {});
    widget.onQueueChanged?.call();
    widget.onTrackSelected?.call(index);
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, Color bg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isHost = widget.isHost && _server != null;
    final tracks = isHost ? _playlist : widget.readOnlyTracks;
    final currentIdx = isHost ? _currentIndex : widget.readOnlyCurrentIndex;

    return Scaffold(
      backgroundColor: TogetherTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: TogetherTheme.darkBackground,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Song Queue',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: TogetherTheme.textPrimary,
              ),
            ),
            Text(
              '${tracks.length} track${tracks.length == 1 ? '' : 's'}${isHost ? ' • tap & hold to reorder' : ''}',
              style: const TextStyle(
                fontSize: 12,
                color: TogetherTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
      body: tracks.isEmpty
          ? _buildEmptyState(isHost)
          : isHost
              ? _buildHostList(tracks as List<TrackItem>, currentIdx)
              : _buildReadOnlyList(
                  tracks as List<Map<String, dynamic>>, currentIdx),
      floatingActionButton: isHost
          ? FloatingActionButton.extended(
              onPressed: _isAdding ? null : _addSongs,
              backgroundColor: _isAdding
                  ? TogetherTheme.primaryPurple.withValues(alpha: 0.5)
                  : TogetherTheme.primaryPurple,
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: const Text(
                'Add Songs',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            )
          : null,
    );
  }

  // ─── Empty state ───────────────────────────────────────────────────────────

  Widget _buildEmptyState(bool isHost) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.queue_music_rounded,
              size: 64, color: TogetherTheme.textMuted),
          const SizedBox(height: 16),
          const Text(
            'Queue is empty',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: TogetherTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isHost
                ? 'Tap "Add Songs" to fill the party queue!'
                : 'The host hasn\'t added any songs yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: TogetherTheme.textSecondary, fontSize: 13),
          ),
          if (isHost) ...[
            const SizedBox(height: 24),
            GradientButton(
              label: 'Add Songs',
              icon: Icons.playlist_add_rounded,
              onPressed: _addSongs,
            ),
          ],
        ],
      ),
    );
  }

  // ─── Host list: reorderable + swipe-to-delete ──────────────────────────────

  Widget _buildHostList(List<TrackItem> tracks, int currentIdx) {
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: tracks.length,
      onReorderItem: _onReorder,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 6,
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: child,
      ),
      itemBuilder: (context, index) {
        final item = tracks[index];
        final isCurrent = index == currentIdx;

        final tile = _buildTile(
          key: ValueKey('host_track_$index'),
          index: index,
          title: item.title,
          owner: item.ownerName,
          isCurrent: isCurrent,
          onTap: isCurrent ? null : () => _jumpToTrack(index),
          trailing: isCurrent
              ? _nowBadge()
              : const Icon(
                  Icons.drag_handle_rounded,
                  color: TogetherTheme.textMuted,
                  size: 22,
                ),
        );

        if (isCurrent) return tile;

        return Dismissible(
          key: ValueKey('dismiss_$index'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Colors.red.shade800,
            ),
            child: const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
          ),
          onDismissed: (_) => _removeAt(index, item.title),
          child: tile,
        );
      },
    );
  }

  // ─── Listener read-only list ───────────────────────────────────────────────

  Widget _buildReadOnlyList(
      List<Map<String, dynamic>> tracks, int currentIdx) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final isCurrent = index == currentIdx;
        return _buildTile(
          key: ValueKey('ro_track_$index'),
          index: index,
          title: track['title'] as String? ?? 'Unknown',
          owner: track['ownerName'] as String? ?? '?',
          isCurrent: isCurrent,
          trailing: isCurrent ? _nowBadge() : null,
        );
      },
    );
  }

  // ─── Shared tile ──────────────────────────────────────────────────────────

  Widget _buildTile({
    required Key key,
    required int index,
    required String title,
    required String owner,
    required bool isCurrent,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: isCurrent
            ? TogetherTheme.primaryPurple.withValues(alpha: 0.18)
            : TogetherTheme.cardSurface,
        border: Border.all(
          color: isCurrent
              ? TogetherTheme.primaryPurple
              : TogetherTheme.glassBorder,
          width: isCurrent ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: isCurrent
            ? const EqualizerVisualizer(
                isPlaying: true,
                barColor: TogetherTheme.liveGreen,
                height: 20,
              )
            : Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: TogetherTheme.cardSurfaceLight,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: TogetherTheme.textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isCurrent
                ? TogetherTheme.textPrimary
                : TogetherTheme.textSecondary,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          'Added by $owner',
          style: const TextStyle(
            fontSize: 11,
            color: TogetherTheme.textMuted,
          ),
        ),
        trailing: trailing,
      ),
    );
  }

  Widget _nowBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: TogetherTheme.liveGreen.withValues(alpha: 0.2),
        ),
        child: const Text(
          'PLAYING',
          style: TextStyle(
            color: TogetherTheme.liveGreen,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.8,
          ),
        ),
      );
}
