import 'package:flutter_test/flutter_test.dart';

import 'package:campus_connect/core/services/cu_identity.dart';

void main() {
  group('CU login id validation', () {
    test('accepts a real CU email', () {
      expect(CuIdentity.validate('21bcs5084@cuchd.in'), isNull);
      expect(CuIdentity.validate('21BCS5084@cuchd.in'), isNull);
    });

    test('rejects non-CU domains', () {
      expect(CuIdentity.validate('21bcs5084@gmail.com'), isNotNull);
      expect(CuIdentity.validate('someone@outlook.com'), isNotNull);
    });

    test('rejects a malformed university id', () {
      expect(CuIdentity.validate('hello@cuchd.in'), isNotNull);
      expect(CuIdentity.validate('21bcs5084'), isNotNull);
      expect(CuIdentity.validate(''), isNotNull);
    });
  });

  group('CU login id parsing', () {
    test('decodes batch, program and roll number', () {
      final id = CuIdentity.parse('21bcs5084@cuchd.in')!;

      expect(id.uid, '21bcs5084');
      expect(id.displayUid, '21BCS5084');
      expect(id.admissionYear, 2021);
      expect(id.programCode, 'bcs');
      expect(id.rollNumber, '5084');
      expect(id.department, 'Computer Science');
      expect(id.course, 'B.E. CSE');
      expect(id.email, '21bcs5084@cuchd.in');
    });

    test('year of study stays within 1st..4th year', () {
      final id = CuIdentity.parse('21bcs5084')!;
      expect(
        ['1st Year', '2nd Year', '3rd Year', '4th Year'],
        contains(id.yearOfStudy),
      );
    });

    test('falls back gracefully for unknown program codes', () {
      final id = CuIdentity.parse('23zzz1234@cuchd.in')!;
      expect(id.department, 'Chandigarh University');
      expect(id.course, 'Student');
    });
  });
}
