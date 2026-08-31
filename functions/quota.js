'use strict';

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {setGlobalOptions} = require('firebase-functions/v2/options');
const admin = require('firebase-admin');

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

setGlobalOptions({
  region: 'us-central1',
  timeoutSeconds: 60,
  memory: '512MiB',
});

const db = admin.firestore();
// Match the actual subcollections used by the app
const VALID_SECTIONS = new Set(['offers', 'requests', 'owners', 'offices', 'brokers', 'watchmen', 'quotations', 'scanner', 'signature', 'imageToPdf', 'combinePdfs']);

class QuotaExceededError extends Error {
  constructor(message, details) {
    super(message);
    this.name = 'QuotaExceededError';
    this.details = details;
  }
}

/**
 * Sanitizes item payload to prevent injection of reserved fields
 * @param {Object} rawPayload - The raw payload from client
 * @return {Object} Sanitized payload
 */
const sanitizeItemPayload = (rawPayload = {}) => {
  if (typeof rawPayload !== 'object' || Array.isArray(rawPayload) || rawPayload === null) {
    throw new HttpsError('invalid-argument', 'payload must be an object.');
  }

  const forbiddenKeys = ['ownerId', 'section', 'createdAt', 'updatedAt', 'id', 'counts', 'userId'];
  const cleaned = {};

  Object.entries(rawPayload).forEach(([key, value]) => {
    if (forbiddenKeys.includes(key)) {
      return;
    }
    cleaned[key] = value;
  });

  return cleaned;
};

/**
 * Cloud Function to add an item with quota enforcement
 * Implements server-side quota checks with idempotency and audit logging
 */
exports.addItemWithQuota = onCall(async (request) => {
  const {auth, data, rawRequest} = request;

  // Authentication check
  if (!auth || !auth.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }

  const uid = auth.uid;
  const section = data?.section;
  const idempotencyToken = data?.idempotencyToken;
  const payload = data?.payload;

  // Validate section
  if (typeof section !== 'string' || !VALID_SECTIONS.has(section)) {
    throw new HttpsError('invalid-argument', `Invalid or missing section. Must be one of: ${Array.from(VALID_SECTIONS).join(', ')}`);
  }

  // Validate idempotency token
  if (typeof idempotencyToken !== 'string' || idempotencyToken.length < 20) {
    throw new HttpsError('invalid-argument', 'A valid idempotencyToken (UUID) is required.');
  }

  // Sanitize payload
  const sanitizedPayload = sanitizeItemPayload(payload);

  const userRef = db.collection('users').doc(uid);
  const idempotencyRef = userRef.collection('idempotency_tokens').doc(idempotencyToken);
  const auditRef = db.collection('audit_logs').doc();

  try {
    // Run transaction to ensure atomicity
    const transactionResult = await db.runTransaction(async (tx) => {
      // Check idempotency first
      const idempotencySnap = await tx.get(idempotencyRef);
      if (idempotencySnap.exists) {
        return {
          replay: true,
          stored: idempotencySnap.data(),
        };
      }

      // Get user document
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw new HttpsError('failed-precondition', 'User profile is missing. Please complete account setup.');
      }

      const userData = userSnap.data() || {};
      const plan = typeof userData.plan === 'string' ? userData.plan : 'free';
      const quotaLimit = plan === 'premium' ? null : 3;

      // 🔒 SECURITY FIX: Check lifetime created count, not current count
      // This prevents users from deleting items to add new ones
      const lifetimeCreated = userData.lifetimeCreated || {};
      const lifetimeCount = lifetimeCreated[section] || 0;
      
      // Also count current items for display purposes
      let currentSectionCount = 0;
      if (quotaLimit !== null) {
        const itemsQuery = userRef.collection(section).count();
        const countSnap = await tx.get(itemsQuery);
        currentSectionCount = countSnap.data().count;
        
        console.log(`🔍 Lifetime created for ${uid}/${section}: ${lifetimeCount}`);
        console.log(`🔍 Current items for ${uid}/${section}: ${currentSectionCount}`);
      }

      // Check quota against LIFETIME count (not current count)
      if (quotaLimit !== null && lifetimeCount >= quotaLimit) {
        const rejectionData = {
          status: 'rejected',
          section,
          errorCode: 'resource-exhausted',
          errorMessage: 'Free plan quota reached for this section.',
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            plan,
            lifetimeCount,
            currentCount: currentSectionCount,
            quotaLimit,
            ip: rawRequest?.ip ?? null,
          },
        };

        const auditData = {
          eventType: 'item_create',
          outcome: 'rejected',
          reason: 'quota-exceeded',
          actorUid: uid,
          section,
          itemId: null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          metadata: {
            plan,
            lifetimeCount,
            currentCount: currentSectionCount,
            quotaLimit,
          },
        };

        // Store rejection for idempotency
        tx.set(idempotencyRef, rejectionData);
        tx.set(auditRef, auditData);

        throw new QuotaExceededError('Free plan quota reached.', {
          section,
          lifetimeCount,
          currentCount: currentSectionCount,
          quotaLimit,
        });
      }

      // Create item in user's subcollection
      const itemRef = userRef.collection(section).doc();
      const now = admin.firestore.FieldValue.serverTimestamp();

      const itemData = {
        ownerId: uid,
        section,
        ...sanitizedPayload,
        createdAt: now,
        updatedAt: now,
      };

      tx.set(itemRef, itemData);

      // Update user counts AND lifetime created counter
      const userUpdates = {
        [`counts.${section}`]: currentSectionCount + 1,
        [`lifetimeCreated.${section}`]: admin.firestore.FieldValue.increment(1),
        lastQuotaCheckAt: now,
        updatedAt: now,
      };
      tx.set(userRef, userUpdates, {merge: true});

      // Store success for idempotency
      const completionData = {
        status: 'completed',
        section,
        itemId: itemRef.id,
        createdAt: now,
        metadata: {
          plan,
          newCount: currentSectionCount + 1,
          lifetimeCount: lifetimeCount + 1,
          quotaLimit,
        },
      };

      // Audit log for success
      const auditData = {
        eventType: 'item_create',
        outcome: 'success',
        actorUid: uid,
        section,
        itemId: itemRef.id,
        createdAt: now,
        metadata: {
          plan,
          newCount: currentSectionCount + 1,
          lifetimeCount: lifetimeCount + 1,
          quotaLimit,
        },
      };

      tx.set(idempotencyRef, completionData);
      tx.set(auditRef, auditData);

      return {
        replay: false,
        stored: completionData,
      };
    });

    // Handle idempotent replay
    if (transactionResult.replay) {
      const stored = transactionResult.stored;
      if (stored.status === 'completed') {
        return {
          itemId: stored.itemId,
          section: stored.section,
          currentCount: stored.metadata?.newCount ?? null,
          quotaLimit: stored.metadata?.quotaLimit ?? null,
          replayed: true,
        };
      }
      if (stored.status === 'rejected') {
        throw new HttpsError(
          stored.errorCode || 'resource-exhausted',
          stored.errorMessage || 'Operation previously rejected.',
          stored.metadata || null,
        );
      }
      throw new HttpsError('aborted', 'Idempotency token is in an unknown state.');
    }

    // Return success result
    const stored = transactionResult.stored;
    return {
      itemId: stored.itemId,
      section: stored.section,
      currentCount: stored.metadata?.newCount ?? null,
      quotaLimit: stored.metadata?.quotaLimit ?? null,
      replayed: false,
    };
  } catch (error) {
    // Handle QuotaExceededError
    if (error instanceof QuotaExceededError) {
      console.warn('Quota exceeded for user', {
        uid,
        section,
        details: error.details,
      });
      const {section: sec, currentCount, quotaLimit} = error.details || {};
      throw new HttpsError(
        'resource-exhausted',
        'Free plan quota reached. Upgrade to continue.',
        {
          section: sec,
          currentCount,
          quotaLimit,
        },
      );
    }

    // Re-throw HttpsError
    if (error instanceof HttpsError) {
      throw error;
    }

    // Log unexpected errors
    console.error('addItemWithQuota failure', {
      uid: auth?.uid,
      section,
      message: error.message,
      stack: error.stack,
    });

    // Store error audit log
    try {
      await db.collection('audit_logs').add({
        eventType: 'item_create',
        outcome: 'error',
        actorUid: uid,
        section,
        itemId: null,
        reason: 'internal-error',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          message: error.message,
        },
      });
    } catch (auditError) {
      console.error('Failed to write audit log', auditError);
    }

    throw new HttpsError('internal', 'Unexpected server error.');
  }
});
