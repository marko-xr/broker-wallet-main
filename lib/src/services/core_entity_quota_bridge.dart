import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import 'quota_helper.dart';

/// Backend-aware bridge for the legacy core-entity quota UI.
///
/// During the Supabase migration, RevenueCat entitlement mapping and final paid
/// quota limits are not yet configured. Supabase mode therefore never touches
/// Firebase for quota checks/counters. The database remains the source of truth
/// for entity rows and RLS ownership.
///
/// Firebase mode preserves the original quota behavior unchanged.
class CoreEntityQuotaBridge {
  const CoreEntityQuotaBridge._();

  static Future<bool> canCreate({
    required BuildContext context,
    required String section,
  }) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return true;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return true;
    }

    return QuotaHelper.checkAndWarnQuota(
      context: context,
      uid: user.uid,
      section: section,
    );
  }

  static Future<void> recordCreated({required String section}) async {
    if (SupabaseConfig.useSupabaseAuth) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'counts': {section: FieldValue.increment(1)},
        'lifetimeCreated': {section: FieldValue.increment(1)},
      }, SetOptions(merge: true));
    } catch (_) {
      // Quota accounting must not convert a successful legacy entity save into
      // a failed save. This preserves the previous behavior.
    }
  }
}
