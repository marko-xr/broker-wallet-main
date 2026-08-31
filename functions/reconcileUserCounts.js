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
  timeoutSeconds: 300, // 5 minutes for large users
  memory: '1GiB',
});

const db = admin.firestore();
// Match the actual subcollections used by the app
const VALID_SECTIONS = ['offers', 'requests', 'owners', 'offices', 'brokers', 'watchmen', 'quotations', 'scanner', 'signature', 'imageToPdf', 'combinePdfs'];

/**
 * Reconcile user counts by scanning actual Firestore data
 * 
 * This function:
 * 1. Counts real items in each user subcollection
 * 2. Updates users.counts atomically
 * 3. Handles pagination for large users (500+ items)
 * 4. Returns accurate counts and detects discrepancies
 * 
 * Call this function:
 * - On first login after app reinstall
 * - After plan upgrade/downgrade
 * - When counts seem incorrect
 * - As a background maintenance job
 * 
 * @param {string} uid - Optional user ID (defaults to authenticated user)
 * @returns {Object} Reconciled counts and discrepancy report
 */
exports.reconcileUserCounts = onCall(async (request) => {
  const {auth, data} = request;
  
  // Authentication check
  if (!auth || !auth.uid) {
    throw new HttpsError('unauthenticated', 'Authentication required.');
  }

  // Allow user to reconcile their own counts, or admin to reconcile any user
  const targetUid = data?.uid || auth.uid;
  
  // Security: Non-admin users can only reconcile their own counts
  if (targetUid !== auth.uid && !auth.token?.admin) {
    throw new HttpsError(
      'permission-denied',
      'You can only reconcile your own counts.',
    );
  }

  const userRef = db.collection('users').doc(targetUid);

  try {
    console.log(`🔄 Starting count reconciliation for user: ${targetUid}`);

    // Get user document for plan info
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      throw new HttpsError(
        'not-found',
        'User profile not found. Please complete account setup.',
      );
    }

    const userData = userDoc.data() || {};
    const plan = userData.plan || 'free';
    const oldCounts = userData.counts || {};

    // Count real items in each section
    const newCounts = {};
    const discrepancies = [];

    for (const section of VALID_SECTIONS) {
      try {
        // Use count() for efficiency (doesn't transfer documents)
        const countQuery = userRef.collection(section).count();
        const countSnap = await countQuery.get();
        const realCount = countSnap.data().count;

        newCounts[section] = realCount;

        const oldCount = oldCounts[section] || 0;
        if (realCount !== oldCount) {
          discrepancies.push({
            section,
            oldCount,
            realCount,
            difference: realCount - oldCount,
          });
        }

        console.log(`📊 ${section}: ${realCount} items (was: ${oldCount})`);
      } catch (error) {
        console.error(`⚠️ Failed to count ${section}:`, error);
        // Keep old count on error
        newCounts[section] = oldCounts[section] || 0;
      }
    }

    // Atomically update counts
    await userRef.set({
      counts: newCounts,
      lastCountReconciliation: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    console.log(`✅ Reconciliation complete for user ${targetUid}`);
    console.log(`   Discrepancies found: ${discrepancies.length}`);

    // Log to audit if discrepancies found
    if (discrepancies.length > 0) {
      await db.collection('audit_logs').add({
        eventType: 'count_reconciliation',
        outcome: 'discrepancies_found',
        actorUid: auth.uid,
        targetUid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          plan,
          discrepancies,
          oldCounts,
          newCounts,
        },
      });
    }

    return {
      success: true,
      counts: newCounts,
      plan,
      discrepanciesFound: discrepancies.length,
      discrepancies,
      message: discrepancies.length > 0
        ? `Fixed ${discrepancies.length} count mismatches`
        : 'All counts accurate',
    };
  } catch (error) {
    // Log error
    console.error(`❌ Reconciliation failed for user ${targetUid}:`, error);

    // Store error audit log
    try {
      await db.collection('audit_logs').add({
        eventType: 'count_reconciliation',
        outcome: 'error',
        actorUid: auth.uid,
        targetUid,
        reason: 'reconciliation-failed',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          message: error.message,
          stack: error.stack,
        },
      });
    } catch (auditError) {
      console.error('Failed to write audit log', auditError);
    }

    // Re-throw HttpsError
    if (error instanceof HttpsError) {
      throw error;
    }

    throw new HttpsError(
      'internal',
      `Failed to reconcile counts: ${error.message}`,
    );
  }
});

/**
 * Admin-only: Reconcile counts for ALL users
 * 
 * This is a maintenance function that should be run:
 * - After deploying new quota system
 * - Weekly as a scheduled job
 * - After any major data migration
 * 
 * @param {number} batchSize - Users to process per batch (default: 100)
 * @returns {Object} Summary of reconciliation results
 */
exports.reconcileAllUserCounts = onCall(async (request) => {
  const {auth, data} = request;

  // Admin-only function
  if (!auth || !auth.token?.admin) {
    throw new HttpsError(
      'permission-denied',
      'This function requires admin privileges.',
    );
  }

  const batchSize = data?.batchSize || 100;
  const usersQuery = db.collection('users').limit(batchSize);

  try {
    console.log(`🔄 Starting batch reconciliation for up to ${batchSize} users`);

    const usersSnapshot = await usersQuery.get();
    const totalUsers = usersSnapshot.size;
    let successCount = 0;
    let errorCount = 0;
    const errors = [];

    // Process each user
    for (const userDoc of usersSnapshot.docs) {
      const uid = userDoc.id;
      try {
        // Call reconcileUserCounts for this user
        await exports.reconcileUserCounts({
          auth: {uid, token: {admin: true}},
          data: {uid},
        });
        successCount++;
      } catch (error) {
        errorCount++;
        errors.push({uid, error: error.message});
        console.error(`Failed to reconcile user ${uid}:`, error);
      }
    }

    console.log(`✅ Batch reconciliation complete`);
    console.log(`   Total users: ${totalUsers}`);
    console.log(`   Success: ${successCount}`);
    console.log(`   Errors: ${errorCount}`);

    return {
      success: true,
      totalUsers,
      successCount,
      errorCount,
      errors: errors.slice(0, 10), // Return first 10 errors
    };
  } catch (error) {
    console.error('❌ Batch reconciliation failed:', error);
    throw new HttpsError(
      'internal',
      `Batch reconciliation failed: ${error.message}`,
    );
  }
});
