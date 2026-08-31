'use strict';

/**
 * Production Notification System for Broker Wallet
 * 
 * This module handles real-time notifications for:
 * 1. Match notifications - When offers match request criteria
 * 2. Plan alerts - Quota warnings, subscription expiring
 * 3. Reminder notifications - Active requests, available offers
 * 4. System updates - New app versions
 */

const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2/options');
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
const messaging = admin.messaging();

// ============================================================================
// NOTIFICATION CATEGORIES
// ============================================================================
const NOTIFICATION_CATEGORIES = {
  MATCH: 'match',
  PLAN: 'plan',
  REMINDER: 'reminder',
  SYSTEM: 'system',
};

// ============================================================================
// 1. MATCH NOTIFICATIONS - Triggered when offers/requests are created
// ============================================================================

/**
 * When a new offer is created, check if it matches any active requests
 */
exports.checkOfferMatchesRequests = onDocumentCreated(
  'users/{userId}/offers/{offerId}',
  async (event) => {
    const offer = event.data?.data();
    const userId = event.params.userId;
    const offerId = event.params.offerId;

    if (!offer) {
      console.log('No offer data found');
      return null;
    }

    console.log(`🔍 Checking matches for new offer: ${offerId}`);

    try {
      // Get all active requests for this user
      const requestsSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('requests')
        .where('status', 'in', ['active', 'Active'])
        .get();

      if (requestsSnapshot.empty) {
        console.log('No active requests to match against');
        return null;
      }

      // Check each request for matches
      for (const requestDoc of requestsSnapshot.docs) {
        const request = requestDoc.data();
        const matchScore = calculateMatchScore(request, offer);

        if (matchScore >= 0.6) { // 60% or higher match
          console.log(`✅ Match found! Request ${requestDoc.id} matches offer ${offerId} with score ${matchScore}`);
          
          await createMatchNotification(
            userId,
            requestDoc.id,
            offerId,
            matchScore,
            offer,
            request
          );
        }
      }

      return null;
    } catch (error) {
      console.error('Error checking offer matches:', error);
      return null;
    }
  }
);

/**
 * When a new request is created, check if it matches any existing offers
 */
exports.checkRequestMatchesOffers = onDocumentCreated(
  'users/{userId}/requests/{requestId}',
  async (event) => {
    const request = event.data?.data();
    const userId = event.params.userId;
    const requestId = event.params.requestId;

    if (!request) {
      console.log('No request data found');
      return null;
    }

    console.log(`🔍 Checking matches for new request: ${requestId}`);

    try {
      // Get all active offers for this user
      const offersSnapshot = await db
        .collection('users')
        .doc(userId)
        .collection('offers')
        .where('status', 'in', ['active', 'Active', 'available', 'Available'])
        .get();

      if (offersSnapshot.empty) {
        console.log('No active offers to match against');
        return null;
      }

      // Check each offer for matches
      for (const offerDoc of offersSnapshot.docs) {
        const offer = offerDoc.data();
        const matchScore = calculateMatchScore(request, offer);

        if (matchScore >= 0.6) { // 60% or higher match
          console.log(`✅ Match found! Offer ${offerDoc.id} matches request ${requestId} with score ${matchScore}`);
          
          await createMatchNotification(
            userId,
            requestId,
            offerDoc.id,
            matchScore,
            offer,
            request
          );
        }
      }

      return null;
    } catch (error) {
      console.error('Error checking request matches:', error);
      return null;
    }
  }
);

/**
 * Calculate match score between a request and an offer
 */
function calculateMatchScore(request, offer) {
  let score = 0;
  let totalCriteria = 0;

  // 1. Type match (rent vs sell) - mandatory
  if (request.requestType && offer.offerType) {
    totalCriteria++;
    if (request.requestType.toLowerCase() === offer.offerType.toLowerCase()) {
      score += 1;
    } else {
      return 0; // Type mismatch = no match
    }
  }

  // 2. Property type match
  if (request.propertyType && offer.propertyType) {
    totalCriteria++;
    if (request.propertyType.toLowerCase() === offer.propertyType.toLowerCase()) {
      score += 1;
    }
  }

  // 3. Location match (partial string match)
  if (request.location && offer.location) {
    totalCriteria++;
    const reqLocation = request.location.toLowerCase();
    const offerLocation = offer.location.toLowerCase();
    if (reqLocation.includes(offerLocation) || offerLocation.includes(reqLocation)) {
      score += 1;
    } else if (reqLocation.split(' ').some(word => offerLocation.includes(word))) {
      score += 0.5; // Partial match
    }
  }

  // 4. Budget match (offer price within request budget range)
  if (offer.price) {
    totalCriteria++;
    const minBudget = request.budgetMin || 0;
    const maxBudget = request.budgetMax || Number.MAX_SAFE_INTEGER;
    
    if (offer.price >= minBudget && offer.price <= maxBudget) {
      score += 1;
    } else if (offer.price >= minBudget * 0.9 && offer.price <= maxBudget * 1.1) {
      score += 0.5; // Within 10% tolerance
    }
  }

  // 5. Rooms match
  if (request.rooms && offer.rooms) {
    totalCriteria++;
    if (offer.rooms >= request.rooms) {
      score += 1;
    } else if (offer.rooms >= request.rooms - 1) {
      score += 0.5; // 1 room less is acceptable
    }
  }

  // 6. Bathrooms match
  if (request.bathrooms && offer.bathrooms) {
    totalCriteria++;
    if (offer.bathrooms >= request.bathrooms) {
      score += 1;
    }
  }

  return totalCriteria > 0 ? score / totalCriteria : 0;
}

/**
 * Create a match notification
 */
async function createMatchNotification(userId, requestId, offerId, matchScore, offer, request) {
  const notificationId = `match_${requestId}_${offerId}`;
  
  // Check if this match notification already exists
  const existingNotif = await db
    .collection('users')
    .doc(userId)
    .collection('notifications')
    .doc(notificationId)
    .get();

  if (existingNotif.exists) {
    console.log(`Match notification already exists for ${notificationId}`);
    return;
  }

  const notification = {
    title: 'New Match Found!',
    body: `An offer matches your ${request.propertyType || 'property'} request in ${request.location || 'your area'}. Tap to view details.`,
    category: NOTIFICATION_CATEGORIES.MATCH,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    data: {
      type: 'match',
      matchScore: matchScore,
    },
    actionRoute: '/match-details',
    offerId: offerId,
    requestId: requestId,
    matchScore: matchScore,
  };

  await db
    .collection('users')
    .doc(userId)
    .collection('notifications')
    .doc(notificationId)
    .set(notification);

  // Send push notification
  await sendPushNotification(userId, notification);

  console.log(`📬 Match notification created: ${notificationId}`);
}

// ============================================================================
// 2. PLAN ALERTS - Quota warnings and subscription status
// ============================================================================

/**
 * Triggered when user's counts are updated - check quota thresholds
 */
exports.checkQuotaThresholds = onDocumentUpdated(
  'users/{userId}',
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    const userId = event.params.userId;

    if (!before || !after) return null;

    const plan = after.plan || 'free';
    if (plan !== 'free') return null; // Premium users don't need quota alerts

    const FREE_LIMIT = 3;
    const counts = after.counts || {};
    const beforeCounts = before.counts || {};

    // Check each section for quota warnings
    const sections = ['offers', 'requests', 'owners', 'offices', 'brokers', 'watchmen'];
    
    for (const section of sections) {
      const currentCount = counts[section] || 0;
      const previousCount = beforeCounts[section] || 0;

      // Alert when reaching 2/3 items (1 remaining)
      if (currentCount === 2 && previousCount < 2) {
        await createPlanAlertNotification(
          userId,
          `oneSlotRemaining_${section}`,
          'Plan Alert: 1 Slot Remaining',
          `You have 1 slot remaining in ${section}. Upgrade to Premium for unlimited access.`,
          { section, remaining: 1 }
        );
      }

      // Alert when reaching limit
      if (currentCount >= FREE_LIMIT && previousCount < FREE_LIMIT) {
        await createPlanAlertNotification(
          userId,
          `limitReached_${section}`,
          'Plan Alert: Limit Reached',
          `You've reached the limit for ${section}. Upgrade to Premium to add more.`,
          { section, remaining: 0 }
        );
      }
    }

    return null;
  }
);

/**
 * Check for expiring subscriptions - runs daily at 9 AM UTC
 */
exports.checkExpiringSubscriptions = onSchedule(
  {
    schedule: '0 9 * * *', // Daily at 9 AM UTC
    timeZone: 'UTC',
  },
  async (event) => {
    console.log('🔔 Running subscription expiry check...');

    const now = admin.firestore.Timestamp.now();
    const sevenDaysFromNow = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
    );
    const threeDaysFromNow = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 3 * 24 * 60 * 60 * 1000)
    );
    const oneDayFromNow = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() + 24 * 60 * 60 * 1000)
    );

    // Find users with expiring subscriptions
    const expiringUsers = await db
      .collection('users')
      .where('subscription.isActive', '==', true)
      .where('subscription.expiresAt', '<=', sevenDaysFromNow)
      .where('subscription.expiresAt', '>', now)
      .get();

    for (const userDoc of expiringUsers.docs) {
      const userData = userDoc.data();
      const expiresAt = userData.subscription?.expiresAt?.toDate();
      
      if (!expiresAt) continue;

      const daysUntilExpiry = Math.ceil((expiresAt - Date.now()) / (24 * 60 * 60 * 1000));
      
      let notificationId;
      let title;
      let body;

      if (daysUntilExpiry <= 1) {
        notificationId = `subscription_expiring_1day_${userDoc.id}`;
        title = 'Subscription Expires Tomorrow!';
        body = 'Your Premium subscription expires tomorrow. Renew now to keep unlimited access.';
      } else if (daysUntilExpiry <= 3) {
        notificationId = `subscription_expiring_3days_${userDoc.id}`;
        title = 'Subscription Expiring Soon';
        body = `Your Premium subscription expires in ${daysUntilExpiry} days. Renew to maintain unlimited access.`;
      } else if (daysUntilExpiry <= 7) {
        notificationId = `subscription_expiring_7days_${userDoc.id}`;
        title = 'Subscription Reminder';
        body = `Your Premium subscription expires in ${daysUntilExpiry} days.`;
      }

      if (notificationId) {
        await createPlanAlertNotification(
          userDoc.id,
          notificationId,
          title,
          body,
          { daysUntilExpiry, expiresAt: expiresAt.toISOString() }
        );
      }
    }

    console.log(`✅ Processed ${expiringUsers.size} users with expiring subscriptions`);
    return null;
  }
);

async function createPlanAlertNotification(userId, notificationId, title, body, data) {
  // Check if notification already sent today
  const existingNotif = await db
    .collection('users')
    .doc(userId)
    .collection('notifications')
    .doc(notificationId)
    .get();

  if (existingNotif.exists) {
    const createdAt = existingNotif.data()?.createdAt?.toDate();
    if (createdAt && (Date.now() - createdAt.getTime()) < 24 * 60 * 60 * 1000) {
      console.log(`Plan alert already sent today: ${notificationId}`);
      return;
    }
  }

  const notification = {
    title,
    body,
    category: NOTIFICATION_CATEGORIES.PLAN,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    data: { type: 'plan', ...data },
    actionRoute: '/my-plan',
  };

  await db
    .collection('users')
    .doc(userId)
    .collection('notifications')
    .doc(notificationId)
    .set(notification);

  await sendPushNotification(userId, notification);

  console.log(`📬 Plan alert notification created: ${notificationId}`);
}

// ============================================================================
// 3. REMINDER NOTIFICATIONS - Active requests and available offers
// ============================================================================

/**
 * Send reminders for items not updated in 7+ days - runs daily at 10 AM UTC
 */
exports.sendItemReminders = onSchedule(
  {
    schedule: '0 10 * * *', // Daily at 10 AM UTC
    timeZone: 'UTC',
  },
  async (event) => {
    console.log('🔔 Running item reminders check...');

    const sevenDaysAgo = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 7 * 24 * 60 * 60 * 1000)
    );

    const usersSnapshot = await db.collection('users').limit(500).get();

    for (const userDoc of usersSnapshot.docs) {
      const userId = userDoc.id;

      // Check active requests not updated in 7+ days
      const oldRequests = await db
        .collection('users')
        .doc(userId)
        .collection('requests')
        .where('status', 'in', ['active', 'Active'])
        .where('updatedAt', '<', sevenDaysAgo)
        .limit(3)
        .get();

      for (const requestDoc of oldRequests.docs) {
        const request = requestDoc.data();
        await createReminderNotification(
          userId,
          `reminder_request_${requestDoc.id}`,
          'Request Follow-Up Reminder',
          `Your ${request.propertyType || 'property'} request in ${request.location || 'your area'} hasn't been updated in over a week. Update or mark as found.`,
          'request',
          requestDoc.id,
          null
        );
      }

      // Check available offers not updated in 7+ days
      const oldOffers = await db
        .collection('users')
        .doc(userId)
        .collection('offers')
        .where('status', 'in', ['active', 'Active', 'available', 'Available'])
        .where('updatedAt', '<', sevenDaysAgo)
        .limit(3)
        .get();

      for (const offerDoc of oldOffers.docs) {
        const offer = offerDoc.data();
        await createReminderNotification(
          userId,
          `reminder_offer_${offerDoc.id}`,
          'Offer Follow-Up Reminder',
          `Your ${offer.propertyType || 'property'} offer "${offer.title || 'property'}" hasn't been updated in over a week. Update availability status.`,
          'offer',
          null,
          offerDoc.id
        );
      }
    }

    console.log('✅ Item reminders check complete');
    return null;
  }
);

async function createReminderNotification(userId, notificationId, title, body, itemType, requestId, offerId) {
  // Don't spam - check if reminder sent in last 3 days
  const existingNotif = await db
    .collection('users')
    .doc(userId)
    .collection('notifications')
    .doc(notificationId)
    .get();

  if (existingNotif.exists) {
    const createdAt = existingNotif.data()?.createdAt?.toDate();
    if (createdAt && (Date.now() - createdAt.getTime()) < 3 * 24 * 60 * 60 * 1000) {
      return; // Don't send if reminder sent within 3 days
    }
  }

  const notification = {
    title,
    body,
    category: NOTIFICATION_CATEGORIES.REMINDER,
    isRead: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    data: { type: 'reminder', itemType },
    actionRoute: itemType === 'offer' ? '/offers-details-by-id' : '/requested-details-by-id',
    requestId: requestId,
    offerId: offerId,
  };

  await db
    .collection('users')
    .doc(userId)
    .collection('notifications')
    .doc(notificationId)
    .set(notification);

  await sendPushNotification(userId, notification);

  console.log(`📬 Reminder notification created: ${notificationId}`);
}

// ============================================================================
// 4. SYSTEM UPDATE NOTIFICATIONS
// ============================================================================

/**
 * Callable function to broadcast system update notification to all users
 * Should be called from admin dashboard or CI/CD pipeline
 */
exports.sendSystemUpdateNotification = onCall(
  { cors: true },
  async (request) => {
    // Verify admin caller (add proper admin check in production)
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Must be authenticated');
    }

    const { version, title, body, storeUrl, mandatory } = request.data;

    if (!version || !title || !body) {
      throw new HttpsError('invalid-argument', 'version, title, and body are required');
    }

    console.log(`📢 Broadcasting system update notification for version ${version}`);

    // Update app_config with latest version
    await db.collection('app_config').doc('latest_version').set({
      version,
      releaseDate: admin.firestore.FieldValue.serverTimestamp(),
      mandatory: mandatory || false,
      storeUrl: storeUrl || null,
    });

    // Get all users (in production, use pagination for large user bases)
    const usersSnapshot = await db.collection('users').limit(1000).get();
    let sentCount = 0;

    for (const userDoc of usersSnapshot.docs) {
      const notificationId = `system_update_${version}`;
      
      const notification = {
        title,
        body,
        category: NOTIFICATION_CATEGORIES.SYSTEM,
        isRead: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        data: { 
          type: 'system_update',
          version,
          mandatory: mandatory || false,
          storeUrl: storeUrl || null,
        },
      };

      await db
        .collection('users')
        .doc(userDoc.id)
        .collection('notifications')
        .doc(notificationId)
        .set(notification);

      await sendPushNotification(userDoc.id, notification);
      sentCount++;
    }

    console.log(`✅ System update notification sent to ${sentCount} users`);
    return { success: true, sentCount };
  }
);

/**
 * Check for app updates on user login - callable from client
 */
exports.checkAppUpdate = onCall(
  { cors: true },
  async (request) => {
    const { currentVersion } = request.data;

    if (!currentVersion) {
      throw new HttpsError('invalid-argument', 'currentVersion is required');
    }

    const latestVersionDoc = await db.collection('app_config').doc('latest_version').get();
    
    if (!latestVersionDoc.exists) {
      return { updateAvailable: false };
    }

    const latestData = latestVersionDoc.data();
    const latestVersion = latestData?.version;
    const mandatory = latestData?.mandatory || false;
    const storeUrl = latestData?.storeUrl;

    if (!latestVersion) {
      return { updateAvailable: false };
    }

    const updateAvailable = compareVersions(currentVersion, latestVersion) < 0;

    return {
      updateAvailable,
      latestVersion,
      mandatory,
      storeUrl,
    };
  }
);

function compareVersions(v1, v2) {
  const parts1 = v1.split('.').map(Number);
  const parts2 = v2.split('.').map(Number);

  for (let i = 0; i < Math.max(parts1.length, parts2.length); i++) {
    const p1 = parts1[i] || 0;
    const p2 = parts2[i] || 0;
    if (p1 < p2) return -1;
    if (p1 > p2) return 1;
  }
  return 0;
}

// ============================================================================
// PUSH NOTIFICATION HELPER
// ============================================================================

async function sendPushNotification(userId, notification) {
  try {
    // Get user's FCM tokens
    const tokensSnapshot = await db
      .collection('users')
      .doc(userId)
      .collection('fcmTokens')
      .get();

    if (tokensSnapshot.empty) {
      console.log(`No FCM tokens for user ${userId}`);
      return;
    }

    const tokens = tokensSnapshot.docs.map(doc => doc.id);

    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        category: notification.category,
        actionRoute: notification.actionRoute || '',
        offerId: notification.offerId || '',
        requestId: notification.requestId || '',
        matchScore: notification.matchScore?.toString() || '',
      },
      tokens: tokens,
    };

    const response = await messaging.sendEachForMulticast(message);
    
    // Clean up invalid tokens
    if (response.failureCount > 0) {
      const failedTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push(tokens[idx]);
        }
      });

      // Remove invalid tokens
      for (const token of failedTokens) {
        await db
          .collection('users')
          .doc(userId)
          .collection('fcmTokens')
          .doc(token)
          .delete();
      }
    }

    console.log(`📤 Push notification sent to ${response.successCount}/${tokens.length} devices`);
  } catch (error) {
    console.error('Error sending push notification:', error);
  }
}
