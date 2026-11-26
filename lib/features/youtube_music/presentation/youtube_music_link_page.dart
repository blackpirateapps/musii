import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/providers.dart';
import '../../../core/constants/app_constants.dart';

enum _PlaybackAction { play, playNext, queue }

class YouTubeMusicLinkPage extends ConsumerStatefulWidget {
  const YouTubeMusicLinkPage({super.key});

  @override
  ConsumerState<YouTubeMusicLinkPage> createState() =>
      _YouTubeMusicLinkPageState();
}

class _YouTubeMusicLinkPageState extends ConsumerState<YouTubeMusicLinkPage> {
  final _link = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _loading) return;
    _link.text = clipboard?.text?.trim() ?? '';
    setState(() => _error = null);
  }

  Future<void> _submit(_PlaybackAction action) async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await ref
        .read(youtubeMusicRepositoryProvider)
        .importLink(_link.text);
    if (!mounted) return;
    final track = result.dataOrNull;
    if (track == null) {
      setState(() {
        _loading = false;
        _error = result.failureOrNull?.message;
      });
      return;
    }

    final playback = ref.read(playbackRepositoryProvider);
    switch (action) {
      case _PlaybackAction.play:
        await playback.playTrack(track, queue: [track]);
      case _PlaybackAction.playNext:
        await playback.playNext(track);
      case _PlaybackAction.queue:
        await playback.playLast(track);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('YouTube Music'),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: CupertinoTextField(
                    controller: _link,
                    enabled: !_loading,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    clearButtonMode: OverlayVisibilityMode.editing,
                    placeholder: 'Song link',
                    onSubmitted: (_) => _submit(_PlaybackAction.play),
                  ),
                ),
                CupertinoButton(
                  onPressed: _loading ? null : _paste,
                  child: const Text('Paste'),
                ),
              ],
            ),
            if (error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              const Center(child: CupertinoActivityIndicator())
            else ...[
              CupertinoButton.filled(
                onPressed: () => _submit(_PlaybackAction.play),
                child: const Text('Play Now'),
              ),
              CupertinoButton(
                onPressed: () => _submit(_PlaybackAction.playNext),
                child: const Text('Play Next'),
              ),
              CupertinoButton(
                onPressed: () => _submit(_PlaybackAction.queue),
                child: const Text('Add to Queue'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
