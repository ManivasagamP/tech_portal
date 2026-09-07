import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_theme.dart';
import 'env.dart';
import 'router.dart';

class TechnicianApp extends ConsumerWidget {
  const TechnicianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
        title: '${Env.brandName} Technician',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        routerConfig: ref.watch(routerProvider),
      );
}
