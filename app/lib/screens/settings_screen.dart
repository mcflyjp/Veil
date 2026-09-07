import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import '../core/client_manager.dart';
import '../core/veil_theme.dart';
import '../core/veil_user_prefs.dart';
import '../widgets/buddy_avatar.dart';
import 'avatar_crop_screen.dart';

// Account settings screen: profile card (avatar, display name edit, locked
// screen-name chip), theme picker, privacy/security info + link to Linked
// Devices, and sign out. Display name is fetched from the Matrix profile on
// open (fetchDisplayName) rather than kept in ClientManager state.

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _displayName;
  bool _loadingName = true;
  Uri? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final mgr = context.read<ClientManager>();
    final results = await Future.wait([mgr.fetchDisplayName(), mgr.fetchAvatarUrl()]);
    if (mounted) {
      setState(() {
        _displayName = results[0] as String?;
        _avatarUrl   = results[1] as Uri?;
        _loadingName = false;
      });
    }
  }

  // ── Profile picture: pick → position → upload ──────────────────────────

  Future<void> _editAvatar(ClientManager mgr, VeilThemeColors tc) async {
    final hasAvatar = _avatarUrl != null;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: tc.inputBg,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetCtx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(Icons.photo_outlined, color: tc.toolbarText),
            title: Text('Choose Photo', style: TextStyle(color: tc.nameText, fontSize: 16)),
            onTap: () => Navigator.pop(sheetCtx, 'choose'),
          ),
          if (hasAvatar)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Remove Photo', style: TextStyle(color: Colors.red, fontSize: 16)),
              onTap: () => Navigator.pop(sheetCtx, 'remove'),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );

    if (action == 'remove') {
      try {
        await mgr.removeAvatar();
        if (mounted) setState(() => _avatarUrl = null);
      } catch (e) {
        _showError('Failed to remove photo: $e');
      }
      return;
    }
    if (action != 'choose') return;

    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final cropped = await Navigator.push<Uint8List>(context,
        MaterialPageRoute(builder: (_) => AvatarCropScreen(imageBytes: bytes)));
    if (cropped == null || !mounted) return;

    try {
      await mgr.setAvatar(cropped);
      final fresh = await mgr.fetchAvatarUrl();
      if (mounted) setState(() => _avatarUrl = fresh);
    } catch (e) {
      _showError('Failed to update photo: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)));
  }

  Future<void> _editDisplayName(ClientManager mgr, VeilThemeColors tc) async {
    final ctrl = TextEditingController(text: _displayName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: tc.inputBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Display Name',
            style: TextStyle(color: tc.nameText, fontSize: 18, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: tc.nameText, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Your display name',
            hintStyle: TextStyle(color: tc.previewText),
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: tc.toolbarActive)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: tc.toolbarActive, width: 2)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: tc.previewText))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: tc.badgeBg, foregroundColor: tc.badgeText),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && result != _displayName) {
      try {
        await mgr.setDisplayName(result);
        if (mounted) setState(() => _displayName = result);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Failed to update: $e'),
              duration: const Duration(seconds: 3)));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr   = context.watch<ClientManager>();
    final prefs = context.watch<VeilUserPrefs>();
    final tc    = prefs.colors;

    final screenName = mgr.myScreenName;
    final initial    = screenName.isNotEmpty ? screenName[0].toUpperCase() : '?';
    final topPad     = MediaQuery.of(context).padding.top;
    final bottomPad  = MediaQuery.viewPaddingOf(context).bottom;

    final displayedName = _loadingName ? '…' : (_displayName ?? screenName);

    return Scaffold(
      backgroundColor: tc.scaffold,
      body: Column(children: [
        // ── Title bar ───────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [tc.titleStart, tc.titleEnd],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          padding: EdgeInsets.fromLTRB(4, topPad + 12, 12, 12),
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: tc.titleOnColor, size: 24),
              onPressed: () => context.go('/buddylist'),
            ),
            Expanded(child: Text('Settings',
                style: TextStyle(color: tc.titleOnColor, fontSize: 18,
                    fontWeight: FontWeight.bold))),
          ]),
        ),

        // ── Scrollable body ─────────────────────────────────────────────
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: bottomPad + 16),
            children: [

              // ── Profile card ──────────────────────────────────────────
              _ProfileCard(
                initial: initial,
                screenName: screenName,
                displayName: displayedName,
                tc: tc,
                avatarUrl: _avatarUrl,
                client: mgr.client,
                onEditName: () => _editDisplayName(mgr, tc),
                onEditAvatar: () => _editAvatar(mgr, tc),
              ),

              const SizedBox(height: 12),

              // ── Appearance ────────────────────────────────────────────
              _SettingsSection(
                label: 'Appearance',
                tc: tc,
                children: [_ThemeSelector(prefs: prefs, tc: tc)],
              ),

              const SizedBox(height: 12),

              // ── Privacy ───────────────────────────────────────────────
              _SettingsSection(
                label: 'Privacy & Security',
                tc: tc,
                children: [
                  _InfoRow(
                    icon: Icons.lock_outline,
                    label: 'End-to-end encryption',
                    tc: tc,
                    trailing: _GreenChip('Active'),
                  ),
                  _Divider(tc: tc),
                  _InfoRow(
                    icon: Icons.dns_outlined,
                    label: 'Home server',
                    tc: tc,
                    trailing: Text('veilmsg.com',
                        style: TextStyle(fontSize: 14, color: tc.previewText)),
                  ),
                  _Divider(tc: tc),
                  _NavRow(
                    icon: Icons.devices_outlined,
                    label: 'Linked Devices',
                    tc: tc,
                    onTap: () => context.go('/buddylist/devices'),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // ── Account ───────────────────────────────────────────────
              _SettingsSection(
                label: 'Account',
                tc: tc,
                children: [
                  InkWell(
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: tc.inputBg,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          title: Text('Sign out?',
                              style: TextStyle(color: tc.nameText, fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          content: Text(
                              'You will be signed out of Veil on this device.',
                              style: TextStyle(color: tc.previewText, fontSize: 14)),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text('Cancel',
                                  style: TextStyle(color: tc.previewText))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Sign Out')),
                          ],
                        ),
                      );
                      if (confirm == true && context.mounted) {
                        await context.read<ClientManager>().logout();
                        if (context.mounted) context.go('/login');
                      }
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(children: [
                        Icon(Icons.logout, color: Colors.red, size: 22),
                        SizedBox(width: 14),
                        Text('Sign Out',
                            style: TextStyle(color: Colors.red, fontSize: 16,
                                fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Profile card ───────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String initial;
  final String screenName;
  final String displayName;
  final VeilThemeColors tc;
  final Uri? avatarUrl;
  final Client client;
  final VoidCallback onEditName;
  final VoidCallback onEditAvatar;

  const _ProfileCard({
    required this.initial, required this.screenName,
    required this.displayName, required this.tc,
    required this.avatarUrl, required this.client,
    required this.onEditName, required this.onEditAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = tc.rowBg == Colors.transparent ? tc.inputBg : tc.rowBg;
    return Container(
      color: cardBg,
      padding: const EdgeInsets.all(20),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        // Avatar — tap to change photo
        GestureDetector(
          onTap: onEditAvatar,
          child: Stack(children: [
            BuddyAvatar(initial: initial, tc: tc, isGroup: true, size: 68,
                avatarUrl: avatarUrl, client: client),
            Positioned(right: 0, bottom: 0,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tc.toolbarActive,
                  border: Border.all(color: cardBg, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 12, color: Colors.white),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 16),

        // Names
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Display name row with edit button
          Row(children: [
            Expanded(child: Text(displayName,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold,
                    color: tc.nameText),
                overflow: TextOverflow.ellipsis)),
            GestureDetector(
              onTap: onEditName,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: tc.toolbarActive.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.edit_outlined, size: 18, color: tc.toolbarActive),
              ),
            ),
          ]),
          const SizedBox(height: 6),

          // Screen name — locked chip
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: tc.badgeBg.withAlpha(25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tc.badgeBg.withAlpha(70)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 11, color: tc.badgeBg),
              const SizedBox(width: 5),
              Text('@$screenName',
                  style: TextStyle(fontSize: 13, color: tc.badgeBg,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ])),
      ]),
    );
  }
}

// ── Settings section card ──────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String label;
  final VeilThemeColors tc;
  final List<Widget> children;

  const _SettingsSection({required this.label, required this.tc, required this.children});

  @override
  Widget build(BuildContext context) {
    final cardBg = tc.rowBg == Colors.transparent ? tc.inputBg : tc.rowBg;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text(label.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 0.8, color: tc.toolbarActive)),
      ),
      Container(color: cardBg, child: Column(children: children)),
    ]);
  }
}

// ── Theme selector ─────────────────────────────────────────────────────────────

class _ThemeSelector extends StatelessWidget {
  final VeilUserPrefs prefs;
  final VeilThemeColors tc;
  const _ThemeSelector({required this.prefs, required this.tc});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
      // 6 themes now (was 4) — a single Row got cramped, so this is a 3-per-row grid.
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 4,
        mainAxisSpacing: 14,
        childAspectRatio: 0.86,
        children: VeilThemeMode.values.map((mode) {
          final t        = VeilThemeColors.forMode(mode);
          final selected = prefs.theme == mode;
          // Some swatches (Modern) have a light title-bar background — the
          // "their bubble" chip and selected checkmark need dark ink there
          // instead of the white that works on every other (dark) swatch.
          final swatchIsLight = ThemeData.estimateBrightnessForColor(t.titleStart) == Brightness.light;
          return GestureDetector(
            onTap: () => prefs.setTheme(mode),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // Preview swatch
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 60,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [t.titleStart, t.titleEnd],
                        begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: selected ? tc.toolbarActive : (swatchIsLight ? const Color(0xFFE4E7EF) : Colors.transparent),
                        width: selected ? 2.5 : 1),
                    boxShadow: selected
                        ? [BoxShadow(color: tc.toolbarActive.withAlpha(70),
                            blurRadius: 10, spreadRadius: 1)]
                        : null,
                  ),
                  child: Stack(children: [
                    // Mini chat bubbles preview
                    Positioned(bottom: 8, left: 6, right: 6,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Align(alignment: Alignment.centerRight,
                          child: Container(width: 24, height: 7,
                            decoration: BoxDecoration(
                              color: t.badgeBg,
                              borderRadius: BorderRadius.circular(4)))),
                        const SizedBox(height: 3),
                        Align(alignment: Alignment.centerLeft,
                          child: Container(width: 18, height: 7,
                            decoration: BoxDecoration(
                              color: swatchIsLight
                                  ? Colors.black.withAlpha(20)
                                  : (t.rowBg == Colors.transparent ? Colors.white.withAlpha(40) : t.rowBg),
                              borderRadius: BorderRadius.circular(4)))),
                      ]),
                    ),
                    if (selected)
                      Positioned(top: 4, right: 4,
                        child: Icon(Icons.check_circle,
                            color: swatchIsLight ? tc.toolbarActive : Colors.white, size: 14)),
                  ]),
                ),
                const SizedBox(height: 5),
                Text(mode.label,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        color: selected ? tc.toolbarActive : tc.previewText),
                    textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Info row ───────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VeilThemeColors tc;
  final Widget? trailing;

  const _InfoRow({required this.icon, required this.label, required this.tc, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
    child: Row(children: [
      Icon(icon, size: 20, color: tc.previewText),
      const SizedBox(width: 14),
      Expanded(child: Text(label,
          style: TextStyle(fontSize: 16, color: tc.nameText))),
      ?trailing,
    ]),
  );
}

class _Divider extends StatelessWidget {
  final VeilThemeColors tc;
  const _Divider({required this.tc});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 50),
    child: Divider(height: 1,
        color: tc.divider == Colors.transparent
            ? tc.nameText.withAlpha(15) : tc.divider),
  );
}

class _GreenChip extends StatelessWidget {
  final String label;
  const _GreenChip(this.label);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.green.shade600,
      borderRadius: BorderRadius.circular(12)),
    child: Text(label,
        style: const TextStyle(color: Colors.white, fontSize: 12,
            fontWeight: FontWeight.bold)),
  );
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VeilThemeColors tc;
  final VoidCallback onTap;
  const _NavRow({required this.icon, required this.label, required this.tc, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Icon(icon, size: 20, color: tc.previewText),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 16, color: tc.nameText))),
        Icon(Icons.chevron_right, size: 20, color: tc.previewText),
      ]),
    ),
  );
}
