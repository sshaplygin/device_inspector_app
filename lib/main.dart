import 'dart:async';
import 'dart:io';
import 'package:rxdart/rxdart.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:safe_device/safe_device.dart';
import 'package:safe_device/safe_device_config.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SafeDevice.init(
    SafeDeviceConfig(mockLocationCheckEnabled: true),
  );

  runApp(const DeviceInspectorApp());
}

class DeviceSnapshot {
  final String name;
  final String osVersion;
  final List<String> interfaces;
  final bool isVpnActive;
  final bool isJailBroken;
  final bool isRealDevice;
  final bool isMockLocation;
  final bool isDevMode;

  DeviceSnapshot({
    required this.name,
    required this.osVersion,
    required this.interfaces,
    required this.isVpnActive,
    required this.isJailBroken,
    required this.isRealDevice,
    required this.isMockLocation,
    required this.isDevMode,
  });
}

class DeviceInspectorApp extends StatelessWidget {
  const DeviceInspectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) {
      return const CupertinoApp(
        theme: CupertinoThemeData(brightness: Brightness.light),
        home: InspectorScreen(),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const InspectorScreen(),
    );
  }
}

class InspectorScreen extends StatefulWidget {
  const InspectorScreen({super.key});

  @override
  State<InspectorScreen> createState() => _InspectorScreenState();
}

class _InspectorScreenState extends State<InspectorScreen> {
  String _deviceName = "Loading...";
  String _osVersion = "";
  List<String> _interfaces = [];

  bool _isVpnActive = false;
  bool _isJailBroken = false;
  bool _isRealDevice = true;
  bool _isMockLocation = false;
  bool _isDevMode = false;
  bool _onExternalStorage = false;

  late StreamSubscription _mainSub;
  bool _isChecking = false;

   @override
  void initState() {
    super.initState();

    final networkTrigger = Connectivity().onConnectivityChanged;
    final timerTrigger = Stream.periodic(const Duration(seconds: 3));

    _mainSub = MergeStream([
      networkTrigger,
      timerTrigger,
    ])
    .debounceTime(const Duration(milliseconds: 500))
    .listen((_) => _checkAll());

    _checkAll();
  }

  Future<void> _checkAll() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      if (Platform.isAndroid) {
        if (await Permission.location.isDenied) {
          await Permission.location.request();
        }
      }

      final results = await Future.wait([
        _getNetworkData(),
        _getSecurityData(),
        _getDeviceHardwareInfo(),
      ]);

      if (!mounted) return;

      final network = results[0] as Map<String, dynamic>;
      final security = results[1] as Map<String, dynamic>;
      final device = results[2] as Map<String, String>;

      setState(() {
        _deviceName = device['name']!;
        _osVersion = device['version']!;
        _interfaces = network['interfaces'];
        _isVpnActive = network['vpn'];
        _isJailBroken = security['jailbroken'];
        _isRealDevice = security['realDevice'];
        _isMockLocation = security['mockLocation'];
        _isDevMode = security['devMode'];
      });
    } catch (e) {
      debugPrint("Check error: $e");
    } finally {
      _isChecking = false;
    }
  }

  @override
  void dispose() {
    _mainSub.cancel();
    super.dispose();
  }

  Future<Map<String, dynamic>> _getNetworkData() async {
    bool vpn = false;
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.vpn)) vpn = true;

    final interfaces = await NetworkInterface.list();
    final ifaceNames = interfaces.map((i) => i.name).toList();

    if (ifaceNames.any((name) => RegExp(r'tun|ppp|tap|utun|ipsec').hasMatch(name.toLowerCase()))) {
      vpn = true;
    }

    return {'vpn': vpn, 'interfaces': ifaceNames};
  }

  Future<Map<String, dynamic>> _getSecurityData() async {
    bool mockDetected = false;
    try {
      Position? pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 3),
      ).timeout(const Duration(seconds: 4));
      mockDetected = pos.isMocked;
    } catch (_) {
      mockDetected = await SafeDevice.isMockLocation;
    }

    return {
      'jailbroken': await SafeDevice.isJailBroken,
      'realDevice': await SafeDevice.isRealDevice,
      'mockLocation': mockDetected,
      'devMode': await SafeDevice.isDevelopmentModeEnable,
    };
  }

  Future<Map<String, String>> _getDeviceHardwareInfo() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      IosDeviceInfo ios = await deviceInfo.iosInfo;
      return {'name': ios.name, 'version': "${ios.systemName} ${ios.systemVersion}"};
    }

    AndroidDeviceInfo android = await deviceInfo.androidInfo;
    return {
      'name': "${android.brand} ${android.model}",
      'version': "Android ${android.version.release} (API ${android.version.sdkInt})"
    };
  }

  Widget _buildInfoRow(String label, String value, {bool? status}) {
    Color? textColor;
    if (status != null) {
      textColor = status ? Colors.green : Colors.red;
    }

    if (Platform.isIOS) {
      return CupertinoListTile(
        title: Text(label),
        additionalInfo: Text(value, style: TextStyle(color: textColor)),
      );
    } else {
      return ListTile(
        title: Text(label),
        trailing: Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Platform.isIOS ? _buildIos() : _buildAndroid();
  }

  Widget _buildIos() {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(middle: Text("Device Inspector")),
      child: SafeArea(
        child: ListView(
          children: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildAndroid() {
    return Scaffold(
      appBar: AppBar(title: const Text("Device Inspector"), backgroundColor: Colors.blue.withOpacity(0.1)),
      body: ListView(
        children: _buildContent(),
      ),
    );
  }

  List<Widget> _buildContent() {
    return [
      const SizedBox(height: 20),
      Center(
        child: Column(
          children: [
            Icon(
              Platform.isIOS ? CupertinoIcons.device_phone_portrait : Icons.smartphone,
              size: 60,
              color: Colors.grey,
            ),
            const SizedBox(height: 10),
            Text(_deviceName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(_osVersion, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionHeader("SYSTEM SECURITY"),
      _buildInfoRow("VPN Active", _isVpnActive ? "YES" : "NO", status: _isVpnActive),
      _buildInfoRow(
        Platform.isIOS ? "Jailbreak" : "Root Access",
        _isJailBroken ? "YES" : "NO",
        status: !_isJailBroken
      ),
      _buildInfoRow("Real Device", _isRealDevice ? "YES" : "EMULATOR", status: _isRealDevice),
      _buildInfoRow("Real Location", _isMockLocation ? "MOCK" : "REAL", status: !_isMockLocation),
      _buildInfoRow("Dev Mode / ADB", _isDevMode ? "ON" : "OFF", status: !_isDevMode),

      _sectionHeader("NETWORK INTERFACES"),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          spacing: 8,
          children: _interfaces.map((i) => Chip(
            label: Text(i, style: const TextStyle(fontSize: 12)),
            backgroundColor: (i.contains('tun') || i.contains('ppp')) ? Colors.blue.withOpacity(0.2) : null,
          )).toList(),
        ),
      ),
    ];
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
    );
  }
}
