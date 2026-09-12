import 'install_prompt.dart';

/// Non-web builds: the phone and desktop apps are already installed.
InstallPrompt createInstallPrompt() => const NoInstallPrompt();
