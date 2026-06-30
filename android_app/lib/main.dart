// main.dart for AKRAMYG Flutter Application

import 'package:flutter/material.dart';
import 'core/database.dart';
import 'core/ai_client.dart';
import 'core/decision_engine.dart';
import 'core/memory_engine.dart';
import 'core/event_bus.dart';
import 'core/local_server.dart';
import 'core/cloud_relay_service.dart';
import 'ui/home_screen.dart';
import 'ui/tasks_screen.dart';
import 'ui/conversation_screen.dart';
import 'ui/insights_screen.dart';
import 'ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize SQLite Database
  final dbHelper = DatabaseHelper.instance;
  await dbHelper.database; // Triggers schema creation

  // 2. Initialize Core Subsystems
  final aiClient = GeminiAiClient();
  final decisionEngine = DecisionEngine(aiClient);
  final memoryEngine = MemoryEngine(aiClient);
  final localServer = LocalSyncServer(aiClient);

  // 3. Start Decision Engine listeners
  decisionEngine.initialize();

  // 4. Start Local Sync Server in background
  try {
    await localServer.start(port: 8080);
  } catch (e) {
    print('Error starting sync server: $e');
  }

  // 4b. Start Cloud Relay Background Poller
  final cloudRelayService = CloudRelayService();
  cloudRelayService.start();

  // 5. Run UI
  runApp(AkramygApp(
    aiClient: aiClient,
    decisionEngine: decisionEngine,
    memoryEngine: memoryEngine,
    localServer: localServer,
  ));
}

class AkramygApp extends StatelessWidget {
  final GeminiAiClient aiClient;
  final DecisionEngine decisionEngine;
  final MemoryEngine memoryEngine;
  final LocalSyncServer localServer;

  const AkramygApp({
    super.key,
    required this.aiClient,
    required this.decisionEngine,
    required this.memoryEngine,
    required this.localServer,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AKRAMYG',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F2EB), // Warm Beige
        primaryColor: const Color(0xFFC05A3E), // Burnt Sienna
        cardColor: const Color(0xFFFAF8F5), // Light Sand Card
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFC05A3E),
          secondary: Color(0xFFE58E73),
          surface: Color(0xFFFAF8F5),
          background: Color(0xFFF5F2EB),
          onPrimary: Colors.white,
          onSurface: Color(0xFF2E2724),
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: Color(0xFF2E2724)),
          bodyMedium: TextStyle(fontFamily: 'Roboto', color: Color(0xFF2E2724)),
          bodySmall: TextStyle(fontFamily: 'Roboto', color: Color(0xFF8A7B76)),
        ),
        useMaterial3: true,
      ),
      home: AppNavigationWrapper(
        aiClient: aiClient,
        decisionEngine: decisionEngine,
        memoryEngine: memoryEngine,
        localServer: localServer,
      ),
    );
  }
}

class AppNavigationWrapper extends StatefulWidget {
  final GeminiAiClient aiClient;
  final DecisionEngine decisionEngine;
  final MemoryEngine memoryEngine;
  final LocalSyncServer localServer;

  const AppNavigationWrapper({
    super.key,
    required this.aiClient,
    required this.decisionEngine,
    required this.memoryEngine,
    required this.localServer,
  });

  @override
  State<AppNavigationWrapper> createState() => _AppNavigationWrapperState();
}

class _AppNavigationWrapperState extends State<AppNavigationWrapper> {
  int _currentIndex = 0;
  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      HomeScreen(decisionEngine: widget.decisionEngine),
      TasksScreen(decisionEngine: widget.decisionEngine, aiClient: widget.aiClient),
      ConversationScreen(aiClient: widget.aiClient, memoryEngine: widget.memoryEngine),
      InsightsScreen(),
      SettingsScreen(aiClient: widget.aiClient, localServer: widget.localServer),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: const Color(0xFFFAF8F5),
        selectedItemColor: const Color(0xFFC05A3E),
        unselectedItemColor: const Color(0xFF8A7B76),
        showSelectedLabels: true,
        showUnselectedLabels: true,
        selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.flash_on_rounded),
            label: 'Now',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.task_alt_rounded),
            label: 'Tasks',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            label: 'Convo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: 'Insights',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
