import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns Supabase/Postgres errors into something worth showing a user.
///
/// Two cases matter most here. RLS rejections surface as PostgrestException
/// 42501 with unhelpful text, and our own `RAISE EXCEPTION` messages in
/// migration 0002 arrive as P0001 — those are written for humans, so they are
/// passed straight through.
String describeError(Object error) {
  if (error is AuthException) {
    final msg = error.message;
    if (msg.contains('Invalid login credentials')) {
      return 'That email and password combination is not recognised.';
    }
    if (msg.contains('Email not confirmed')) {
      return 'Check your inbox and confirm your email address first.';
    }
    // Signup runs handle_new_user(); a raise in there arrives as a generic
    // "Database error saving new user", so surface the likely cause.
    if (msg.contains('Database error saving new user')) {
      return 'Signup was rejected. Students must use a Richfield or AAA '
          'student address with a 9-digit student number.';
    }
    return msg;
  }

  if (error is PostgrestException) {
    switch (error.code) {
      case '42501':
        return 'You do not have permission to do that.';
      case '23505':
        return 'That already exists.';
      case '23503':
        return 'That item no longer exists.';
      case 'P0001':
        return error.message; // our own RAISE EXCEPTION text
      default:
        return error.message;
    }
  }

  if (error is StorageException) return error.message;
  if (error is StateError) return error.message;

  return 'Something went wrong. Please try again.';
}
