class BackendConfig {
  // Sirf defaultValue wale string ko purane URL se naye Cloud URL se replace kiya gaya hai
  static const String _configured = String.fromEnvironment(
      'BACKEND_URL', 
      defaultValue: 'https://19ripudaman-rajshala-captcha-solver.hf.space'
  );
  static String get baseUrl => _configured.replaceFirst(RegExp(r'/+$'), '');
  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}