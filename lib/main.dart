import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'app_theme.dart';
import 'host_screen.dart';
import 'listener_screen.dart';
import 'ui_components.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.example.together.channel.audio',
    androidNotificationChannelName: 'Together playback',
    androidNotificationOngoing: false,
    androidStopForegroundOnPause: false,
  );
  runApp(const TogetherApp());
}

class TogetherApp extends StatelessWidget {
  const TogetherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Together',
      debugShowCheckedModeBanner: false,
      theme: TogetherTheme.darkTheme,
      home: const RoleSelectScreen(),
    );
  }
}

class RoleSelectScreen extends StatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  State<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends State<RoleSelectScreen> {
  @override
  Widget build(BuildContext context) {
    final isPartyRunning = isHostPartyRunning;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),

              // Hero Header & Branding
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: TogetherTheme.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: TogetherTheme.primaryPurple.withOpacity(0.4),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ShaderMask(
                      shaderCallback: (bounds) => TogetherTheme.primaryGradient.createShader(bounds),
                      child: const Text(
                        'TOGETHER',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Host or join synced listening parties over local Wi-Fi.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TogetherTheme.textSecondary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 36),

              // Dynamic Live Active Party Banner
              if (isPartyRunning) ...[
                GlassContainer(
                  borderColor: TogetherTheme.liveGreen,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF064E3B), Color(0xFF022C22)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const HostScreen()),
                    );
                    setState(() {});
                  },
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: TogetherTheme.liveGreen.withOpacity(0.2),
                        ),
                        child: const EqualizerVisualizer(
                          isPlaying: true,
                          barColor: TogetherTheme.liveGreen,
                          height: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PARTY IS LIVE',
                              style: TextStyle(
                                color: TogetherTheme.liveGreen,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Tap to resume control',
                              style: TextStyle(
                                color: TogetherTheme.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: TogetherTheme.liveGreen,
                        size: 18,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Role Card 1: Host a Party
              GlassContainer(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HostScreen()),
                  );
                  setState(() {});
                },
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: TogetherTheme.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.podcasts_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPartyRunning ? 'Party Menu / Playlist' : 'Host a Party',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: TogetherTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isPartyRunning
                                ? 'Add tracks or manage current stream'
                                : 'Select local audio & broadcast to friends',
                            style: const TextStyle(
                              fontSize: 13,
                              color: TogetherTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: TogetherTheme.textMuted,
                      size: 28,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Role Card 2: Join a Party
              GlassContainer(
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ListenerScreen()),
                  );
                  setState(() {});
                },
                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: TogetherTheme.cyanGradient,
                      ),
                      child: const Icon(
                        Icons.headphones_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Join a Party',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: TogetherTheme.textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Tune in to a nearby DJ on your local network',
                            style: TextStyle(
                              fontSize: 13,
                              color: TogetherTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: TogetherTheme.textMuted,
                      size: 28,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Footer Note
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.wifi_rounded, size: 16, color: TogetherTheme.textMuted),
                  SizedBox(width: 6),
                  Text(
                    'No cellular data required • Ultra-low sync latency',
                    style: TextStyle(color: TogetherTheme.textMuted, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
