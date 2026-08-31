// import 'package:broker_wallet/src/common/localization/localization_delegate.dart';
// import 'package:broker_wallet/src/data/models/notification_model.dart';
// import 'package:broker_wallet/src/repositories/repository_provider.dart';
// import 'package:broker_wallet/src/viewmodels/Signup-Login/auth_viewmodel.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:provider/provider.dart';

// /// Test screen to verify notification system functionality
// /// This screen allows testing:
// /// 1. FCM token generation and storage
// /// 2. Creating test notifications in Firestore
// /// 3. Notification permissions
// /// 4. Local notification display
// class NotificationTestView extends StatefulWidget {
//   const NotificationTestView({super.key});

//   @override
//   State<NotificationTestView> createState() => _NotificationTestViewState();
// }

// class _NotificationTestViewState extends State<NotificationTestView> {
//   String _fcmToken = 'Loading...';
//   String _permissionStatus = 'Checking...';
//   bool _isLoading = false;
//   final List<String> _logs = [];

//   @override
//   void initState() {
//     super.initState();
//     _checkNotificationStatus();
//   }

//   void _log(String message) {
//     if (mounted) {
//       setState(() {
//         _logs.insert(
//             0, '${DateTime.now().toString().substring(11, 19)} - $message');
//         if (_logs.length > 50) _logs.removeLast();
//       });
//     }
//     print('🔔 Notification Test: $message');
//   }

//   Future<void> _checkNotificationStatus() async {
//     _log('Checking notification status...');

//     try {
//       // Check FCM token
//       final token = await FirebaseMessaging.instance.getToken();
//       setState(() {
//         _fcmToken = token ?? 'No token available';
//       });
//       _log('FCM Token retrieved: ${token?.substring(0, 20)}...');

//       // Check permission status
//       final settings =
//           await FirebaseMessaging.instance.getNotificationSettings();
//       setState(() {
//         _permissionStatus = settings.authorizationStatus.toString();
//       });
//       _log('Permission status: ${settings.authorizationStatus}');

//       _log('✅ NotificationService check complete');
//     } catch (e) {
//       _log('❌ Error checking status: $e');
//     }
//   }

//   Future<void> _requestPermission() async {
//     _log('Requesting notification permission...');
//     setState(() => _isLoading = true);

//     try {
//       final settings = await FirebaseMessaging.instance.requestPermission(
//         alert: true,
//         badge: true,
//         sound: true,
//         provisional: false,
//       );

//       setState(() {
//         _permissionStatus = settings.authorizationStatus.toString();
//         _isLoading = false;
//       });

//       if (settings.authorizationStatus == AuthorizationStatus.authorized) {
//         _log('✅ Permission granted!');
//       } else if (settings.authorizationStatus == AuthorizationStatus.denied) {
//         _log('❌ Permission denied');
//       } else {
//         _log('⚠️ Permission status: ${settings.authorizationStatus}');
//       }

//       await _checkNotificationStatus();
//     } catch (e) {
//       setState(() => _isLoading = false);
//       _log('❌ Error requesting permission: $e');
//     }
//   }

//   Future<void> _createTestNotification(NotificationCategory category) async {
//     final authVM = context.read<AuthViewModel>();
//     final userId = authVM.currentUser?.uid;

//     if (userId == null) {
//       _log('❌ No user logged in');
//       _showSnackBar('Please log in first');
//       return;
//     }

//     setState(() => _isLoading = true);
//     _log('Creating ${category.firestoreValue} notification...');

//     try {
//       final notification = NotificationModel(
//         id: DateTime.now().millisecondsSinceEpoch.toString(),
//         title: _getTitleForCategory(category),
//         body: _getBodyForCategory(category),
//         category: category,
//         isRead: false,
//         createdAt: DateTime.now(),
//         data: {
//           'testData': 'This is a test notification',
//           'timestamp': DateTime.now().toIso8601String(),
//         },
//         actionRoute:
//             category == NotificationCategory.match ? '/offers-list' : null,
//       );

//       final repository = RepositoryProvider.instance.notificationRepository;
//       await repository.saveNotification(userId, notification);

//       setState(() => _isLoading = false);
//       _log('✅ Notification created successfully!');
//       _showSnackBar('Test notification created!');
//     } catch (e) {
//       setState(() => _isLoading = false);
//       _log('❌ Error creating notification: $e');
//       _showSnackBar('Error: $e');
//     }
//   }

//   String _getTitleForCategory(NotificationCategory category) {
//     final localization = AppLocalizations.of(context);
//     switch (category) {
//       case NotificationCategory.match:
//         return localization.translate('notifMatchTitle');
//       case NotificationCategory.reminder:
//         return localization.translate('notifReminderTitle');
//       case NotificationCategory.plan:
//         return localization.translate('notifQuotaTitle');
//       case NotificationCategory.system:
//         return localization.translate('notifSystemTitle');
//     }
//   }

//   String _getBodyForCategory(NotificationCategory category) {
//     final localization = AppLocalizations.of(context);
//     switch (category) {
//       case NotificationCategory.match:
//         return localization.translate('notifMatchBody');
//       case NotificationCategory.reminder:
//         return localization.translate('notifReminderBody');
//       case NotificationCategory.plan:
//         return localization.translate('notifQuotaBody');
//       case NotificationCategory.system:
//         return localization.translate('notifSystemBody');
//     }
//   }

//   Future<void> _syncFcmToken() async {
//     final authVM = context.read<AuthViewModel>();
//     final userId = authVM.currentUser?.uid;

//     if (userId == null) {
//       _log('❌ No user logged in');
//       _showSnackBar('Please log in first');
//       return;
//     }

//     setState(() => _isLoading = true);
//     _log('Syncing FCM token to Firestore...');

//     try {
//       final token = await FirebaseMessaging.instance.getToken();
//       if (token == null) {
//         _log('❌ No FCM token available');
//         setState(() => _isLoading = false);
//         return;
//       }

//       final repository = RepositoryProvider.instance.notificationRepository;
//       await repository.upsertFcmToken(
//         userId,
//         FcmTokenMetadata(
//           token: token,
//           platform: 'android',
//           updatedAt: DateTime.now(),
//           deviceName: 'Test Device',
//           locale: 'en',
//         ),
//       );

//       setState(() => _isLoading = false);
//       _log('✅ FCM token synced successfully!');
//       _showSnackBar('Token synced to Firestore');
//     } catch (e) {
//       setState(() => _isLoading = false);
//       _log('❌ Error syncing token: $e');
//       _showSnackBar('Error: $e');
//     }
//   }

//   Future<void> _checkFirestoreNotifications() async {
//     final authVM = context.read<AuthViewModel>();
//     final userId = authVM.currentUser?.uid;

//     if (userId == null) {
//       _log('❌ No user logged in');
//       _showSnackBar('Please log in first');
//       return;
//     }

//     setState(() => _isLoading = true);
//     _log('Checking Firestore notifications...');

//     try {
//       final repository = RepositoryProvider.instance.notificationRepository;
//       final notifications =
//           await repository.fetchNotifications(userId, limit: 5);

//       setState(() => _isLoading = false);
//       _log('✅ Found ${notifications.length} notifications in Firestore');

//       if (notifications.isEmpty) {
//         _showSnackBar('No notifications found in Firestore');
//       } else {
//         _showSnackBar('Found ${notifications.length} notifications');
//         for (final notif in notifications) {
//           _log('  - ${notif.title} (${notif.category.firestoreValue})');
//         }
//       }
//     } catch (e) {
//       setState(() => _isLoading = false);
//       _log('❌ Error fetching notifications: $e');
//       _showSnackBar('Error: $e');
//     }
//   }

//   void _showSnackBar(String message) {
//     if (mounted) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
//       );
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Notification System Test'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _checkNotificationStatus,
//             tooltip: 'Refresh Status',
//           ),
//         ],
//       ),
//       body: _isLoading
//           ? const Center(child: CircularProgressIndicator())
//           : ListView(
//               padding: const EdgeInsets.all(16),
//               children: [
//                 // Status Card
//                 Card(
//                   child: Padding(
//                     padding: const EdgeInsets.all(16),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           'System Status',
//                           style: Theme.of(context).textTheme.titleLarge,
//                         ),
//                         const SizedBox(height: 16),
//                         _StatusRow(
//                           label: 'Permission',
//                           value: _permissionStatus,
//                           icon: Icons.security,
//                         ),
//                         const SizedBox(height: 8),
//                         _StatusRow(
//                           label: 'FCM Token',
//                           value: _fcmToken.length > 30
//                               ? '${_fcmToken.substring(0, 30)}...'
//                               : _fcmToken,
//                           icon: Icons.vpn_key,
//                           onTap: () {
//                             Clipboard.setData(ClipboardData(text: _fcmToken));
//                             _showSnackBar('Token copied to clipboard');
//                           },
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 16),

//                 // Actions Card
//                 Card(
//                   child: Padding(
//                     padding: const EdgeInsets.all(16),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.stretch,
//                       children: [
//                         Text(
//                           'Actions',
//                           style: Theme.of(context).textTheme.titleLarge,
//                         ),
//                         const SizedBox(height: 16),
//                         ElevatedButton.icon(
//                           onPressed: _requestPermission,
//                           icon: const Icon(Icons.notifications_active),
//                           label: const Text('Request Permission'),
//                         ),
//                         const SizedBox(height: 8),
//                         ElevatedButton.icon(
//                           onPressed: _syncFcmToken,
//                           icon: const Icon(Icons.sync),
//                           label: const Text('Sync FCM Token'),
//                         ),
//                         const SizedBox(height: 8),
//                         ElevatedButton.icon(
//                           onPressed: _checkFirestoreNotifications,
//                           icon: const Icon(Icons.cloud_download),
//                           label: const Text('Check Firestore Notifications'),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 16),

//                 // Create Test Notifications
//                 Card(
//                   child: Padding(
//                     padding: const EdgeInsets.all(16),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.stretch,
//                       children: [
//                         Text(
//                           'Create Test Notifications',
//                           style: Theme.of(context).textTheme.titleLarge,
//                         ),
//                         const SizedBox(height: 16),
//                         _TestNotificationButton(
//                           category: NotificationCategory.match,
//                           onPressed: () => _createTestNotification(
//                               NotificationCategory.match),
//                         ),
//                         const SizedBox(height: 8),
//                         _TestNotificationButton(
//                           category: NotificationCategory.reminder,
//                           onPressed: () => _createTestNotification(
//                               NotificationCategory.reminder),
//                         ),
//                         const SizedBox(height: 8),
//                         _TestNotificationButton(
//                           category: NotificationCategory.plan,
//                           onPressed: () => _createTestNotification(
//                               NotificationCategory.plan),
//                         ),
//                         const SizedBox(height: 8),
//                         _TestNotificationButton(
//                           category: NotificationCategory.system,
//                           onPressed: () => _createTestNotification(
//                               NotificationCategory.system),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 16),

//                 // Logs Card
//                 Card(
//                   child: Padding(
//                     padding: const EdgeInsets.all(16),
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.stretch,
//                       children: [
//                         Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Text(
//                               'Activity Log',
//                               style: Theme.of(context).textTheme.titleLarge,
//                             ),
//                             TextButton(
//                               onPressed: () => setState(() => _logs.clear()),
//                               child: const Text('Clear'),
//                             ),
//                           ],
//                         ),
//                         const SizedBox(height: 8),
//                         Container(
//                           height: 300,
//                           decoration: BoxDecoration(
//                             color: Theme.of(context)
//                                 .colorScheme
//                                 .surfaceContainerHighest,
//                             borderRadius: BorderRadius.circular(8),
//                           ),
//                           child: _logs.isEmpty
//                               ? const Center(child: Text('No logs yet'))
//                               : ListView.builder(
//                                   itemCount: _logs.length,
//                                   itemBuilder: (context, index) {
//                                     return Padding(
//                                       padding: const EdgeInsets.symmetric(
//                                         horizontal: 12,
//                                         vertical: 4,
//                                       ),
//                                       child: Text(
//                                         _logs[index],
//                                         style: Theme.of(context)
//                                             .textTheme
//                                             .bodySmall
//                                             ?.copyWith(
//                                               fontFamily: 'monospace',
//                                             ),
//                                       ),
//                                     );
//                                   },
//                                 ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ),
//                 const SizedBox(height: 100),
//               ],
//             ),
//     );
//   }
// }

// class _StatusRow extends StatelessWidget {
//   const _StatusRow({
//     required this.label,
//     required this.value,
//     required this.icon,
//     this.onTap,
//   });

//   final String label;
//   final String value;
//   final IconData icon;
//   final VoidCallback? onTap;

//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       onTap: onTap,
//       child: Row(
//         children: [
//           Icon(icon, size: 20),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text(
//                   label,
//                   style: Theme.of(context).textTheme.labelSmall,
//                 ),
//                 const SizedBox(height: 4),
//                 Text(
//                   value,
//                   style: Theme.of(context).textTheme.bodyMedium,
//                 ),
//               ],
//             ),
//           ),
//           if (onTap != null) const Icon(Icons.copy, size: 16),
//         ],
//       ),
//     );
//   }
// }

// class _TestNotificationButton extends StatelessWidget {
//   const _TestNotificationButton({
//     required this.category,
//     required this.onPressed,
//   });

//   final NotificationCategory category;
//   final VoidCallback onPressed;

//   IconData get icon {
//     switch (category) {
//       case NotificationCategory.match:
//         return Icons.handshake;
//       case NotificationCategory.reminder:
//         return Icons.alarm;
//       case NotificationCategory.plan:
//         return Icons.pie_chart;
//       case NotificationCategory.system:
//         return Icons.shield;
//     }
//   }

//   String get label {
//     switch (category) {
//       case NotificationCategory.match:
//         return 'Match Notification';
//       case NotificationCategory.reminder:
//         return 'Reminder Notification';
//       case NotificationCategory.plan:
//         return 'Quota Notification';
//       case NotificationCategory.system:
//         return 'System Notification';
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return OutlinedButton.icon(
//       onPressed: onPressed,
//       icon: Icon(icon),
//       label: Text(label),
//     );
//   }
// }
