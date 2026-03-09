import * as admin from 'firebase-admin';
import { onCall, HttpsError } from 'firebase-functions/v2/https';

const FREE_DAILY_LIMIT = 20;

/**
 * Callable Function — vérifie et décrémente le quota journalier de l'utilisateur.
 *
 * Retourne : { remaining: number }
 * Lève resource-exhausted si quota épuisé.
 */
export const checkQuota = onCall(
  { region: 'europe-west1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Authentification requise.');
    }

    const uid = request.auth.uid;
    const userRef = admin.firestore().collection('users').doc(uid);

    const result = await admin.firestore().runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists) {
        throw new HttpsError('not-found', 'Utilisateur introuvable.');
      }

      const data = snap.data()!;
      const plan: string = data['plan'] ?? 'free';

      // Les utilisateurs Pro ne sont pas limités
      if (plan === 'pro') return { remaining: -1 };

      const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
      const storedDate: string = data['dailyRequestsDate'] ?? '';
      let daily: number = storedDate === today ? (data['dailyRequests'] ?? 0) : 0;

      if (daily >= FREE_DAILY_LIMIT) {
        throw new HttpsError(
          'resource-exhausted',
          `Quota journalier de ${FREE_DAILY_LIMIT} requêtes atteint.`
        );
      }

      daily++;
      tx.update(userRef, {
        dailyRequests: daily,
        dailyRequestsDate: today,
        totalRequests: admin.firestore.FieldValue.increment(1),
      });

      return { remaining: FREE_DAILY_LIMIT - daily };
    });

    return result;
  }
);
