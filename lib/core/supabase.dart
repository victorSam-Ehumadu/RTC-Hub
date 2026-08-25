import 'package:supabase_flutter/supabase_flutter.dart';

/// The one Supabase client the whole app talks to.
///
/// There is no application server: this client *is* the backend boundary, and
/// every query it makes is filtered by row-level security using the signed-in
/// user's JWT. Anything a user must not be able to forge is either denied by
/// policy or funnelled through an RPC — see
/// `supabase/migrations/0002_client_direct_access.sql`.
SupabaseClient get db => Supabase.instance.client;

/// Currently signed-in auth user id, or null when signed out.
String? get currentUserId => db.auth.currentUser?.id;

/// Throws if called while signed out. Repositories use this where a null id
/// would otherwise turn into a query that silently matches nothing.
String get requireUserId {
  final id = currentUserId;
  if (id == null) {
    throw StateError('No signed-in user');
  }
  return id;
}
