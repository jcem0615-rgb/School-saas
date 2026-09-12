import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/core/install/install_prompt_factory.dart';

/// The install offer on a non-web build.
///
/// The point of the conditional export is that a phone build never
/// compiles `package:web` and never shows a button offering to install
/// the app it is already running inside. This is what pins that: the
/// test suite runs on the VM, takes the stub, and gets "nothing to
/// offer" — which is also what the widget renders as an empty box.
void main() {
  test('a non-web build has nothing to install', () {
    expect(createInstallPrompt().offer, InstallOffer.none);
  });

  test('and asking anyway is refused rather than throwing', () async {
    // The button never calls this when the offer is none, but a stub
    // that threw would turn a mis-wired screen into a crash instead of a
    // no-op.
    expect(await createInstallPrompt().show(), isFalse);
  });
}
