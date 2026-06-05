import * as admin from 'firebase-admin';

admin.initializeApp();

// Exporter toutes les fonctions
export { checkQuota } from './quotas';
export { stripeWebhook } from './stripe_webhooks';
