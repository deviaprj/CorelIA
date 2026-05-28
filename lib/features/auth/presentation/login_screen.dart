import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_notifier.dart';
import '../data/mock_auth_repository.dart';
import '../../../app/cofely_theme.dart';
import '../../../core/providers/firebase_providers.dart';
import '../../../main.dart' show isDemoMode;
import '../../../shared/extensions/string_extensions.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController(text: 'test@aironbot.app');
  final _passCtrl = TextEditingController(text: 'test1234');
  bool _isRegister = false;
  bool _obscurePass = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;

    // Validation
    if (email.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir tous les champs')),
      );
      return;
    }

    if (!email.isValidEmail) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Email invalide')),
      );
      return;
    }

    if (_isRegister && pass.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le mot de passe doit faire au moins 6 caractères')),
      );
      return;
    }

    if (_isRegister) {
      await ref
          .read(authNotifierProvider.notifier)
          .registerWithEmail(email, pass, 'Utilisateur');
    } else {
      await ref
          .read(authNotifierProvider.notifier)
          .signInWithEmail(email, pass);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    ref.listen(authNotifierProvider, (_, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    });

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF001218), CofelyTokens.primary],
            begin: Alignment.topCenter,
            end: Alignment.center,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ── En-tête Cofely ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                child: Column(
                  children: [
                    // Logo "C"
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: CofelyTokens.avatarGradient,
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'C',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Corely',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Votre assistant IA personnel',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 13,
                        color: Colors.white.withOpacity(0.65),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Carte formulaire ───────────────────────────────────────
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 24,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Titre formulaire
                        Text(
                          _isRegister ? 'Créer un compte' : 'Bon retour 👋',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.bold,
                                color: CofelyTokens.primary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 28),

                        // Badge compte de test
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: CofelyTokens.accent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: CofelyTokens.accent.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline,
                                  size: 15, color: CofelyTokens.accent),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Compte test : test@aironbot.app / test1234',
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    fontSize: 11.5,
                                    color: CofelyTokens.accent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Email
                        TextField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Mot de passe
                        TextField(
                          controller: _passCtrl,
                          obscureText: _obscurePass,
                          decoration: InputDecoration(
                            labelText: 'Mot de passe',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePass
                                    ? Icons.visibility_off
                                    : Icons.visibility,
                              ),
                              onPressed: () => setState(
                                  () => _obscurePass = !_obscurePass),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Bouton principal
                        FilledButton(
                          onPressed: isLoading ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: CofelyTokens.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isRegister ? "S'inscrire" : 'Se connecter',
                                  style: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),

                        // Google
                        OutlinedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () => ref
                                  .read(authNotifierProvider.notifier)
                                  .signInWithGoogle(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            side: BorderSide(
                                color: CofelyTokens.primary.withOpacity(0.4)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.g_mobiledata, size: 24),
                          label: const Text('Continuer avec Google'),
                        ),
                        const SizedBox(height: 8),

                        // Anonyme
                        TextButton(
                          onPressed: isLoading
                              ? null
                              : () => ref
                                  .read(authNotifierProvider.notifier)
                                  .signInAnonymously(),
                          child: Text(
                            'Continuer sans compte',
                            style: TextStyle(color: CofelyTokens.accent),
                          ),
                        ),
                        const SizedBox(height: 4),

                        // Mode test hors-ligne
                        OutlinedButton.icon(
                          onPressed: isLoading
                              ? null
                              : () async {
                                  isDemoMode = true;
                                  await mockAuthRepository.initialize();
                                  await mockAuthRepository.signInAnonymously();
                                  ref.invalidate(authStateProvider);
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                            side: const BorderSide(
                                color: Colors.orange, width: 0.8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.bug_report_outlined, size: 20),
                          label: const Text('Mode test (hors-ligne)'),
                        ),
                        const SizedBox(height: 24),

                        // Toggle register/login
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isRegister
                                  ? 'Déjà un compte ? '
                                  : "Pas encore de compte ? ",
                              style: const TextStyle(fontSize: 13),
                            ),
                            GestureDetector(
                              onTap: () => setState(
                                  () => _isRegister = !_isRegister),
                              child: Text(
                                _isRegister ? 'Se connecter' : "S'inscrire",
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  color: CofelyTokens.primary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
