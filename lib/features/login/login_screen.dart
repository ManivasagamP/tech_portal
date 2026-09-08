import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/env.dart';
import '../../app/router.dart';
import '../../state/auth_controller.dart';
import '../../state/providers.dart';
import '../../theme/fe_colors.dart';
import '../../widgets/app_text.dart';
import '../../widgets/common.dart';
import '../../widgets/technician_loading.dart';

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

    final ok = await ref
        .read(authControllerProvider.notifier)
        .login(_username.text.trim(), _password.text);
    if (!mounted) return;

    if (ok) {
      final session = ref.read(authControllerProvider).session;
      if (session != null && !session.isInHouse) {
        await ref.read(authControllerProvider.notifier).logout();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: AppText(
              'This account belongs to a partner. Use the partner portal to sign in.',
            ),
          ),
        );
        return;
      }
      context.go(Routes.dashboard);
    }
  }

  void _showServerSettingsDialog() {
    final store = ref.read(sessionStoreProvider);
    final currentUrl = store.readBaseUrlOverride() ?? Env.defaultApiBaseUrl;
    final controller = TextEditingController(text: currentUrl);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(LucideIcons.server, size: 20, color: FeColors.primary),
            SizedBox(width: 8),
            AppText.title('Connection Settings'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppText.bodySmall(
              'Only change this if your IT team has asked you to.',
              color: FeColors.ink2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Server Address',
                hintText: 'http://localhost:5000',
                prefixIcon: Icon(LucideIcons.globe, size: 16),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await store.writeBaseUrlOverride(null);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const AppText('Reset to Default', color: FeColors.ink2),
          ),
          ElevatedButton(
            onPressed: () async {
              final val = controller.text.trim();
              await store.writeBaseUrlOverride(val.isEmpty ? null : val);
              if (ctx.mounted) Navigator.of(ctx).pop();
            },
            child: const AppText('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      backgroundColor: FeColors.page,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Technician Hero Branding Emblem
                  Center(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Soft glow halo
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: FeColors.primaryLight.withValues(
                              alpha: 0.12,
                            ),
                          ),
                        ),
                        // Outer bordered badge ring
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [FeColors.ink, FeColors.primary],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: FeColors.primary.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                            border: Border.all(
                              color: FeColors.primaryLight.withValues(
                                alpha: 0.4,
                              ),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            LucideIcons.hardHat,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Session badge
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: FeColors.infoSoft,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: FeColors.primaryLight.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.shieldCheck,
                            size: 13,
                            color: FeColors.primary,
                          ),
                          SizedBox(width: 6),
                          AppText.caption(
                            'SECURE SIGN IN',
                            color: FeColors.ink,
                            weight: FontWeight.w600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  AppText.title(
                    '${Env.brandName} Technician',
                    align: TextAlign.center,
                    weight: FontWeight.w700,
                  ),
                  const SizedBox(height: 4),
                  const AppText.bodySmall(
                    'Field service app for technicians',
                    align: TextAlign.center,
                    color: FeColors.ink2,
                  ),
                  const SizedBox(height: 24),

                  // Session Expired Banner (if redirected after 24h)
                  if (auth.sessionExpired) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: FeColors.warningSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: FeColors.warning.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            LucideIcons.clockAlert,
                            color: FeColors.warning,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: AppText.bodySmall(
                              "You've been signed out after 24 hours. Please sign in again.",
                              color: FeColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Login Form Card
                  TechCard(
                    padding: const EdgeInsets.all(24),
                    radius: 16,
                    child: auth.isBusy
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: TechnicianLoadingView(
                              message: 'Signing you in...',
                              submessage: 'Checking your username and password',
                              showBrand: false,
                            ),
                          )
                        : Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const AppText.label(
                                  'TECHNICIAN SIGN IN',
                                  color: FeColors.ink2,
                                  weight: FontWeight.w700,
                                ),
                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _username,
                                  autocorrect: false,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Technician ID or Username',
                                    hintText: 'e.g. tech1 or email@domain.com',
                                    prefixIcon: Icon(
                                      LucideIcons.userCheck,
                                      size: 18,
                                      color: FeColors.primary,
                                    ),
                                  ),
                                  validator: (value) =>
                                      (value == null || value.trim().isEmpty)
                                      ? 'Technician ID or username is required'
                                      : null,
                                ),
                                const SizedBox(height: 16),

                                TextFormField(
                                  controller: _password,
                                  obscureText: _obscure,
                                  textInputAction: TextInputAction.done,
                                  onFieldSubmitted: (_) => _submit(),
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(
                                      LucideIcons.keyRound,
                                      size: 18,
                                      color: FeColors.primary,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscure
                                            ? LucideIcons.eye
                                            : LucideIcons.eyeOff,
                                        size: 18,
                                        color: FeColors.ink2,
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
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: FeColors.dangerSoft,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: FeColors.danger.withValues(
                                          alpha: 0.3,
                                        ),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          LucideIcons.circleAlert,
                                          color: FeColors.danger,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: AppText.bodySmall(
                                            auth.error!,
                                            color: FeColors.danger,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 24),

                                SizedBox(
                                  height: 48,
                                  child: ElevatedButton(
                                    onPressed: _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: FeColors.primary,
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(LucideIcons.logIn, size: 18),
                                        SizedBox(width: 8),
                                        AppText(
                                          'Sign In',
                                          color: Colors.white,
                                          weight: FontWeight.w600,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),

                  // Bottom Technical Security Info & Server Configuration
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.lock,
                        size: 12,
                        color: FeColors.ink2,
                      ),
                      const SizedBox(width: 4),
                      const AppText.caption(
                        'Stays signed in for 24 hours',
                        color: FeColors.ink2,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: 'Connection Settings',
                        icon: const Icon(
                          LucideIcons.settings2,
                          size: 15,
                          color: FeColors.ink2,
                        ),
                        onPressed: _showServerSettingsDialog,
                      ),
                    ],
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
