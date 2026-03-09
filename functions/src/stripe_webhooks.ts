import * as admin from 'firebase-admin';
import { onRequest } from 'firebase-functions/v2/https';
import Stripe from 'stripe';

// ⚠️  Définir ces secrets via : firebase functions:secrets:set STRIPE_SECRET_KEY
//                                                    STRIPE_WEBHOOK_SECRET
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY ?? '', {
  apiVersion: '2023-10-16',
});

/**
 * HTTP Endpoint — webhook Stripe
 * URL : https://<region>-<project>.cloudfunctions.net/stripeWebhook
 *
 * Configure dans Stripe Dashboard → Webhooks → Add endpoint
 * Événements écoutés : checkout.session.completed, customer.subscription.deleted
 */
export const stripeWebhook = onRequest(
  { region: 'europe-west1' },
  async (req, res) => {
    const sig = req.headers['stripe-signature'];
    const webhookSecret = process.env.STRIPE_WEBHOOK_SECRET ?? '';

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,
        sig as string,
        webhookSecret
      );
    } catch (err) {
      console.error('Stripe webhook signature invalide :', err);
      res.status(400).send('Webhook Error: invalid signature');
      return;
    }

    const db = admin.firestore();

    switch (event.type) {
      case 'checkout.session.completed': {
        const session = event.data.object as Stripe.Checkout.Session;
        const uid = session.metadata?.['uid'];
        if (uid) {
          await db.collection('users').doc(uid).update({ plan: 'pro' });
          console.log(`Utilisateur ${uid} passé en Pro via Stripe.`);
        }
        break;
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription;
        const uid = sub.metadata?.['uid'];
        if (uid) {
          await db.collection('users').doc(uid).update({ plan: 'free' });
          console.log(`Utilisateur ${uid} rétrogradé en Free (annulation).`);
        }
        break;
      }

      default:
        console.log(`Événement Stripe ignoré : ${event.type}`);
    }

    res.json({ received: true });
  }
);
