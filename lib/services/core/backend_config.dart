class BackendConfig {
  // Hugging Face URL ko Oracle Cloud VM ke IP aur Port se replace kiya gaya hai
  static const String _configured = String.fromEnvironment(
      'BACKEND_URL', 
      defaultValue: 'http://192.168.31.225:7860'
  );
  static String get baseUrl => _configured.replaceFirst(RegExp(r'/+$'), '');
  static Uri uri(String path) => Uri.parse('$baseUrl$path');
}