import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:rxdart/rxdart.dart';
import 'package:safe_device/safe_device.dart';
import 'package:safe_device/safe_device_config.dart';

void main() {
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

class _InspectorScreenState extends State<InspectorScreen>
    with WidgetsBindingObserver {
  static final _vpnInterfacePattern = RegExp(r'^(utun|tun|tap|ppp|ipsec)');

  DeviceSnapshot? _snapshot;
  bool _failed = false;

  StreamSubscription<Object?>? _triggerSub;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final networkTrigger = Connectivity().onConnectivityChanged;
    final timerTrigger = Stream<Object?>.periodic(const Duration(seconds: 15));

    _triggerSub = MergeStream<Object?>([networkTrigger, timerTrigger])
        .debounceTime(const Duration(milliseconds: 500))
        .listen(
          (_) => _checkAll(),
          onError: (Object e) => debugPrint("Trigger stream error: $e"),
        );

    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _triggerSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sub = _triggerSub;
    if (sub == null) return;
    if (state == AppLifecycleState.resumed) {
      if (sub.isPaused) sub.resume();
      _checkAll();
    } else if (!sub.isPaused) {
      sub.pause();
    }
  }

  Future<void> _start() async {
    await _ensureLocationPermission();
    await _checkAll();
  }

  Future<void> _ensureLocationPermission() async {
    try {
      final permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 3));
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint("Permission check failed: $e");
    }
  }

  Future<void> _checkAll() async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      // The timeout guards against a plugin call that never answers, which
      // would otherwise pin the UI on the spinner forever.
      final (network, security, device) = await (
        _getNetworkData(),
        _getSecurityData(),
        _getDeviceHardwareInfo(),
      ).wait.timeout(const Duration(seconds: 10));

      if (!mounted) return;
      setState(() {
        _failed = false;
        _snapshot = DeviceSnapshot(
          name: device.name,
          osVersion: device.version,
          interfaces: network.interfaces,
          isVpnActive: network.vpn,
          isJailBroken: security.jailbroken,
          isRealDevice: security.realDevice,
          isMockLocation: security.mockLocation,
          isDevMode: security.devMode,
        );
      });
    } catch (e) {
      debugPrint("Check error: $e");
      if (mounted && _snapshot == null) {
        setState(() => _failed = true);
      }
    } finally {
      _isChecking = false;
    }
  }

  Future<({bool vpn, List<String> interfaces})> _getNetworkData() async {
    final connectivity = await Connectivity().checkConnectivity();
    bool vpn = connectivity.contains(ConnectivityResult.vpn);

    final interfaces = await NetworkInterface.list();
    final names = interfaces.map((i) => i.name).toList();

    if (!vpn) {
      if (Platform.isAndroid) {
        // On Android a tun/ppp interface only exists while a VPN is up.
        vpn = names.any((n) => _vpnInterfacePattern.hasMatch(n.toLowerCase()));
      } else if (Platform.isIOS) {
        // iOS keeps system utun interfaces up even without a VPN, so the
        // name alone is meaningless; only count tunnels that carry a
        // routable address.
        vpn = interfaces.any((i) =>
            _vpnInterfacePattern.hasMatch(i.name.toLowerCase()) &&
            i.addresses.any(_isRoutable));
      }
    }

    return (vpn: vpn, interfaces: names);
  }

  static bool _isRoutable(InternetAddress address) {
    if (address.type == InternetAddressType.IPv4) return true;
    // Link-local (fe80::/10) and unique-local (fc00::/7) IPv6 addresses are
    // assigned to system tunnels; a VPN gets a globally routable one.
    final ip = address.address.toLowerCase();
    return !address.isLinkLocal && !ip.startsWith('fc') && !ip.startsWith('fd');
  }

  Future<({bool jailbroken, bool realDevice, bool mockLocation, bool devMode})>
      _getSecurityData() async {
    return (
      jailbroken: await SafeDevice.isJailBroken,
      realDevice: await SafeDevice.isRealDevice,
      mockLocation: await _isLocationMocked(),
      devMode: await SafeDevice.isDevelopmentModeEnable,
    );
  }

  Future<bool> _isLocationMocked() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 3),
          ),
        ).timeout(const Duration(seconds: 4));
        return position.isMocked;
      }
    } catch (e) {
      debugPrint("Location check failed: $e");
    }
    return SafeDevice.isMockLocation;
  }

  Future<({String name, String version})> _getDeviceHardwareInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final ios = await deviceInfo.iosInfo;
      return (
        name: ios.name,
        version: "${ios.systemName} ${ios.systemVersion}",
      );
    }

    final android = await deviceInfo.androidInfo;
    return (
      name: "${android.brand} ${android.model}",
      version: "Android ${android.version.release} (API ${android.version.sdkInt})",
    );
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
      navigationBar: const CupertinoNavigationBar(middle: Text("DeviceInspector")),
      child: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildAndroid() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("DeviceInspector"),
        backgroundColor: Colors.blue.withValues(alpha: 0.1),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return Center(child: _failed ? _buildError() : _buildSpinner());
    }
    return ListView(children: _buildContent(snapshot));
  }

  Widget _buildSpinner() {
    return Platform.isIOS
        ? const CupertinoActivityIndicator()
        : const CircularProgressIndicator();
  }

  Widget _buildError() {
    const message = Text("Couldn't read device state");
    final retry = Platform.isIOS
        ? CupertinoButton(onPressed: _checkAll, child: const Text("Retry"))
        : TextButton(onPressed: _checkAll, child: const Text("Retry"));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [message, retry],
    );
  }

  List<Widget> _buildContent(DeviceSnapshot snapshot) {
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
            Text(snapshot.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(snapshot.osVersion, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
      const SizedBox(height: 20),
      _sectionHeader("SYSTEM SECURITY"),
      _buildInfoRow("VPN Active", snapshot.isVpnActive ? "YES" : "NO", status: !snapshot.isVpnActive),
      _buildInfoRow(
        Platform.isIOS ? "Jailbreak" : "Root Access",
        snapshot.isJailBroken ? "YES" : "NO",
        status: !snapshot.isJailBroken,
      ),
      _buildInfoRow("Real Device", snapshot.isRealDevice ? "YES" : "EMULATOR", status: snapshot.isRealDevice),
      _buildInfoRow("Real Location", snapshot.isMockLocation ? "MOCK" : "REAL", status: !snapshot.isMockLocation),
      _buildInfoRow("Dev Mode / ADB", snapshot.isDevMode ? "ON" : "OFF", status: !snapshot.isDevMode),

      _sectionHeader("NETWORK INTERFACES"),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: snapshot.interfaces.map(_buildInterfaceChip).toList(),
        ),
      ),
    ];
  }

  Widget _buildInterfaceChip(String name) {
    final isTunnel = _vpnInterfacePattern.hasMatch(name.toLowerCase());
    if (Platform.isIOS) {
      // Material Chip needs a Material ancestor, which CupertinoApp
      // doesn't provide.
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isTunnel
              ? CupertinoColors.activeBlue.withValues(alpha: 0.2)
              : CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(name, style: const TextStyle(fontSize: 12)),
      );
    }
    return Chip(
      label: Text(name, style: const TextStyle(fontSize: 12)),
      backgroundColor: isTunnel ? Colors.blue.withValues(alpha: 0.2) : null,
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(title.toUpperCase(), style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold)),
    );
  }
}
