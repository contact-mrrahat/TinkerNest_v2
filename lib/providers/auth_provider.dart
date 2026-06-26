import 'package:flutter/foundation.dart';

/// Placeholder auth state until Firebase (or another backend) is wired up.
class AuthProvider extends ChangeNotifier {
  String? _email;
  bool _initialized = false;

  String? get userEmail => _email;
  bool get isAuthenticated => _email != null;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    _initialized = true;
    notifyListeners();
  }

  Future<String?> signInWithEmail(String email, String password) async {
    return 'Authentication is not configured yet.';
  }

  Future<String?> registerWithEmail(String email, String password) async {
    return 'Authentication is not configured yet.';
  }

  Future<void> signOut() async {
    _email = null;
    notifyListeners();
  }
}
