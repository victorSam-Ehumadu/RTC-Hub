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
    String? campus,
    int? enrollmentYear,
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
        'campus': ?campus,
        if (enrollmentYear != null) 'enrollment_year': '$enrollmentYear',
        'student_number': ?studentNumber,
        'company_name': ?companyName,
        'industry': ?industry,
      },
    );
  }

  Future<void> signOut() => db.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      db.auth.resetPasswordForEmail(email.trim().toLowerCase());

  /// Changes the signed-in user's own password. Unlike the admin-forced
  /// reset (`admin_reset_password`, migration 0014), this needs no RPC —
  /// Supabase's own `updateUser` already scopes a write to the caller, so
  /// there's no privileged-write boundary to cross (CLAUDE.md's
  /// SECURITY DEFINER rule is for writing data on someone else's behalf, or
  /// a field a user could benefit from lying about; a user's own credential
  /// is neither). The caller re-authenticates with the current password
  /// first — see [signIn] — which doubles as verifying it's correct.
  Future<void> updateOwnPassword(String newPassword) =>
      db.auth.updateUser(UserAttributes(password: newPassword));

  /// Deletes the signed-in user's own account. See migration 0019's
  /// `delete_own_account()` — a SECURITY DEFINER function is required here
  /// because deleting an `auth.users` row needs privileges the client's
  /// anon-derived JWT never holds.
  Future<void> deleteOwnAccount() => db.rpc('delete_own_account');

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
