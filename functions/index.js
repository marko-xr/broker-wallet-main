/**
 * Import function triggers from their respective submodules:
 *
 * const {onCall} = require("firebase-functions/v2/https");
 * const {onDocumentWritten} = require("firebase-functions/v2/firestore");
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/https");
const logger = require("firebase-functions/logger");

// For cost control, you can set the maximum number of containers that can be
// running at the same time. This helps mitigate the impact of unexpected
// traffic spikes by instead downgrading performance. This limit is a
// per-function limit. You can override the limit for each function using the
// `maxInstances` option in the function's options, e.g.
// `onRequest({ maxInstances: 5 }, (req, res) => { ... })`.
// NOTE: setGlobalOptions does not apply to functions using the v1 API. V1
// functions should each use functions.runWith({ maxInstances: 10 }) instead.
// In the v1 API, each function can only serve one request per container, so
// this will be the maximum concurrent request count.
setGlobalOptions({ maxInstances: 10 });

// Import transcoding functions (temporarily disabled due to v2 API issues)
// const {
//   transcodeToHLS,
//   getTranscodingStatus,
//   cleanupTranscodingJob,
//   onTranscodingComplete,
//   cleanupOldTranscodingJobs,
// } = require('./transcoding');

// Import quota functions
const {
  addItemWithQuota,
} = require('./quota');

// Import sync quota functions
const {
  syncUserQuota,
  onUserUpdate,
} = require('./syncUserQuota');

// Import reconciliation functions
const {
  reconcileUserCounts,
  reconcileAllUserCounts,
} = require('./reconcileUserCounts');

// Import notification functions
const {
  checkOfferMatchesRequests,
  checkRequestMatchesOffers,
  checkQuotaThresholds,
  checkExpiringSubscriptions,
  sendItemReminders,
  sendSystemUpdateNotification,
  checkAppUpdate,
} = require('./notifications');

// Export transcoding functions (temporarily disabled)
// exports.transcodeToHLS = transcodeToHLS;
// exports.getTranscodingStatus = getTranscodingStatus;
// exports.cleanupTranscodingJob = cleanupTranscodingJob;
// exports.onTranscodingComplete = onTranscodingComplete;
// exports.cleanupOldTranscodingJobs = cleanupOldTranscodingJobs;

// Export quota functions
exports.addItemWithQuota = addItemWithQuota;

// Export sync quota functions
exports.syncUserQuota = syncUserQuota;
exports.onUserUpdate = onUserUpdate;

// Export reconciliation functions
exports.reconcileUserCounts = reconcileUserCounts;
exports.reconcileAllUserCounts = reconcileAllUserCounts;

// Export notification functions
exports.checkOfferMatchesRequests = checkOfferMatchesRequests;
exports.checkRequestMatchesOffers = checkRequestMatchesOffers;
exports.checkQuotaThresholds = checkQuotaThresholds;
exports.checkExpiringSubscriptions = checkExpiringSubscriptions;
exports.sendItemReminders = sendItemReminders;
exports.sendSystemUpdateNotification = sendSystemUpdateNotification;
exports.checkAppUpdate = checkAppUpdate;

// Create and deploy your first functions
// https://firebase.google.com/docs/functions/get-started

// exports.helloWorld = onRequest((request, response) => {
//   logger.info("Hello logs!", {structuredData: true});
//   response.send("Hello from Firebase!");
// });
