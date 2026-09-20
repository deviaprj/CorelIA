/// Règles de validation du compte, isolées de l'interface pour être testables.
abstract class AuthValidators {
  /// Longueur minimale d'un mot de passe (Firebase en exige 6 ; on vise mieux).
  static const int minPasswordLength = 8;

  /// Âge minimal pour créer un compte.
  static const int minAge = 13;

  /// Âge au-delà duquel une date de naissance est considérée comme erronée.
  static const int maxAge = 120;

  static final RegExp _emailRegex = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  static String? email(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return 'Renseigne ton adresse e-mail.';
    if (!_emailRegex.hasMatch(trimmed)) return 'Adresse e-mail invalide.';
    return null;
  }

  static String? password(String? value) {
    final pwd = value ?? '';
    if (pwd.isEmpty) return 'Choisis un mot de passe.';
    if (pwd.length < minPasswordLength) {
      return 'Au moins $minPasswordLength caractères.';
    }
    if (!pwd.contains(RegExp('[A-Za-z]')) || !pwd.contains(RegExp(r'\d'))) {
      return 'Mélange au moins une lettre et un chiffre.';
    }
    return null;
  }

  static String? passwordConfirmation(String? value, String password) {
    if ((value ?? '').isEmpty) return 'Confirme ton mot de passe.';
    if (value != password) return 'Les deux mots de passe diffèrent.';
    return null;
  }

  static String? firstName(String? value) {
    if ((value ?? '').trim().length < 2) return 'Renseigne ton prénom.';
    return null;
  }

  static String? lastName(String? value) {
    if ((value ?? '').trim().length < 2) return 'Renseigne ton nom.';
    return null;
  }

  static String? birthDate(DateTime? value, {DateTime? now}) {
    if (value == null) return 'Renseigne ta date de naissance.';
    final today = now ?? DateTime.now();
    if (value.isAfter(today)) return 'La date ne peut pas être dans le futur.';
    final years = age(value, now: today);
    if (years > maxAge) return 'Cette date de naissance semble erronée.';
    if (years < minAge) return 'Tu dois avoir au moins $minAge ans.';
    return null;
  }

  /// Âge révolu à la date [now].
  static int age(DateTime birthDate, {DateTime? now}) {
    final today = now ?? DateTime.now();
    var years = today.year - birthDate.year;
    final birthdayPassed = today.month > birthDate.month ||
        (today.month == birthDate.month && today.day >= birthDate.day);
    if (!birthdayPassed) years--;
    return years < 0 ? 0 : years;
  }

  /// Vrai si le formulaire complet d'inscription est valide.
  static bool isRegistrationValid({
    required String? firstName,
    required String? lastName,
    required DateTime? birthDate,
    required String? email,
    required String? password,
    required String? confirmation,
    DateTime? now,
  }) =>
      AuthValidators.firstName(firstName) == null &&
      AuthValidators.lastName(lastName) == null &&
      AuthValidators.birthDate(birthDate, now: now) == null &&
      AuthValidators.email(email) == null &&
      AuthValidators.password(password) == null &&
      AuthValidators.passwordConfirmation(confirmation, password ?? '') == null;
}
