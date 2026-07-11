import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../core/client_manager.dart';
import '../core/veil_theme.dart';
import '../core/veil_user_prefs.dart';

class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});
  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<Device>? _devices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _devices = null; _error = null; });
    try {
      final mgr = context.read<ClientManager>();
      final devices = await mgr.getDevices();
      if (mounted) setState(() => _devices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
  }

  Future<void> _revokeDevice(BuildContext ctx, Device device, VeilThemeColors tc) async {
    final mgr    = context.read<ClientManager>();
    final pwCtrl = TextEditingController();
    String? password;

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: tc.inputBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Device',
            style: TextStyle(color: tc.nameText, fontSize: 18,
                fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            'Removing "${device.displayName ?? device.deviceId}" will sign it out. '
            'Enter your password to confirm.',
            style: TextStyle(color: tc.previewText, fontSize: 14),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: pwCtrl,
            obscureText: true,
            autofocus: true,
            onChanged: (v) => password = v,
            style: TextStyle(color: tc.nameText, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: tc.previewText),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: tc.toolbarActive)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: tc.toolbarActive, width: 2)),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: TextStyle(color: tc.previewText))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () {
              password = pwCtrl.text;
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Remove')),
        ],
      ),
    );
    pwCtrl.dispose();

    if (confirmed != true || password == null || password!.isEmpty || !ctx.mounted) return;

    try {
      await mgr.deleteDevice(device.deviceId, password!);
      if (mounted) _load();
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _showAddDeviceQr(BuildContext ctx, VeilThemeColors tc) async {
    final mgr = context.read<ClientManager>();
    String? token;
    String? err;
    try {
      token = await mgr.requestLoginToken();
    } catch (e) {
      err = e.toString().replaceAll('Exception: ', '');
    }
    if (!ctx.mounted) return;
    if (err != null) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(err), backgroundColor: Colors.red));
      return;
    }
    showDialog(
      context: ctx,
      builder: (_) => _QrDialog(token: token!, tc: tc),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mgr           = context.watch<ClientManager>();
    final tc            = context.watch<VeilUserPrefs>().colors;
    final topPad        = MediaQuery.of(context).padding.top;
    final currentDevice = mgr.client.deviceID;

    return Scaffold(
      backgroundColor: tc.scaffold,
      body: Column(children: [
        // ── Title bar ─────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd]),
          ),
          padding: EdgeInsets.fromLTRB(4, topPad + 12, 12, 12),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: tc.titleOnColor, size: 24),
              onPressed: () => context.go('/buddylist/settings'),
            ),
            Expanded(child: Text('Linked Devices',
                style: TextStyle(color: tc.titleOnColor, fontSize: 18,
                    fontWeight: FontWeight.bold))),
            Tooltip(
              message: 'Add device via QR code',
              child: IconButton(
                icon: Icon(Icons.qr_code, color: tc.titleOnColor, size: 24),
                onPressed: () => _showAddDeviceQr(context, tc),
              ),
            ),
          ]),
        ),

        // ── Body ──────────────────────────────────────────────────────
        Expanded(
          child: _devices == null && _error == null
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!,
                        style: TextStyle(color: Colors.red.shade400, fontSize: 14),
                        textAlign: TextAlign.center),
                  ),
                )
              : _devices!.isEmpty
              ? Center(child: Text('No devices found',
                  style: TextStyle(fontSize: 16, color: tc.previewText)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _devices!.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1, indent: 66,
                      color: tc.divider == Colors.transparent
                          ? tc.nameText.withAlpha(15) : tc.divider,
                    ),
                    itemBuilder: (ctx, i) {
                      final device    = _devices![i];
                      final isCurrent = device.deviceId == currentDevice;
                      final name      = device.displayName ?? device.deviceId;
                      final lastSeen  = device.lastSeenTs != null
                          ? DateTime.fromMillisecondsSinceEpoch(device.lastSeenTs!)
                          : null;

                      return ListTile(
                        tileColor: tc.rowBg == Colors.transparent ? null : tc.rowBg,
                        leading: Container(
                          width: 44, height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCurrent
                                ? tc.toolbarActive.withAlpha(30)
                                : tc.previewText.withAlpha(20),
                          ),
                          child: Icon(Icons.phone_android,
                              color: isCurrent ? tc.toolbarActive : tc.previewText,
                              size: 22),
                        ),
                        title: Row(children: [
                          Expanded(child: Text(name,
                              style: TextStyle(fontSize: 15, color: tc.nameText,
                                  fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis)),
                          if (isCurrent)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.green.shade600,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('This device',
                                  style: TextStyle(color: Colors.white,
                                      fontSize: 11, fontWeight: FontWeight.bold)),
                            ),
                        ]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (device.lastSeenIp != null)
                              Text(device.lastSeenIp!,
                                  style: TextStyle(fontSize: 12,
                                      color: tc.previewText)),
                            if (lastSeen != null)
                              Text(_formatDate(lastSeen),
                                  style: TextStyle(fontSize: 12,
                                      color: tc.previewText)),
                          ],
                        ),
                        isThreeLine: device.lastSeenIp != null && lastSeen != null,
                        trailing: isCurrent
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red, size: 22),
                                tooltip: 'Remove device',
                                onPressed: () => _revokeDevice(ctx, device, tc),
                              ),
                      );
                    },
                  ),
                ),
        ),
      ]),
    );
  }

  String _formatDate(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

/// Dialog showing a QR code for device linking (m.login.token flow).
class _QrDialog extends StatelessWidget {
  final String token;
  final VeilThemeColors tc;
  const _QrDialog({required this.token, required this.tc});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: tc.inputBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Add Device',
          style: TextStyle(color: tc.nameText, fontSize: 18,
              fontWeight: FontWeight.bold),
          textAlign: TextAlign.center),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: token,
            version: QrVersions.auto,
            size: 220,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Open Veil on your new device, tap\n"Sign in by scanning a QR code",\nthen point the camera at this code.',
          style: TextStyle(fontSize: 13, color: tc.previewText),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text('Expires in ~2 minutes • Single use',
            style: TextStyle(fontSize: 11,
                color: tc.previewText.withAlpha(150),
                fontStyle: FontStyle.italic),
            textAlign: TextAlign.center),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: TextStyle(color: tc.toolbarActive))),
      ],
    );
  }
}
