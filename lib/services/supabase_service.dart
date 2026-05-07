import 'package:supabase_flutter/supabase_flutter.dart';

SupabaseClient get supabase => Supabase.instance.client;

Future<T> withRetry<T>(Future<T> Function() fn) async {
  try {
    return await fn();
  } catch (_) {
    await Future.delayed(const Duration(seconds: 2));
    return fn();
  }
}
