import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// Applies a control message coming from the host to a local [AudioPlayer],
/// using [serverNowMs] (a function returning "what time it is on the host's
/// clock, right now") to line up playback across every device.
///
/// This same function is used by BOTH the host (with an offset of 0, since
/// the host's clock IS the reference clock) and every listener (with an
/// offset computed via [SyncClient]'s ping/pong calibration). That means
/// there's only one code path to get right.
Future<void> applySyncMessage(
    AudioPlayer player,
    Map<String, dynamic> msg,
    int Function() serverNowMs,
    ) async {
  switch (msg['type']) {
    case 'load':
      final url = msg['audioUrl'] as String;
      final title = (msg['title'] as String?) ?? 'Together';
      // A MediaItem tag is what just_audio_background reads to populate the
      // lock-screen / notification controls — without it, background
      // playback still works but the notification has no title to show.
      await player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          tag: MediaItem(id: url, title: title, album: 'Together party'),
        ),
      );
      break;

    case 'play':
      final startAt = msg['serverStartTime'] as int; // host clock, ms epoch
      final positionMs = msg['positionMs'] as int; // position song should be at startAt
      final delay = startAt - serverNowMs();

      if (delay > 0) {
        // We're early: seek to the agreed position now, then fire play()
        // exactly when the host clock hits startAt.
        await player.seek(Duration(milliseconds: positionMs));
        Future.delayed(Duration(milliseconds: delay), () {
          player.play();
        });
      } else {
        // We're late (e.g. connection lag, or a freshly-joined listener) —
        // catch up by seeking forward past the missed time, then play now.
        final catchUpMs = positionMs + (-delay);
        await player.seek(Duration(milliseconds: catchUpMs));
        player.play();
      }
      break;

    case 'pause':
      final positionMs = msg['positionMs'] as int;
      await player.pause();
      await player.seek(Duration(milliseconds: positionMs));
      break;
  }
}