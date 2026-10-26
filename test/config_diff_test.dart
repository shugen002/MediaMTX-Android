import 'package:flutter_test/flutter_test.dart';
import 'package:mediamtx_manager/core/utils/json_diff.dart';

void main() {
  test('only changed top-level keys are patched', () {
    final before = {
      'logLevel': 'info',
      'api': true,
      'authInternalUsers': [
        {'user': 'admin', 'pass': '<redacted>'},
      ],
    };
    final after = {
      'logLevel': 'debug',
      'api': true,
      'authInternalUsers': [
        {'user': 'admin', 'pass': '<redacted>'},
      ],
    };
    expect(changedTopLevelKeys(before, after), {'logLevel': 'debug'});
  });

  test('detects redacted secrets anywhere in a patch', () {
    expect(
      containsRedactedSecret({
        'authInternalUsers': [
          {'user': 'admin', 'pass': '<redacted>'},
        ],
      }),
      isTrue,
    );
    expect(containsRedactedSecret({'logLevel': 'debug'}), isFalse);
  });
}
