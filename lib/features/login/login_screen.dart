import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/env.dart';
import '../../app/router.dart';
import '../../state/auth_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_extensions.dart';
import '../../widgets/common.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final ok = await ref.read(authControllerProvider.notifier).login(
          _username.text.trim(),
          _password.text,
        );
    if (!mounted) return;

    if (ok) {
      final session = ref.read(authControllerProvider).session;
      if (session != null && !session.isInHouse) {
        await ref.read(authControllerProvider.notifier).logout();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This account belongs to a partner. Use the partner portal to sign in.',
            ),
          ),
        );
        return;
      }
      context.go(Routes.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: AppColors.gray50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 64,
                    width: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.orange500, AppColors.orange600],
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(LucideIcons.wrench,
                        color: AppColors.white, size: 30),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    '${Env.brandName} Technician',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sign in to see the jobs assigned to you.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  TechCard(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _username,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Username or email',
                              prefixIcon: Icon(LucideIcons.user, size: 18),
                            ),
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? 'Username or Email is required'
                                    : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _password,
                            obscureText: _obscure,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(LucideIcons.lock, size: 18),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscure ? LucideIcons.eye : LucideIcons.eyeOff,
                                  size: 18,
                                ),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                            validator: (value) =>
                                (value == null || value.isEmpty)
                                    ? 'Password is required'
                                    : null,
                          ),
                          if (auth.error != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.red50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: AppColors.red200),
                              ),
                              child: Text(
                                auth.error!,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppColors.red700),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            height: context.metrics.buttonDialog,
                            child: ElevatedButton(
                              onPressed: auth.isBusy ? null : _submit,
                              child: auth.isBusy
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                            AppColors.white),
                                      ),
                                    )
                                  : const Text('Sign In'),
                            ),
                          ),
                        ],
                      ),
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
