import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/supabase.dart';
import '../models/profile.dart';

/// Replaces the old `/api/auth` routes.
///
/// Signup no longer inserts the profile itself — it hands the profile fields
/// to Supabase Auth as user metadata, and the `handle_new_user` trigger builds
/// the `profiles` row inside the same transaction. That is what keeps `role`
/// and `status` out of the client's control.
class AuthRepository {
  const AuthRepository();

  Session? get session => db.auth.currentSession;

  Stream<AuthState> get changes => db.auth.onAuthStateChange;

  Future<void> signIn({required String email, required String password}) async {
    await db.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? faculty,
    String? course,
    String? academicYear,
    int? graduationYear,
    String? studentNumber,
    String? companyName,
    String? industry,
  }) async {
    final clean = email.trim().toLowerCase();

    // The database enforces this too; checking here gives a clear message
    // instead of Auth's generic "Database error saving new user".
    if (role == 'STUDENT' && !isValidStudentEmail(clean)) {
      throw StateError(
        'Students must register with a Richfield or AAA address whose prefix '
        'is a 9-digit student number.',
      );
    }

    await db.auth.signUp(
      email: clean,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'role': role,
        'faculty': ?faculty,
        'course': ?course,
        'academic_year': ?academicYear,
        if (graduationYear != null) 'graduation_year': '$graduationYear',
        'student_number': ?studentNumber,
        'company_name': ?companyName,
        'industry': ?industry,
      },
    );
  }

  Future<void> signOut() => db.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      db.auth.resetPasswordForEmail(email.trim().toLowerCase());

  /// Change the signed-in user's password. Requires the old password for verification.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      db.rpc('user_change_password', params: {
        'p_old_password': currentPassword,
        'p_new_password': newPassword,
      });

  /// Permanently delete the signed-in user's account and all associated data.
  /// Requires the password for verification. This operation cannot be undone.
  Future<void> deleteAccount({required String password}) =>
      db.rpc('user_delete_account', params: {
        'p_password': password,
      });

  /// The signed-in user's own profile row.
  ///
  /// Returns null in the brief window after signup where the auth user exists
  /// but the trigger's insert has not yet been committed, and when the account
  /// was deleted out from under a stale session.
  Future<Profile?> currentProfile() async {
    final id = currentUserId;
    if (id == null) return null;
    final row =
        await db.from('profiles').select().eq('id', id).maybeSingle();
    return row == null ? null : Profile.fromMap(row);
  }
}
