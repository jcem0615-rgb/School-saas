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
}
