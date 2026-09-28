import 'package:flutter/material.dart';

import 'camera_setup.dart';
import 'webrtc/classroom_call.dart';

/// Choosing a camera, in the middle of a lesson.
///
/// A school laptop has a built-in camera and often a better one on a
/// USB lead; a phone has two. The browser hands over whichever it likes
/// first, which is not reliably the one pointing at the teacher -- and
/// a teacher who has to leave the lesson to fix that has left the
/// lesson.
class CameraSheet extends StatefulWidget {
  final ClassroomCall call;

  /// Which camera is in use, and the callback that remembers a change.
  final String? current;
  final ValueChanged<String> onChosen;

  const CameraSheet({
    super.key,
    required this.call,
    required this.current,
    required this.onChosen,
  });

  @override
  State<CameraSheet> createState() => _CameraSheetState();
}

class _CameraSheetState extends State<CameraSheet> {
  List<CameraOption>? _cameras;
  String? _chosen;
  bool _blurOn = false;
  BackgroundSupport _blur = BackgroundSupport.unknown;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    _chosen = widget.current;
    _load();
  }

  Future<void> _load() async {
    final cameras = await widget.call.cameras();
    if (!mounted) return;
    setState(() {
      _cameras = cameras;
      _chosen ??= preferredCamera(cameras, widget.current)?.id;
    });
  }

  Future<void> _use(String id) async {
    setState(() {
      _chosen = id;
      _working = true;
    });
    await widget.call.useCamera(id);
    widget.onChosen(id);
    if (mounted) setState(() => _working = false);
  }

  Future<void> _blurBackground(bool on) async {
    setState(() => _working = true);
    final result = await widget.call.setBackgroundBlur(on);
    if (!mounted) return;
    setState(() {
      _blur = result;
      // Only claim it is on if the camera says it is. Browsers accept
      // this request and then leave the picture exactly as it was, and
      // a switch that sits in the "on" position over an unchanged
      // background is worse than one that admits it cannot.
      _blurOn = result == BackgroundSupport.available && on;
      _working = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cameras = _cameras;
    final why = backgroundUnavailableBecause(_blur);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Camera', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Changes apply to the lesson straight away. Nobody is '
              'disconnected.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (cameras == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (cameras.isEmpty)
              Text(
                'This device is not offering a camera. The browser may '
                'not have been given permission.',
                style: theme.textTheme.bodyMedium,
              )
            else
              for (final (position, camera) in cameras.indexed)
                ListTile(
                  onTap: _working ? null : () => _use(camera.id),
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _chosen == camera.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: _chosen == camera.id
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                  ),
                  title: Text(cameraLabel(camera, position)),
                ),
            const Divider(height: 28),
            SwitchListTile(
              value: _blurOn,
              onChanged: _working ? null : _blurBackground,
              contentPadding: EdgeInsets.zero,
              title: const Text('Blur my background'),
              subtitle: Text(
                why ??
                    'Hides the room behind you. Done by the camera and '
                        'the computer, so it costs the lesson nothing.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
