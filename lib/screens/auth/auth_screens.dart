import 'package:flutter/material.dart';

import '../../controllers/app_state.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_form.dart';
import '../../widgets/scrapbook.dart';

/// The desk with the wordmark and a paper card in the middle - shared by
/// the welcome and profile set-up screens.
class _AuthLayout extends StatelessWidget {
  const _AuthLayout({required this.child, this.tagline});

  final Widget child;
  final String? tagline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: InkbookColors.desk,
      body: GrainSurface(
        color: InkbookColors.desk,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Column(
                children: <Widget>[
                  Text(
                    'Inkbook',
                    style: InkbookType.wordmark(
                      size: 56,
                      color: InkbookColors.folderCream,
                    ),
                  ),
                  Text(
                    tagline ?? 'an interactive digital sketchbook',
                    style: InkbookType.handwritten(
                      size: 17,
                      color: InkbookColors.folderCream.withAlpha(210),
                    ),
                  ),
                  const SizedBox(height: 28),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
                      decoration: BoxDecoration(
                        color: InkbookColors.folderCream,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: paperShadow(lift: 1.4),
                      ),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// First thing people see: sign in, or create an account.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _creating = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _attempt(Future<void> Function() action) async {
    setState(() {
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } on AuthFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _submit() {
    final account = AppScope.of(context).account;
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    _attempt(() => _creating
        ? account.createAccount(email, password)
        : account.signIn(email, password));
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Type your email above first.');
      return;
    }
    await _attempt(
      () => AppScope.of(context).account.sendPasswordReset(email),
    );
    if (mounted && _error == null) {
      setState(() => _notice = 'Check your inbox for a reset link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final busy = account.isBusy;
        return _AuthLayout(
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  _creating ? 'Create your account' : 'Welcome back',
                  style: InkbookType.title(size: 24),
                ),
                const SizedBox(height: 6),
                Text(
                  _creating
                      ? 'Your sketchbooks are saved to your account, so they '
                          'follow you to any device.'
                      : 'Sign in to open your sketchbooks.',
                  style: InkbookType.body(
                    size: 14,
                    color: InkbookColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed:
                      busy ? null : () => _attempt(account.signInWithGoogle),
                  icon: Text(
                    'G',
                    style: InkbookType.title(
                      size: 18,
                      color: InkbookColors.toolOrange,
                    ),
                  ),
                  label: const Text('Continue with Google'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text('OR', style: InkbookType.eyebrow()),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'EMAIL'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _password,
                  enabled: !busy,
                  obscureText: true,
                  autofillHints: <String>[
                    _creating
                        ? AutofillHints.newPassword
                        : AutofillHints.password,
                  ],
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: 'PASSWORD',
                    helperText: _creating ? 'At least 6 characters' : null,
                  ),
                ),
                if (!_creating)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : _forgot,
                      child: const Text('Forgot password?'),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: InkbookType.body(
                        size: 13,
                        color: InkbookColors.toolOrange,
                      ),
                    ),
                  ),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _notice!,
                      style: InkbookType.body(
                        size: 13,
                        color: InkbookColors.sage,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : _submit,
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: InkbookColors.folderCream,
                          ),
                        )
                      : Text(_creating ? 'Create account' : 'Sign in'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                            _creating = !_creating;
                            _error = null;
                            _notice = null;
                          }),
                  child: Text(
                    _creating
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown once, right after a new account is created (or the first time
/// someone signs in with Google): pick a display name and unique username.
class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    final suggested = account.user?.displayName ?? '';
    return _AuthLayout(
      tagline: 'one last step',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Set up your profile', style: InkbookType.title(size: 24)),
          const SizedBox(height: 6),
          Text(
            'This is how other artists will see you. You can change it '
            'any time.',
            style: InkbookType.body(size: 14, color: InkbookColors.inkSoft),
          ),
          const SizedBox(height: 20),
          ProfileForm(
            initialName: suggested,
            submitLabel: 'Start drawing',
            onSubmit: (name, handle, bio) => account.createProfile(
              name: name,
              handle: handle,
              bio: bio,
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: account.signOut,
              child: Text(
                'Not ${account.email ?? 'you'}? Sign out',
                style: InkbookType.body(size: 13, color: InkbookColors.inkSoft),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Loading went wrong (almost always: no connection).
class LoadFailedScreen extends StatelessWidget {
  const LoadFailedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    return _AuthLayout(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'Could not open your sketchbooks',
            textAlign: TextAlign.center,
            style: InkbookType.title(size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            'Check your internet connection and try again.',
            textAlign: TextAlign.center,
            style: InkbookType.body(size: 14, color: InkbookColors.inkSoft),
          ),
          if (account.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                '${account.error}',
                textAlign: TextAlign.center,
                style: InkbookType.body(size: 11, color: InkbookColors.inkSoft),
              ),
            ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: account.retry,
            child: const Text('Try again'),
          ),
          TextButton(
            onPressed: account.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
