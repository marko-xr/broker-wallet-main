/**
 * Cloud Function to sync user quota counts with actual Firestore data
 * This ensures counts always reflect reality, even after app reinstall
 */

const {onCall} = require("firebase-functions/v2/https");
const {getFirestore} = require("firebase-admin/firestore");
const admin = require("firebase-admin");

// Initialize Firebase Admin if not already initialized
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = getFirestore();

/**
 * Sync user's quota counts with actual data in Firestore
 * This function counts real items in each collection and updates the user's counts
 * 
 * Called when:
 * - User logs in (especially after app reinstall)
 * - User upgrades/downgrades plan
 * - Manual refresh requested
 * 
 * @returns {Object} Updated counts and user plan info
 */
exports.syncUserQuota = onCall(async (request) => {
  const userId = request.auth?.uid;
  
  if (!userId) {
    throw new Error("User must be authenticated");
  }

  try {
    console.log(`🔄 Syncing quota for user: ${userId}`);

    // Get user document to check plan
    const userDoc = await db.collection('users').doc(userId).get();
    const userData = userDoc.data() || {};
    const plan = userData.plan || 'free';

    console.log(`📋 User plan: ${plan}`);

    // Count actual items in each collection (SUBCOLLECTIONS under users/{uid})
    const counts = {
      offers: 0,
      requests: 0,
      owners: 0,
      offices: 0,
      brokers: 0,
      watchmen: 0,
      quotations: 0,
      scanner: 0,
      signature: 0,
      imageToPdf: 0,
      combinePdfs: 0,
    };

    const userRef = db.collection('users').doc(userId);

    // Count offers (subcollection)
    const offersSnapshot = await userRef.collection('offers')
      .count()
      .get();
    counts.offers = offersSnapshot.data().count;

    // Count requests (subcollection)
    const requestsSnapshot = await userRef.collection('requests')
      .count()
      .get();
    counts.requests = requestsSnapshot.data().count;

    // Count owners (subcollection)
    const ownersSnapshot = await userRef.collection('owners')
      .count()
      .get();
    counts.owners = ownersSnapshot.data().count;

    // Count offices (subcollection)
    const officesSnapshot = await userRef.collection('offices')
      .count()
      .get();
    counts.offices = officesSnapshot.data().count;

    // Count brokers (subcollection)
    const brokersSnapshot = await userRef.collection('brokers')
      .count()
      .get();
    counts.brokers = brokersSnapshot.data().count;

    // Count watchmen (subcollection)
    const watchmenSnapshot = await userRef.collection('watchmen')
      .count()
      .get();
    counts.watchmen = watchmenSnapshot.data().count;

    // Count quotations (subcollection)
    const quotationsSnapshot = await userRef.collection('quotations')
      .count()
      .get();
    counts.quotations = quotationsSnapshot.data().count;

    // Count scanner documents (subcollection)
    const scannerSnapshot = await userRef.collection('scanner')
      .count()
      .get();
    counts.scanner = scannerSnapshot.data().count;

    // Count signature documents (subcollection)
    const signatureSnapshot = await userRef.collection('signature')
      .count()
      .get();
    counts.signature = signatureSnapshot.data().count;

    // Count imageToPdf documents (subcollection)
    const imageToPdfSnapshot = await userRef.collection('imageToPdf')
      .count()
      .get();
    counts.imageToPdf = imageToPdfSnapshot.data().count;

    // Count combinePdfs documents (subcollection)
    const combinePdfsSnapshot = await userRef.collection('combinePdfs')
      .count()
      .get();
    counts.combinePdfs = combinePdfsSnapshot.data().count;

    console.log(`📊 Synced counts:`, counts);

    // Update user document with synced counts
    await db.collection('users').doc(userId).set({
      counts: counts,
      lastQuotaSync: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    // Calculate if user is at limit (for FREE users)
    const freeLimit = 3;
    const sectionsAtLimit = [];
    
    if (plan === 'free') {
      Object.keys(counts).forEach(section => {
        if (counts[section] >= freeLimit) {
          sectionsAtLimit.push(section);
        }
      });
    }

    console.log(`✅ Quota sync complete for user: ${userId}`);

    return {
      success: true,
      counts: counts,
      plan: plan,
      limit: plan === 'free' ? freeLimit : 'unlimited',
      sectionsAtLimit: sectionsAtLimit,
      message: "Quota synced successfully",
    };

  } catch (error) {
    console.error(`❌ Error syncing quota for user ${userId}:`, error);
    throw new Error(`Failed to sync quota: ${error.message}`);
  }
});

/**
 * Firestore trigger to auto-sync quota when user document is created/updated
 * This ensures counts are always accurate
 */
exports.onUserUpdate = require("firebase-functions/v2/firestore")
  .onDocumentWritten("users/{userId}", async (event) => {
    const userId = event.params.userId;
    const beforeData = event.data?.before?.data();
    const afterData = event.data?.after?.data();

    // Only sync if plan changed or document is newly created
    if (!beforeData || beforeData.plan !== afterData?.plan) {
      console.log(`🔄 Auto-syncing quota for user ${userId} due to plan change`);
      
      try {
        // Call the sync function internally
        // Note: We can't use onCall here, so we duplicate the logic
        const counts = {};
        const userRef = db.collection('users').doc(userId);
        
        // Count each collection (SUBCOLLECTIONS under users/{uid})...
        const offersSnapshot = await userRef.collection('offers')
          .count()
          .get();
        counts.offers = offersSnapshot.data().count;

        const requestsSnapshot = await userRef.collection('requests')
          .count()
          .get();
        counts.requests = requestsSnapshot.data().count;

        const ownersSnapshot = await userRef.collection('owners')
          .count()
          .get();
        counts.owners = ownersSnapshot.data().count;

        const officesSnapshot = await userRef.collection('offices')
          .count()
          .get();
        counts.offices = officesSnapshot.data().count;

        const brokersSnapshot = await userRef.collection('brokers')
          .count()
          .get();
        counts.brokers = brokersSnapshot.data().count;

        const watchmenSnapshot = await userRef.collection('watchmen')
          .count()
          .get();
        counts.watchmen = watchmenSnapshot.data().count;

        const quotationsSnapshot = await userRef.collection('quotations')
          .count()
          .get();
        counts.quotations = quotationsSnapshot.data().count;

        const scannerSnapshot = await userRef.collection('scanner')
          .count()
          .get();
        counts.scanner = scannerSnapshot.data().count;

        const signatureSnapshot = await userRef.collection('signature')
          .count()
          .get();
        counts.signature = signatureSnapshot.data().count;

        const imageToPdfSnapshot = await userRef.collection('imageToPdf')
          .count()
          .get();
        counts.imageToPdf = imageToPdfSnapshot.data().count;

        const combinePdfsSnapshot = await userRef.collection('combinePdfs')
          .count()
          .get();
        counts.combinePdfs = combinePdfsSnapshot.data().count;

        // Update counts
        await event.data.after.ref.set({
          counts: counts,
          lastQuotaSync: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        console.log(`✅ Auto-sync complete for user ${userId}`);
      } catch (error) {
        console.error(`❌ Error auto-syncing quota for user ${userId}:`, error);
      }
    }
  });
