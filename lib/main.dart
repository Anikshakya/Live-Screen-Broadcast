import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase/firebase_client_screen.dart';
import 'firebase/firebase_host_screen.dart';
import 'firebase_options.dart';
import 'websocket/websocket_client_screen.dart';
import 'websocket/websocket_host_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  runApp(const MirrorApp());
}

class MirrorApp extends StatelessWidget {
  const MirrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Screen Mirror',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.teal,
          surface: Color(0xFF1E293B),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E293B),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const MainMenu(),
    );
  }
}

class MainMenu extends StatelessWidget {
  const MainMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final bool isSmall = size.width < 400;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cast_connected_rounded,
                size: 20,
                color: Colors.tealAccent,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Real-Time Screen Mirror',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: isSmall ? 16.0 : 24.0,
            vertical: isSmall ? 16.0 : 24.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Branding Card
              Container(
                padding: EdgeInsets.all(isSmall ? 18 : 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E293B),
                      Colors.teal.withValues(alpha: 0.15),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFF334155)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 16,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.teal.withValues(alpha: 0.5),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.teal.withValues(alpha: 0.3),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.cast_for_education_rounded,
                        size: 42,
                        color: Colors.tealAccent,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Interactive Device Mirror',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isSmall ? 20 : 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Choose between Local Wi-Fi (WebSocket) or Global Cloud (Firebase) for screen broadcasting and remote touch interactions.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: isSmall ? 12 : 13.5,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- SECTION 1: WEBSOCKET LAN ---
              const Padding(
                padding: EdgeInsets.only(left: 4.0, bottom: 10.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.wifi_rounded,
                      color: Colors.tealAccent,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'WEBSOCKET (LOCAL WI-FI)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.tealAccent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),

              _buildRoleCard(
                context: context,
                title: 'WebSocket Host',
                subtitle:
                    'Broadcast screen over local Wi-Fi with ultra-low latency & remote touch input.',
                badgeText: 'Host Server',
                icon: Icons.wifi_tethering_rounded,
                accentColor: Colors.tealAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WebSocketHostScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              _buildRoleCard(
                context: context,
                title: 'WebSocket Client',
                subtitle:
                    'Connect to Host IP to view live screen and send real-time touch gestures.',
                badgeText: 'Client Receiver',
                icon: Icons.devices_rounded,
                accentColor: Colors.tealAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WebSocketClientScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),

              // --- SECTION 2: FIREBASE CLOUD ---
              const Padding(
                padding: EdgeInsets.only(left: 4.0, bottom: 10.0),
                child: Row(
                  children: [
                    Icon(
                      Icons.local_fire_department_rounded,
                      color: Colors.orangeAccent,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'FIREBASE (GLOBAL CLOUD)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.orangeAccent,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),

              _buildRoleCard(
                context: context,
                title: 'Firebase Host',
                subtitle:
                    'Broadcast screen to cloud room (room_101) for global cross-network streaming.',
                badgeText: 'Cloud Host',
                icon: Icons.cloud_upload_rounded,
                accentColor: Colors.orangeAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FirebaseHostScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              _buildRoleCard(
                context: context,
                title: 'Firebase Client',
                subtitle:
                    'Connect via Room ID to view cloud broadcast from anywhere on the web or mobile.',
                badgeText: 'Cloud Client',
                icon: Icons.cloud_download_rounded,
                accentColor: Colors.orangeAccent,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FirebaseClientScreen(),
                    ),
                  );
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String badgeText,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: accentColor.withValues(alpha: 0.15),
          highlightColor: accentColor.withValues(alpha: 0.05),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Icon(icon, size: 28, color: accentColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white60,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Colors.white38,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
