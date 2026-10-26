import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/app_state.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';

/// Display name, unique @username and bio - used both to set up a new
/// account's profile and to edit it later.
///
/// The username is checked against the database as the user types, so they
/// know it is free before they press save. Display names can repeat.
class ProfileForm extends StatefulWidget {
  const ProfileForm({
    super.key,
    required this.submitLabel,
    required this.onSubmit,
    this.initialName = '',
    this.initialHandle = '',
    this.initialBio = '',
    this.onCancel,
  });

  final String initialName;

  /// Without the '@'.
  final String initialHandle;
  final String initialBio;
  final String submitLabel;

  /// Saves the profile. Throw [ProfileFailure] to show a message.
  final Future<void> Function(String name, String handle, String bio) onSubmit;
  final VoidCallback? onCancel;

  @override
  State<ProfileForm> createState() => _ProfileFormState();
}

enum _Username { unchanged, checking, available, taken, invalid }

class _ProfileFormState extends State<ProfileForm> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  late final TextEditingController _handle =
      TextEditingController(text: widget.initialHandle)
        ..addListener(_handleChanged);
  late final TextEditingController _bio =
      TextEditingController(text: widget.initialBio);

  bool _saving = false;
  String? _error;
  late _Username _status =
      widget.initialHandle.isEmpty ? _Username.invalid : _Username.unchanged;
  Timer? _debounce;

  static final RegExp _pattern = RegExp(r'^[a-z0-9._]{3,20}$');

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _handle.dispose();
    _bio.dispose();
    super.dispose();
  }

  String get _clean => _handle.text.trim().toLowerCase().replaceFirst('@', '');

  void _handleChanged() {
    _debounce?.cancel();
    final clean = _clean;
    _Username next;
    if (clean.isNotEmpty && clean == widget.initialHandle) {
      next = _Username.unchanged;
    } else if (!_pattern.hasMatch(clean)) {
      next = _Username.invalid;
    } else {
      next = _Username.checking;
      _debounce = Timer(const Duration(milliseconds: 450), () async {
        final account = AppScope.of(context).account;
        bool free;
        try {
          free = await account.isHandleAvailable(clean);
        } catch (_) {
          free = true; // offline: let the save itself decide
        }
        if (!mounted || _clean != clean) return;
        setState(() => _status = free ? _Username.available : _Username.taken);
      });
    }
    if (next != _status) setState(() => _status = next);
  }

  bool get _canSave =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      (_status == _Username.unchanged || _status == _Username.available);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_name.text, _clean, _bio.text);
    } on ProfileFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          if (e.message.contains('taken')) _status = _Username.taken;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (String help, Color helpColor, Widget? suffix) = switch (_status) {
      _Username.unchanged => (
          'Unique across Inkbook - people find you by it',
          InkbookColors.inkSoft,
          null,
        ),
      _Username.checking => (
          'Checking...',
          InkbookColors.inkSoft,
          const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      _Username.available => (
          '@$_clean is available',
          InkbookColors.sage,
          const Icon(Icons.check_circle, color: InkbookColors.sage, size: 20),
        ),
      _Username.taken => (
          '@$_clean is taken - try another',
          InkbookColors.toolOrange,
          const Icon(Icons.cancel, color: InkbookColors.toolOrange, size: 20),
        ),
      _Username.invalid => (
          '3-20 characters: letters, numbers, dots and underscores',
          _clean.isEmpty ? InkbookColors.inkSoft : InkbookColors.toolOrange,
          null,
        ),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _name,
          enabled: !_saving,
          autofocus: widget.initialName.isEmpty,
          textCapitalization: TextCapitalization.words,
          maxLength: 60,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'DISPLAY NAME',
            helperText: 'Shown on your profile - does not need to be unique',
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _handle,
          enabled: !_saving,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 20,
          decoration: InputDecoration(
            labelText: 'USERNAME',
            prefixText: '@',
            helperText: help,
            helperStyle: InkbookType.body(size: 12, color: helpColor),
            suffixIcon: suffix,
            counterText: '',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _bio,
          enabled: !_saving,
          maxLines: 3,
          maxLength: 160,
          decoration: const InputDecoration(
            labelText: 'BIO (OPTIONAL)',
            hintText: 'What do you like to draw?',
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style:
                  InkbookType.body(size: 13, color: InkbookColors.toolOrange),
            ),
          ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            if (widget.onCancel != null)
              TextButton(
                onPressed: _saving ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _canSave ? _save : null,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: InkbookColors.folderCream,
                      ),
                    )
                  : Text(widget.submitLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// Edit the signed-in user's profile in a dialog.
Future<void> showEditProfile(BuildContext context) {
  final community = AppScope.of(context).community;
  final me = community.currentUser;
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Edit profile'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 8),
          child: ProfileForm(
            initialName: me.name,
            initialHandle: me.handle.replaceFirst('@', ''),
            initialBio: me.bio,
            submitLabel: 'Save',
            onCancel: () => Navigator.of(dialogContext).pop(),
            onSubmit: (name, handle, bio) async {
              await community.updateProfile(
                name: name,
                handle: handle,
                bio: bio,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
          ),
        ),
      ),
    ),
  );
}
