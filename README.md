# Together

Host plays a song, everyone on the same Wi-Fi network hears it in sync on
their own phone → own Bluetooth earphone. No Bluetooth multi-device tricks
needed, because each phone only ever talks to its own headset.

## How it works

- **Host** picks an audio file from their phone. The app starts a tiny local
  server (`SyncServer`) that (1) serves that file over plain HTTP, and
  (2) opens a WebSocket for control messages.
- **Listeners** enter the host's local IP address and connect. Their app
  (`SyncClient`) does a few rounds of ping/pong with the host to measure the
  clock offset between their phone and the host's phone — this is the same
  idea NTP uses to sync clocks over an unreliable network.
- When the host hits play, the host broadcasts *"start playing from position
  X at host-clock-time Y"* (a few hundred ms in the future) to every
  listener. Each phone converts Y into its own local time using the offset
  it measured, and schedules `play()` for that exact instant. Same idea for
  pause/seek, and for someone joining mid-song.
- The actual song *file* is a local HTTP download over Wi-Fi, not a live
  audio stream — that's what makes sync as tight as it is. You're not
  fighting network jitter on every audio sample, only on the scheduling
  message.

This is deliberately **not** built on WebRTC. WebRTC captures the
microphone, not a song already playing — it's the right tool for "broadcast
my voice," not "broadcast this MP3 without an echoey mic re-recording of it."

## Setting this up

This drop only contains `pubspec.yaml` and `lib/`. To turn it into a runnable
project:

```bash
flutter create --project-name together .
# then copy pubspec.yaml and lib/ from this folder over the generated ones
flutter pub get
```

Note that `flutter create` sets the on-device app label from the project
name too, but only as a default — Android reads it from `android/app/src/main/AndroidManifest.xml`
(the `android:label` attribute on `<application>`) and iOS from
`ios/Runner/Info.plist` (`CFBundleDisplayName`). If you want the icon under
the app to say exactly "Together" rather than a generated default, set both
of those explicitly after running `flutter create`.

### Android

1. `android/app/src/main/AndroidManifest.xml` needs internet + local network
   access — `<uses-permission android:name="android.permission.INTERNET"/>`
   (usually already present in the default template).
2. Android blocks plain `http://` by default since API 28. Since this app
   only talks to devices on the same LAN, add to the `<application>` tag:
   `android:usesCleartextTraffic="true"`. (For production you'd scope this
   to local IP ranges with a network security config instead of allowing it
   globally.)
3. `file_picker` will prompt for storage/media permissions at runtime — no
   manifest changes needed beyond what the plugin's own setup docs say.

### iOS

1. iOS 14+ requires `NSLocalNetworkUsageDescription` in `Info.plist` (a
   sentence explaining why the app talks to other devices on the LAN), or
   the OS silently blocks the connections.
2. `NSAppTransportSecurity` → allow arbitrary/local loads, same reasoning as
   Android's cleartext setting above.

## Honest limitations

- **Same Wi-Fi network only.** There's no NAT traversal or relay server
  here — this is a LAN party app, not an internet-wide one. Extending it to
  work over the internet is possible (add a relay server, handle the file
  transfer through it too) but is a materially bigger project.
- **"No latency" means very close, not sample-perfect.** Expect
  drift on the order of tens of milliseconds depending on Wi-Fi conditions
  and each phone's audio pipeline startup time — inaudible for casual group
  listening, but this isn't a professional silent-disco rig.
- **No continuous drift correction yet.** Sync is (re-)established at
  play/pause/seek/join. For very long tracks you could add a periodic
  "nudge" that gently corrects small drift — I kept it out here to keep the
  logic easy to follow, happy to add it.
- **Manual IP entry.** Simple and reliable, but not as slick as scanning a
  QR code or auto-discovering hosts (mDNS/Bonjour). Worth adding later.
- **Whatever file the host picks.** No YouTube/Spotify playback — streaming
  someone else's copyrighted stream to other users through your own app
  isn't something those platforms allow, separate from any technical
  question.
- I don't have a Flutter SDK in this environment to compile/run this, so
  treat it as a solid first pass rather than pre-verified — run
  `flutter pub get` and fix anything a package version bump changed
  (`just_audio` and `file_picker` APIs have been stable, but worth checking
  their changelogs if `flutter pub get` complains).

## Natural next steps

- Periodic drift-correction nudges during playback.
- mDNS-based auto-discovery so listeners don't type an IP.
- A "queue" so listeners can suggest the next song.
- Per-listener volume, so quieter/louder earbuds can be balanced.
