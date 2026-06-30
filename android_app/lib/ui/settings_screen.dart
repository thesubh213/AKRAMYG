// settings_screen.dart for AKRAMYG Configurations UI

import 'package:flutter/material.dart';
import '../core/database.dart';
import '../core/ai_client.dart';
import '../core/local_server.dart';

class SettingsScreen extends StatefulWidget {
  final GeminiAiClient aiClient;
  final LocalSyncServer localServer;
  const SettingsScreen({super.key, required this.aiClient, required this.localServer});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseHelper _db = DatabaseHelper.instance;
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _relayUrlController = TextEditingController();
  final TextEditingController _pairingKeyController = TextEditingController();

  bool _isSaving = false;
  bool _isSavingRelay = false;
  bool _cloudRelayEnabled = false;
  
  // Privacy Provider States
  bool _foregroundApp = true;
  bool _battery = true;
  bool _network = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // Legacy/retired model names that should be auto-healed
  static const _legacyModels = {
    'gemini-1.5-flash', 'gemini-1.5-flash-latest', 'gemini-1.5-pro',
    'gemini-2.0-flash', 'gemini-2.0-flash-lite',
  };
  static const _defaultModel = 'gemini-2.5-flash';

  Future<void> _loadSettings() async {
    // 1. API key config
    final config = await _db.queryById('system_entities', 'gemini_api_key');
    if (config != null) {
      _apiKeyController.text = config['value'];
    }
    
    final modelConfig = await _db.queryById('system_entities', 'gemini_model');
    String loadedModel = modelConfig != null && modelConfig['value'] != null
        ? modelConfig['value'] as String
        : _defaultModel;

    // Auto-heal any legacy/retired model names
    if (loadedModel.isEmpty || _legacyModels.contains(loadedModel)) {
      loadedModel = _defaultModel;
      await _db.insert('system_entities', {
        'id': 'gemini_model',
        'value': _defaultModel,
        'updated_at': DateTime.now().toIso8601String()
      });
      if (config != null && config['value'] != null) {
        await widget.aiClient.updateConfig(config['value'], _defaultModel);
      }
    }
    _modelController.text = loadedModel;

    // 2. Cloud Relay configurations
    final relayEnabled = await _db.queryById('system_entities', 'cloud_relay_enabled');
    final relayUrl = await _db.queryById('system_entities', 'cloud_relay_url');
    final pairingKey = await _db.queryById('system_entities', 'cloud_relay_pairing_key');

    // 3. Context Providers configurations
    final appConfig = await _db.queryById('system_entities', 'foreground_app_provider');
    final battConfig = await _db.queryById('system_entities', 'battery_provider');
    final netConfig = await _db.queryById('system_entities', 'network_provider');

    setState(() {
      _cloudRelayEnabled = relayEnabled != null && relayEnabled['value'] == 'true';
      _relayUrlController.text = relayUrl != null ? relayUrl['value'] : 'http://localhost:8080/relay';
      _pairingKeyController.text = pairingKey != null ? pairingKey['value'] : '';

      _foregroundApp = appConfig == null || appConfig['value'] == 'true';
      _battery = battConfig == null || battConfig['value'] == 'true';
      _network = netConfig == null || netConfig['value'] == 'true';
    });
  }

  Future<void> _saveApiKey() async {
    setState(() {
      _isSaving = true;
    });

    final key = _apiKeyController.text.trim();
    final modelName = _modelController.text.trim().isEmpty ? _defaultModel : _modelController.text.trim();
    try {
      await _db.insert('system_entities', {
        'id': 'gemini_api_key',
        'value': key,
        'updated_at': DateTime.now().toIso8601String()
      });
      await _db.insert('system_entities', {
        'id': 'gemini_model',
        'value': modelName,
        'updated_at': DateTime.now().toIso8601String()
      });

      // Dynamically reconfigure client parameters
      await widget.aiClient.updateConfig(key, modelName);

      // Validate the model by sending a probe request
      final validationResult = await widget.aiClient.validateModel();
      final isSuccess = validationResult.contains('successfully');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSuccess ? '✅ $validationResult' : '⚠️ $validationResult'),
          backgroundColor: isSuccess ? const Color(0xFF27AE60) : const Color(0xFFC0392B),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save API key: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _saveRelaySettings() async {
    setState(() {
      _isSavingRelay = true;
    });

    final url = _relayUrlController.text.trim();
    final key = _pairingKeyController.text.trim();

    try {
      await _db.insert('system_entities', {
        'id': 'cloud_relay_enabled',
        'value': _cloudRelayEnabled.toString(),
        'updated_at': DateTime.now().toIso8601String()
      });
      await _db.insert('system_entities', {
        'id': 'cloud_relay_url',
        'value': url,
        'updated_at': DateTime.now().toIso8601String()
      });
      await _db.insert('system_entities', {
        'id': 'cloud_relay_pairing_key',
        'value': key,
        'updated_at': DateTime.now().toIso8601String()
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud Relay sync configuration saved!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save Relay configuration: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingRelay = false;
        });
      }
    }
  }

  Future<void> _toggleProvider(String providerId, bool value) async {
    await _db.insert('system_entities', {
      'id': providerId,
      'value': value.toString(),
      'updated_at': DateTime.now().toIso8601String()
    });

    _loadSettings();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;
    final cardColor = Theme.of(context).cardColor;
    final scaffoldBg = Theme.of(context).scaffoldBackgroundColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final textMuted = Theme.of(context).textTheme.bodySmall?.color ?? const Color(0xFF8A7B76);
    final dividerColor = Theme.of(context).dividerColor;

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, color: textColor)),
        backgroundColor: cardColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. AI API Configuration
            Text('🤖 AI ASSISTANT CONFIGURATION', style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            // Helpful Guide Card
            Card(
              color: primaryColor.withOpacity(0.08),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: primaryColor.withOpacity(0.2)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded, color: primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Text('Setup Quick Guide', style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '1. Get your free API Key from aistudio.google.com\n'
                      '2. Paste it below to enable AI-powered task planning.\n'
                      '3. Default model: gemini-2.5-flash (recommended).\n'
                      '4. Hit Save — we\'ll instantly verify your connection.',
                      style: TextStyle(fontSize: 12, color: textColor.withOpacity(0.85), height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            Card(
              color: cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _apiKeyController,
                      obscureText: true,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Enter Gemini API Key',
                        hintText: 'AIzaSy...',
                        labelStyle: TextStyle(color: textMuted),
                        filled: true,
                        fillColor: scaffoldBg,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modelController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Model Identifier',
                        hintText: 'gemini-2.5-flash',
                        helperText: 'Available: gemini-2.5-flash · gemini-2.5-pro · gemini-3.5-flash',
                        helperStyle: TextStyle(color: textMuted, fontSize: 10),
                        labelStyle: TextStyle(color: textMuted),
                        filled: true,
                        fillColor: scaffoldBg,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _saveApiKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        minimumSize: const Size.fromHeight(45),
                      ),
                      child: Text(_isSaving ? 'Verifying...' : 'Save & Verify Connection', style: const TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2. Connectivity Information
            Text('EXTENSION SYNC SERVER', style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              color: cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.sync_rounded, color: Color(0xFF27AE60)),
                        const SizedBox(width: 8),
                        const Text('Local Server Active', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF27AE60))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Provide this address in your Chrome Extension options screen to connect to the Core Decision Engine:',
                      style: TextStyle(fontSize: 12, color: textColor),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      'http://${widget.localServer.serverAddress ?? "localhost"}:8080',
                      style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 14, color: primaryColor),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 2b. Cloud Sync Relay
            Text('CLOUD SYNC RELAY', style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              color: cardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable Encrypted Cloud Relay', style: TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: const Text('Syncs browser contexts securely over network relays.'),
                      value: _cloudRelayEnabled,
                      activeColor: primaryColor,
                      onChanged: (val) {
                        setState(() {
                          _cloudRelayEnabled = val;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _relayUrlController,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Relay Mailbox URL',
                        labelStyle: TextStyle(color: textMuted),
                        filled: true,
                        fillColor: scaffoldBg,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pairingKeyController,
                      obscureText: true,
                      style: TextStyle(color: textColor),
                      decoration: InputDecoration(
                        labelText: 'Pairing Secret Key (Passphrase)',
                        labelStyle: TextStyle(color: textMuted),
                        filled: true,
                        fillColor: scaffoldBg,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _isSavingRelay ? null : _saveRelaySettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        minimumSize: const Size.fromHeight(45),
                      ),
                      child: Text(_isSavingRelay ? 'Saving...' : 'Save Relay Configuration', style: const TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 3. Privacy Sensor Options
            Text('PRIVACY & CONTEXT PROVIDERS', style: Theme.of(context).textTheme.bodySmall?.copyWith(letterSpacing: 1.5, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Card(
              color: cardColor,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Active Window (Browser Extension)'),
                    subtitle: const Text('Syncs browser domains, webpage content and scraped milestones.'),
                    value: _foregroundApp,
                    activeColor: primaryColor,
                    onChanged: (val) => _toggleProvider('foreground_app_provider', val),
                  ),
                  Divider(color: dividerColor, height: 1),
                  SwitchListTile(
                    title: const Text('Battery Level'),
                    subtitle: const Text('Adapts reminders and urgency rules when battery is critically low.'),
                    value: _battery,
                    activeColor: primaryColor,
                    onChanged: (val) => _toggleProvider('battery_provider', val),
                  ),
                  Divider(color: dividerColor, height: 1),
                  SwitchListTile(
                    title: const Text('Network Connectivity'),
                    subtitle: const Text('Pauses cloud relays and schedules offline-sync loops.'),
                    value: _network,
                    activeColor: primaryColor,
                    onChanged: (val) => _toggleProvider('network_provider', val),
                  ),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _modelController.dispose();
    _relayUrlController.dispose();
    _pairingKeyController.dispose();
    super.dispose();
  }
}
