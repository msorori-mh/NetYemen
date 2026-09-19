import 'package:flutter/material.dart';

import '../app/app_shell.dart';

/// Compatibility entrypoint for the retired legacy shell.
///
/// The customer application is owned by [AppShell]. Keeping this small adapter
/// allows older navigation code to compile without restoring the duplicated
/// home, wallet, purchases, or profile implementations.
@Deprecated('Use AppShell from app/app_shell.dart instead.')
class MainScreen extends StatelessWidget {
  const MainScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppShell();
}
