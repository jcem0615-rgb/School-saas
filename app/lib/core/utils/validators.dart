/// Pure, dependency-free validators. Used both by usecases (pre-network
/// validation) and directly by TextFormField.validator in the UI, so the
/// same rule never has to be written twice.
class Validators {
  Validators._();

  /// The `(\.[\w\-]+)*` group is what allows multi-label domains. Without
  /// it the pattern only matches a single label before the TLD, which
  /// rejects every `*.edu.ph` address -- i.e. most Philippine school
  /// addresses, and therefore most of this product's users.
  static final RegExp _emailRegex =
      RegExp(r'^[\w\.\+\-]+@[\w\-]+(\.[\w\-]+)*\.[a-zA-Z]{2,}$');

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required.';
    if (!_emailRegex.hasMatch(value.trim())) return 'Enter a valid email address.';
    return null;
  }

  /// Minimum bar enforced client-side; Firebase Auth enforces >=6 chars
  /// server-side regardless. We require a stronger policy for a commercial
  /// product handling financial data.
  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Password is required.';
    if (value.length < 8) return 'Password must be at least 8 characters.';
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(value);
    final hasDigit = RegExp(r'\d').hasMatch(value);
    if (!hasLetter || !hasDigit) {
      return 'Password must contain both letters and numbers.';
    }
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? required(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required.';
    return null;
  }

  /// An email that may be left blank, but must be real if it is not.
  ///
  /// The student form's address is the one their portal account gets
  /// created against, and most students have none. Refusing to save a
  /// Grade 1 pupil without one gets an address invented; accepting a
  /// typo'd one gets an account nobody can ever reach. So: optional, and
  /// checked when present.
  static String? optionalEmail(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return email(value);
  }

  /// A Philippine mobile number that may be left blank.
  ///
  /// Mirrors normalizePhone in functions/src/shared/auth/phone.ts, which
  /// is what a password reset by phone matches against. A number this
  /// rejects is one that recovers nothing -- so the two have to agree,
  /// and the client saying yes where the server says no would just move
  /// the refusal to after the network call.
  static String? optionalPhilippineMobile(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return normalizePhilippineMobile(value) == null
        ? 'Enter a mobile number as 09171234567 or +639171234567.'
        : null;
  }

  /// The digits a number reduces to, or null when it is not one we can
  /// match on. `0917 555 0100`, `+639175550100` and `(0917) 555-0100` all
  /// come back as `639175550100`, because all three are the same phone
  /// and a family should not be locked out by a space.
  static String? normalizePhilippineMobile(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '');
    if (digits.isEmpty) return null;

    if (digits.startsWith('+')) {
      final rest = digits.substring(1);
      return RegExp(r'^\d{8,15}$').hasMatch(rest) ? rest : null;
    }
    // A leading zero is the national trunk prefix and is dropped when the
    // country code goes on; keeping it would make 09... and +639... two
    // different numbers.
    if (digits.startsWith('0')) {
      final rest = digits.substring(1);
      return RegExp(r'^\d{8,14}$').hasMatch(rest) ? '63$rest' : null;
    }
    if (digits.startsWith('63') && RegExp(r'^\d{10,15}$').hasMatch(digits)) {
      return digits;
    }
    if (RegExp(r'^9\d{9}$').hasMatch(digits)) return '63$digits';
    return null;
  }
}
