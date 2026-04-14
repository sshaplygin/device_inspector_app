import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:safe_device/safe_device.dart';

void main() => runApp(const DeviceInspectorApp());

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
  // Общие данные
  String _deviceName = "Loading...";
  String _osVersion = "";
  List<String> _interfaces = [];

  // Флаги безопасности
  bool _isVpnActive = false;
  bool _isJailBroken = false;
  bool _isRealDevice = true;
  bool _isDevMode = false;
  bool _onExternalStorage = false;

  late StreamSubscription _sub;

  @override
  void initState() {
    super.initState();
    _checkAll();
    _sub = Connectivity().onConnectivityChanged.listen((_) => _checkAll());
  }

  Future<void> _checkAll() async {
    // 1. Проверка VPN (API + Интерфейсы)
    bool vpn = false;
    List<String> ifaces = [];
    final res = await Connectivity().checkConnectivity();
    if (res.contains(ConnectivityResult.vpn)) vpn = true;

    try {
      final networkInterfaces = await NetworkInterface.list();
      for (var i in networkInterfaces) {
        ifaces.add(i.name);
        if (RegExp(r'tun|ppp|tap|utun|ipsec').hasMatch(i.name.toLowerCase())) {
          vpn = true;
        }
      }
    } catch (_) {}

    // 2. Параметры SafeDevice (нативно для обеих ОС)
    bool jailbroken = await SafeDevice.isJailBroken;
    bool realDevice = await SafeDevice.isRealDevice;
    bool devMode = await SafeDevice.isDevelopmentModeEnable;
    bool external = await SafeDevice.isOnExternalStorage;

    // 3. Device Info
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String name = "";
    String version = "";

    if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      name = iosInfo.name; // Имя, заданное пользователем (напр. "Sam's iPhone")
      version = "${iosInfo.systemName} ${iosInfo.systemVersion}";
    } else {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      name = "${androidInfo.brand} ${androidInfo.model}";
      version = "Android ${androidInfo.version.release} (API ${androidInfo.version.sdkInt})";
    }

    setState(() {
      _isVpnActive = vpn;
      _interfaces = ifaces;
      _isJailBroken = jailbroken;
      _isRealDevice = realDevice;
      _isDevMode = devMode;
      _onExternalStorage = external;
      _deviceName = name;
      _osVersion = version;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  // Вспомогательный метод для отображения строк данных
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