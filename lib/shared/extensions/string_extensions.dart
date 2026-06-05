extension StringExt on String {
  /// Capitalize first letter
  String get capitalized =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// Truncate with ellipsis
  String truncate(int maxLen) =>
      length <= maxLen ? this : '${substring(0, maxLen)}…';

  /// True si l'e-mail est valide
  bool get isValidEmail =>
      RegExp(r'^[\w.+-]+@[\w-]+\.[a-zA-Z]{2,}$').hasMatch(this);

  /// True si le mot de passe est suffisamment fort (≥ 8 chars)
  bool get isStrongPassword => length >= 8;
}
