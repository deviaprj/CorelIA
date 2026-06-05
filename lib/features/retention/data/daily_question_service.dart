import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tz;

/// Service de notification quotidienne "Corely Daily".
///
/// Envoie une notification locale tous les jours a 9h00
/// avec une question d'actualite ou un prompt interessant.
///
/// L'utilisateur peut appuyer sur la notification pour ouvrir
/// l'app directement sur le chat avec la question pre-remplie.
class DailyQuestionService {
  static const String _prefsKeyEnabled = 'daily_question_enabled';
  static const String _prefsKeyLastQuestion = 'daily_question_last';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialise le plugin de notifications locales.
  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _notifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        debugPrint('[DailyQuestion] Notification tapped: ${response.payload}');
      },
    );

    _initialized = true;
  }

  /// Active ou desactive la notification quotidienne.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, enabled);

    if (enabled) {
      await scheduleDailyNotification();
    } else {
      await _notifications.cancel(0);
    }
  }

  /// Verifie si la notification est activee.
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? false;
  }

  /// Programme la notification quotidienne a 9h00.
  Future<void> scheduleDailyNotification() async {
    await init();

    final question = _pickRandomQuestion();

    const androidDetails = AndroidNotificationDetails(
      'daily_question_channel',
      'Corely Daily',
      channelDescription: 'Votre question du jour pour rester productif',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      9, // 9h00
    );

    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _notifications.zonedSchedule(
      0, // id
      'Corely Daily',
      question,
      scheduled,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: question,
    );

    debugPrint('[DailyQuestion] Programme pour $scheduled : $question');
  }

  /// Envoie une notification de test immediatement.
  Future<void> sendTestNotification() async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'daily_question_channel',
      'Corely Daily',
      channelDescription: 'Votre question du jour pour rester productif',
      importance: Importance.high,
      priority: Priority.high,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      0,
      'Corely Daily (test)',
      _pickRandomQuestion(),
      details,
    );
  }

  /// Desactive toutes les notifications quotidiennes.
  Future<void> cancel() async {
    await _notifications.cancel(0);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, false);
  }

  /// Liste de questions quotidiennes en francais.
  static final List<String> _questions = [
    'Quelle est l\'actualite tech aujourd\'hui ?',
    'Resumes-moi les dernieres nouvelles en France.',
    'Quel est le cours du Bitcoin en ce moment ?',
    'Donne-moi 3 idees de recettes rapides pour ce soir.',
    'Quels sont les evenements ce week-end a Paris ?',
    'Traduis-moi une phrase en anglais pour un email pro.',
    'Aide-moi a rediger un message de motivation.',
    'Quelles sont les tendances mode de cette saison ?',
    'Donne-moi 5 exercices de sport sans materiel.',
    'Quel film recommandes-tu pour ce soir ?',
    'Resume-moi un article de ton choix.',
    'Quelle est la meteo de ce week-end ?',
    'Aide-moi a planifier mes vacances.',
    'Quels sont les meilleurs podcasts a ecouter ?',
    'Donne-moi des astuces de productivite.',
    'Quel est le score du dernier match de Ligue 1 ?',
    'Aide-moi a ecrire un poeme.',
    'Quelles sont les nouveautes Flutter cette semaine ?',
    'Donne-moi 3 idees de cadeaux originaux.',
    'Quels sont les signes astrologiques compatibles ?',
    'Resume-moi un livre que tu connais.',
    'Quelle est la difference entre IA et ML ?',
    'Aide-moi a preparer un entretien d\'embauche.',
    'Quels sont les meilleurs restaurants pres de moi ?',
    'Donne-moi un fait historique interessant.',
  ];

  String _pickRandomQuestion() {
    final index = math.Random().nextInt(_questions.length);
    final question = _questions[index];

    // Sauvegarder la derniere question pour eviter repetition immediate
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(_prefsKeyLastQuestion, question);
    });

    return question;
  }
}
