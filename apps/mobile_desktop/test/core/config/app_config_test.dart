import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_desktop/core/config/app_config.dart';

void main() {
  group('AppConfig.validate', () {
    test('throws when required --dart-define values are missing', () {
      // No --dart-define values are passed in this test run, so all
      // configuration fields are empty strings.
      expect(() => AppConfig.validate(), throwsStateError);
    });
  });
}
