import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/url_launcher_service.dart';
import '../../domain/entities/last_fm_account.dart';
import '../../domain/entities/pending_scrobble.dart';
import '../../domain/entities/scrobble_settings.dart';
import '../providers/last_fm_providers.dart';
import 'pending_scrobbles_page.dart';
import 'scrobble_history_page.dart';

class LastFmSettingsPage extends ConsumerStatefulWidget {
  const LastFmSettingsPage({super.key});

  @override
  ConsumerState<LastFmSettingsPage> createState() => _LastFmSettingsPageState();
}

class _LastFmSettingsPageState extends ConsumerState<LastFmSettingsPage> {
  bool _isConnecting = false;
  String? _pendingAuthToken;
  Uri? _pendingAuthUrl;
  bool _copiedLink = false;
  Timer? _copiedLinkResetTimer;
  String? _authErrorMessage;
  String? _configuredApiKey;

  @override
  void initState() {
    super.initState();
    _checkConfiguredKey();
  }

  @override
  void dispose() {
    _copiedLinkResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkConfiguredKey() async {
    final key = await ref.read(lastFmRepositoryProvider).getApiKey();
    if (mounted) {
      setState(() {
        _configuredApiKey = key;
      });
    }
  }

  Future<void> _startAuth() async {
    setState(() {
      _isConnecting = true;
      _authErrorMessage = null;
    });

    final repo = ref.read(lastFmRepositoryProvider);
    final tokenResult = await repo.getAuthToken();

    if (!mounted) return;

    if (tokenResult.isFailure) {
      final failure = tokenResult.failureOrNull!;
      setState(() {
        _isConnecting = false;
        _authErrorMessage = failure.message;
      });

      if (failure.message.contains('not configured')) {
        await _showConfigDialog();
      }
      return;
    }

    final token = tokenResult.dataOrNull!;
    final authUrl = await repo.getAuthUrl(token);

    if (!mounted) return;

    setState(() {
      _pendingAuthToken = token;
      _pendingAuthUrl = authUrl;
      _copiedLink = false;
      _isConnecting = false;
    });

    // Launch authorization in external browser
    const launcher = DefaultUrlLauncherService();
    await launcher.launch(authUrl);
  }

  Future<void> _completeAuth() async {
    final token = _pendingAuthToken;
    if (token == null) return;

    setState(() {
      _isConnecting = true;
      _authErrorMessage = null;
    });

    final repo = ref.read(lastFmRepositoryProvider);
    final result = await repo.completeAuthentication(token);

    if (!mounted) return;

    if (result.isFailure) {
      final failure = result.failureOrNull!;
      setState(() {
        _isConnecting = false;
        _authErrorMessage =
            failure.message.contains('not been authorized') ||
                failure.message.contains('Authentication Failed')
            ? 'Authorization not yet completed on Last.fm. Please approve Musii in your browser and try again.'
            : failure.message;
      });
      return;
    }

    setState(() {
      _isConnecting = false;
      _pendingAuthToken = null;
      _authErrorMessage = null;
    });
  }

  void _cancelPendingAuth() {
    setState(() {
      _isConnecting = false;
      _pendingAuthToken = null;
      _authErrorMessage = null;
    });
  }

  void _showDisconnectDialog() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Disconnect Last.fm?'),
        content: const Text(
          'Musii will stop sending new listening activity to Last.fm. '
          'Your existing Last.fm history will not be deleted.',
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(lastFmRepositoryProvider).disconnect();
            },
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
  }

  Future<void> _showConfigDialog() async {
    final repo = ref.read(lastFmRepositoryProvider);
    final currentKey = await repo.getApiKey();
    final currentSecret = await repo.getApiSecret();

    if (!mounted) return;

    final apiKeyController = TextEditingController(text: currentKey ?? '');
    final apiSecretController = TextEditingController(
      text: currentSecret ?? '',
    );

    await showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Last.fm API Credentials'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your Last.fm API Key and Shared Secret to enable scrobbling.\n(Obtain free at last.fm/api/account/create)',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: apiKeyController,
                placeholder: 'API Key',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              CupertinoTextField(
                controller: apiSecretController,
                placeholder: 'Shared Secret',
                obscureText: true,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Save'),
            onPressed: () async {
              final key = apiKeyController.text
                  .replaceAll('"', '')
                  .replaceAll("'", '')
                  .trim();
              final sec = apiSecretController.text
                  .replaceAll('"', '')
                  .replaceAll("'", '')
                  .trim();
              if (key.isNotEmpty && sec.isNotEmpty) {
                await ref
                    .read(lastFmRepositoryProvider)
                    .setApiCredentials(apiKey: key, apiSecret: sec);
                if (mounted) {
                  setState(() {
                    _authErrorMessage = null;
                  });
                }
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
          ),
        ],
      ),
    );
  }

  String _formatLastSynced(DateTime? dt) {
    if (dt == null) return 'Never';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return DateFormat('MMM d, h:mm a').format(dt);
  }

  String _maskKey(String key) {
    if (key.length <= 8) return key;
    return '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(lastFmAccountProvider);
    final settingsAsync = ref.watch(lastFmSettingsProvider);
    final pendingAsync = ref.watch(lastFmPendingScrobblesProvider);

    final account = accountAsync.value;
    final settings = settingsAsync.value ?? const ScrobbleSettings();
    final pendingList = pendingAsync.value ?? const <PendingScrobble>[];
    final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

    final isConnected =
        account != null && account.status != LastFmAccountStatus.disconnected;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Last.fm'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => unawaited(_showConfigDialog()),
          child: const Icon(CupertinoIcons.gear_alt, size: 22),
        ),
      ),
      child: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: isConnected
              ? _buildConnectedView(
                  context,
                  account,
                  settings,
                  pendingList,
                  isDark,
                )
              : _buildDisconnectedView(context, isDark),
        ),
      ),
    );
  }

  Widget _buildDisconnectedView(BuildContext context, bool isDark) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        const SizedBox(height: 32),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFD51007).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                CupertinoIcons.music_note_2,
                color: Color(0xFFD51007),
                size: 40,
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Keep your listening\nhistory in sync.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Connect Musii to automatically scrobble the music you listen to, track your listening habits, and discover new songs.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            color: isDark
                ? CupertinoColors.systemGrey
                : CupertinoColors.secondaryLabel,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 36),

        if (_authErrorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.destructiveRed.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _authErrorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CupertinoColors.destructiveRed,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        if (_pendingAuthToken != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1F28) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Authorizing in browser...',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Text(
                  'Approve Musii on Last.fm in your browser, then tap Complete Connection below.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.secondaryLabel,
                  ),
                ),
                if (_pendingAuthUrl != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF12131A)
                          : CupertinoColors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? CupertinoColors.systemGrey.withOpacity(0.2)
                            : CupertinoColors.systemGrey4,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _pendingAuthUrl.toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontFamily: 'monospace',
                              color: isDark
                                  ? CupertinoColors.systemGrey
                                  : CupertinoColors.secondaryLabel,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        CupertinoButton(
                          padding: EdgeInsets.zero,
                          minSize: 28,
                          onPressed: () {
                            final url = _pendingAuthUrl?.toString();
                            if (url != null) {
                              unawaited(
                                Clipboard.setData(ClipboardData(text: url)),
                              );
                              setState(() => _copiedLink = true);
                              _copiedLinkResetTimer?.cancel();
                              _copiedLinkResetTimer = Timer(
                                const Duration(seconds: 2),
                                () {
                                  if (mounted) {
                                    setState(() => _copiedLink = false);
                                  }
                                },
                              );
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _copiedLink
                                    ? CupertinoIcons.checkmark_alt
                                    : CupertinoIcons.doc_on_clipboard,
                                size: 14,
                                color: CupertinoColors.activeBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _copiedLink ? 'Copied' : 'Copy',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: CupertinoColors.activeBlue,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () async {
                      if (_pendingAuthUrl != null) {
                        const launcher = DefaultUrlLauncherService();
                        await launcher.launch(_pendingAuthUrl!);
                      }
                    },
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.compass, size: 15),
                        SizedBox(width: 6),
                        Text(
                          'Re-open Browser',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoButton.filled(
                    onPressed: _isConnecting ? null : _completeAuth,
                    child: _isConnecting
                        ? const CupertinoActivityIndicator(
                            color: CupertinoColors.white,
                          )
                        : const Text('Complete Connection'),
                  ),
                ),
                const SizedBox(height: 8),
                CupertinoButton(
                  onPressed: _cancelPendingAuth,
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ] else ...[
          if (_configuredApiKey != null && _configuredApiKey!.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: CupertinoColors.activeGreen.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.checkmark_circle_fill,
                        size: 14,
                        color: CupertinoColors.activeGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'API Key: ${_maskKey(_configuredApiKey!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.activeGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          SizedBox(
            width: double.infinity,
            child: CupertinoButton.filled(
              onPressed: _isConnecting ? null : _startAuth,
              child: _isConnecting
                  ? const CupertinoActivityIndicator(
                      color: CupertinoColors.white,
                    )
                  : const Text(
                      'Connect Last.fm',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConnectedView(
    BuildContext context,
    LastFmAccount account,
    ScrobbleSettings settings,
    List<PendingScrobble> pendingList,
    bool isDark,
  ) {
    final requiresReauth = account.requiresReauth;

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 16),

        // Account Header
        Center(
          child: Column(
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                ),
                clipBehavior: Clip.antiAlias,
                child:
                    account.avatarUrl != null && account.avatarUrl!.isNotEmpty
                    ? Image.network(
                        account.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _buildAvatarFallback(account),
                      )
                    : _buildAvatarFallback(account),
              ),
              const SizedBox(height: 12),
              Text(
                '@${account.username}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              if (account.realName != null && account.realName!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  account.realName!,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark
                        ? CupertinoColors.systemGrey
                        : CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: requiresReauth
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.activeGreen,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    requiresReauth ? 'Reconnect needed' : 'Connected',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: requiresReauth
                          ? CupertinoColors.destructiveRed
                          : CupertinoColors.activeGreen,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (requiresReauth) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CupertinoColors.destructiveRed.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Text(
                    'Last.fm needs you to reconnect.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.destructiveRed,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Your recent listening is still safe.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  CupertinoButton.filled(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    onPressed: _startAuth,
                    child: const Text(
                      'Reconnect',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Scrobbling Toggles
        CupertinoListSection.insetGrouped(
          header: const Text('LISTENING'),
          children: [
            CupertinoListTile(
              title: const Text('Scrobble automatically'),
              subtitle: const Text(
                'Songs you listen to in Musii are sent to Last.fm when eligible.',
              ),
              trailing: CupertinoSwitch(
                value: settings.scrobblingEnabled,
                onChanged: (val) {
                  ref.read(lastFmRepositoryProvider).setScrobblingEnabled(val);
                },
              ),
            ),
            CupertinoListTile(
              title: const Text('Now Playing'),
              subtitle: const Text(
                'Broadcast currently playing song in real time',
              ),
              trailing: CupertinoSwitch(
                value: settings.nowPlayingEnabled,
                onChanged: (val) {
                  ref.read(lastFmRepositoryProvider).setNowPlayingEnabled(val);
                },
              ),
            ),
          ],
        ),

        // Offline Scrobbles Section
        CupertinoListSection.insetGrouped(
          header: const Text('OFFLINE SCROBBLES'),
          children: [
            CupertinoListTile(
              title: const Text('Offline Scrobbles'),
              subtitle: Text(
                pendingList.isEmpty
                    ? '0 tracks waiting to sync'
                    : '${pendingList.length} track${pendingList.length == 1 ? '' : 's'} waiting to sync',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pendingList.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemOrange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${pendingList.length}',
                        style: const TextStyle(
                          color: CupertinoColors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(width: 4),
                  const Icon(
                    CupertinoIcons.chevron_forward,
                    size: 18,
                    color: CupertinoColors.systemGrey,
                  ),
                ],
              ),
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const PendingScrobblesPage(),
                  ),
                );
              },
            ),
          ],
        ),

        // Scrobble Activity Section
        CupertinoListSection.insetGrouped(
          header: const Text('SCROBBLE ACTIVITY'),
          children: [
            CupertinoListTile(
              title: const Text('Scrobbles synced'),
              trailing: Text(
                '${account.scrobbleCount}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.secondaryLabel,
                ),
              ),
            ),
            CupertinoListTile(
              title: const Text('Last synced'),
              trailing: Text(
                _formatLastSynced(account.lastSyncedAt),
                style: TextStyle(
                  color: isDark
                      ? CupertinoColors.systemGrey
                      : CupertinoColors.secondaryLabel,
                ),
              ),
            ),
            CupertinoListTile(
              title: const Text('Recent Scrobbles'),
              trailing: const Icon(
                CupertinoIcons.chevron_forward,
                size: 18,
                color: CupertinoColors.systemGrey,
              ),
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const ScrobbleHistoryPage(),
                  ),
                );
              },
            ),
          ],
        ),

        // Account Actions
        CupertinoListSection.insetGrouped(
          header: const Text('ACCOUNT'),
          children: [
            CupertinoListTile(
              title: const Text('Open Last.fm profile'),
              trailing: const Icon(
                CupertinoIcons.arrow_up_right,
                size: 18,
                color: CupertinoColors.systemGrey,
              ),
              onTap: () {
                const launcher = DefaultUrlLauncherService();
                launcher.launch(Uri.parse(account.profileUrl));
              },
            ),
            CupertinoListTile(
              title: const Text(
                'Disconnect Last.fm',
                style: TextStyle(color: CupertinoColors.destructiveRed),
              ),
              trailing: const Icon(
                CupertinoIcons.chevron_forward,
                size: 18,
                color: CupertinoColors.destructiveRed,
              ),
              onTap: _showDisconnectDialog,
            ),
          ],
        ),

        const SizedBox(height: 64),
      ],
    );
  }

  Widget _buildAvatarFallback(LastFmAccount account) {
    return Center(
      child: Text(
        account.username.isNotEmpty ? account.username[0].toUpperCase() : '?',
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          color: Color(0xFFD51007),
        ),
      ),
    );
  }
}
