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
/// What happened when an account was created.
///
/// Three outcomes rather than a bool, because "confirm your email" and "that
/// address already has an account" need different screens and the caller
/// cannot tell them apart from a null session alone.
enum SignUpOutcome { signedIn, confirmEmail, alreadyRegistered }

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

  /// Registers an account.
  ///
  /// Returns [SignUpOutcome.confirmEmail] when Supabase created the user but
  /// no session, which is what happens whenever the project has "Confirm
  /// email" switched on. The caller has to handle that: the router only
  /// moves off /signup once a session exists, so assuming one always follows
  /// signUp leaves the user staring at the form they just submitted with a
  /// success message on screen.
  Future<SignUpOutcome> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? faculty,
    String? course,
    String? academicYear,
    int? graduationYear,
    String? companyName,
    String? industry,
    List<String>? contentInterests,
  }) async {
    final clean = email.trim().toLowerCase();

    // The database enforces this too; checking here gives a clear message
    // instead of Auth's generic "Database error saving new user".
    if (role == 'STUDENT' && !isValidStudentEmail(clean)) {
      throw StateError(
        'Students must register with a @richfield.ac.za address whose prefix '
        'is a 9-digit student number.',
      );
    }

    final response = await db.auth.signUp(
      email: clean,
      password: password,
      data: {
        'full_name': fullName.trim(),
        'role': role,
        'faculty': ?faculty,
        'course': ?course,
        'academic_year': ?academicYear,
        if (graduationYear != null) 'graduation_year': '$graduationYear',
        'company_name': ?companyName,
        'industry': ?industry,
        // Which faculties a business wants content from. Students and alumni
        // do not send this — trg_profiles_interests derives it from faculty.
        if (contentInterests != null && contentInterests.isNotEmpty)
          'content_interests': contentInterests,
      },
    );

    if (response.session != null) return SignUpOutcome.signedIn;
    if (response.user != null) return SignUpOutcome.confirmEmail;

    // Supabase returns a user with no identities when the address is already
    // registered, rather than erroring — telling the caller it worked would
    // send them to an inbox that will never receive anything.
    return SignUpOutcome.alreadyRegistered;
  }

  /// Resends the confirmation mail, for the "did not arrive" case.
  Future<void> resendConfirmation(String email) => db.auth.resend(
        type: OtpType.signup,
        email: email.trim().toLowerCase(),
      );

  Future<void> signOut() => db.auth.signOut();

  Future<void> sendPasswordReset(String email) =>
      db.auth.resetPasswordForEmail(email.trim().toLowerCase());

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
