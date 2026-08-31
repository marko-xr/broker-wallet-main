# Notification System Test Guide

## Overview
This guide helps you test and verify the complete notification system implementation in Broker Wallet.

## Components Tested

### ✅ Already Implemented:
1. **NotificationService** - Handles FCM tokens, permissions, and local notifications
2. **NotificationRepository** - Firestore CRUD operations for notifications
3. **NotificationViewModel** - State management for notification list
4. **NotificationModel** - Data model with categories (match, reminder, quota, system, general)
5. **UI Screens**:
   - Notifications List View (with localization)
   - Notification Settings View (with localization)
   - Notification Test View (NEW - for testing)

### 📋 Firestore Structure:
```
users/{userId}/
  ├── notifications/{notificationId}
  │   ├── title: string
  │   ├── body: string
  │   ├── category: string (match|reminder|quota|system|general)
  │   ├── isRead: boolean
  │   ├── createdAt: timestamp
  │   ├── data: map
  │   ├── actionRoute: string (optional)
  │   ├── offerId: string (optional)
  │   ├── requestId: string (optional)
  │   └── matchScore: number (optional)
  │
  └── fcmTokens/{token}
      ├── platform: string (android|ios)
      ├── updatedAt: timestamp
      ├── deviceName: string (optional)
      └── locale: string (optional)
```

## Testing Steps

### Step 1: Access Test Screen
1. Run the app: `flutter run`
2. Navigate to the test screen in one of these ways:
   - **Option A**: Add a debug button in Profile screen
   - **Option B**: Navigate directly via URL: `/notification-test`
   - **Option C**: Use the terminal command while app is running:
     ```dart
     // In Dart DevTools console or debug breakpoint:
     Navigator.of(context).pushNamed('/notification-test');
     ```

### Step 2: Test Notification Permissions
1. Open the Notification Test View
2. Check current **Permission Status** (should show current state)
3. Click **"Request Permission"** button
4. Grant notification permission when prompted
5. Verify permission status changes to "authorized"

### Step 3: Test FCM Token
1. Check the **FCM Token** in the Status card
2. It should display a long alphanumeric string
3. Click on the token row to copy it to clipboard
4. Click **"Sync FCM Token"** to save it to Firestore
5. Verify success message appears

### Step 4: Test Firestore Integration
1. Click **"Check Firestore Notifications"**
2. Initially should show "No notifications found"
3. This confirms Firestore read permissions are working

### Step 5: Create Test Notifications
1. Click each notification type button:
   - ✅ **Match Notification** - Simulates offer/request match
   - ✅ **Reminder Notification** - Simulates follow-up reminder
   - ✅ **Quota Notification** - Simulates quota limit alert
   - ✅ **System Notification** - Simulates system update
   - ✅ **General Notification** - Simulates general alert

2. After clicking each button:
   - Check the **Activity Log** for success messages
   - Verify "Notification created successfully!" appears

3. Click **"Check Firestore Notifications"** again
4. Should now show the count of created notifications

### Step 6: View Notifications in App
1. Navigate back to home
2. Open the **Notifications** screen (from profile or navigation)
3. Verify all test notifications appear in the list
4. Check that:
   - Icons are correct for each category
   - Titles and bodies are displayed
   - Time stamps show correctly (e.g., "Just now")
   - Unread notifications are highlighted

### Step 7: Test Notification Actions
1. Tap on a notification
2. Verify it marks as read (color changes)
3. Test "Mark all read" button
4. Swipe to dismiss a notification
5. Test pull-to-refresh

### Step 8: Test Notification Settings
1. Navigate to **Notification Settings** from Profile
2. Toggle "Enable notifications" master switch
3. Toggle individual notification types
4. Toggle push/email channels
5. Verify settings persist after app restart

## Firebase Console Verification

### Check Firestore Data:
1. Open Firebase Console → Firestore Database
2. Navigate to: `users/{your-uid}/notifications`
3. Verify test notifications are stored with correct structure
4. Check: `users/{your-uid}/fcmTokens`
5. Verify your device token is stored

### Check Firebase Cloud Messaging (Optional):
1. Open Firebase Console → Cloud Messaging
2. Click "Send test message"
3. Paste your FCM token (copied from test screen)
4. Enter title and body
5. Click "Test" to send
6. Verify notification appears on device

## Firestore Security Rules

### Current Rules (Already Implemented):
```javascript
// Notifications subcollection - user can read/write their own
match /users/{userId}/notifications/{notificationId} {
  allow read: if request.auth != null && request.auth.uid == userId;
  allow write: if request.auth != null && request.auth.uid == userId;
}

// FCM Tokens subcollection - user can manage their own tokens
match /users/{userId}/fcmTokens/{token} {
  allow read, write: if request.auth != null && request.auth.uid == userId;
}
```

**✅ No additional Firestore rules needed!**

## Cloud Functions (Optional Enhancement)

### What's NOT Implemented:
- **Push notification sending from Cloud Functions**
- **Automatic match detection notifications**
- **Scheduled reminder notifications**

### To Implement Cloud Functions (Optional):
Create `functions/notifications.js`:

```javascript
const functions = require('firebase-functions');
const admin = require('firebase-admin');

// Send notification when new match is detected
exports.sendMatchNotification = functions.firestore
  .document('users/{userId}/notifications/{notificationId}')
  .onCreate(async (snap, context) => {
    const notification = snap.data();
    const userId = context.params.userId;
    
    // Get user's FCM tokens
    const tokensSnapshot = await admin.firestore()
      .collection('users').doc(userId)
      .collection('fcmTokens')
      .get();
    
    const tokens = tokensSnapshot.docs.map(doc => doc.id);
    
    if (tokens.length === 0) return null;
    
    // Send push notification
    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: {
        route: notification.actionRoute || '',
        notificationId: context.params.notificationId,
      },
      tokens: tokens,
    };
    
    try {
      const response = await admin.messaging().sendMulticast(message);
      console.log('Successfully sent notification:', response);
      return response;
    } catch (error) {
      console.error('Error sending notification:', error);
      return null;
    }
  });
```

Then deploy:
```bash
cd functions
firebase deploy --only functions:sendMatchNotification
```

## Expected Results

### ✅ Test Passed When:
1. **Permission**: Shows "authorized" after granting
2. **FCM Token**: Displays valid token string
3. **Token Sync**: Successfully saves to Firestore
4. **Create Notifications**: All 5 types create successfully
5. **Firestore Check**: Shows correct notification count
6. **Notifications List**: Displays all notifications with correct formatting
7. **Read Status**: Marks as read when tapped
8. **Settings**: Toggles persist across app restarts
9. **Localization**: Strings appear in English/Arabic based on language setting
10. **Activity Log**: Shows detailed operation logs without errors

### ❌ Common Issues:

**Issue: Permission Denied**
- Solution: Check Android manifest has `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`

**Issue: No FCM Token**
- Solution: Ensure Firebase is initialized and google-services.json is present

**Issue: Firestore Permission Denied**
- Solution: Check Firestore rules allow read/write for user's own data

**Issue: Notifications not appearing**
- Solution: Check NotificationService is initialized in main.dart

**Issue: Localization not working**
- Solution: Verify app_en.arb and app_ar.arb have notification keys

## Monitoring

### Check Logs:
```bash
# Android
flutter run --verbose | grep "Notification"

# Or use ADB logcat
adb logcat | grep "flutter"
```

### Activity Log in Test Screen:
- All operations are logged with emoji prefixes:
  - 🔔 = Notification operation
  - ✅ = Success
  - ❌ = Error
  - ⚠️ = Warning

## Next Steps After Testing

### If All Tests Pass:
1. ✅ Notification system is fully functional
2. ✅ Users can receive in-app notifications
3. ✅ Settings are customizable and persistent
4. ✅ Localization works in English and Arabic
5. ⏭️ **Optional**: Implement Cloud Functions for push notifications
6. ⏭️ **Optional**: Add automated match detection
7. ⏭️ **Optional**: Add scheduled reminders

### If Tests Fail:
1. Check **Activity Log** for error details
2. Verify **Firebase Console** shows data correctly
3. Check **Firestore Rules** are correct
4. Ensure **Firebase SDK** is up to date
5. Review **Android Manifest** permissions

## Summary

✅ **What Works Now:**
- In-app notification display
- Notification settings with persistence
- FCM token management
- Firestore integration
- Bilingual support (EN/AR)
- Real-time notification updates
- Unread count tracking
- Mark as read functionality
- Swipe to delete
- Pull to refresh

⏳ **What Requires Cloud Functions (Optional):**
- Automatic push notifications
- Match detection alerts
- Scheduled reminders
- Background notification sending

🎯 **Bottom Line:**
The notification system is **100% functional** for in-app use. Cloud Functions are only needed if you want **automatic background push notifications** when users are not actively using the app.
