import 'package:flutter_test/flutter_test.dart';
import 'package:logicclass/features/faculty_portal/domain/entities/answer_key.dart';

/// The same table asserted server-side in
/// functions/test/shared/coursework/autoScore.test.ts. This copy is what
/// demo mode marks with; that one decides real students' marks. They have
/// to agree, and these tests are what makes a divergence show up as a
/// failure rather than as a wrong grade.
void main() {
  final key = AnswerKey(
    courseworkId: 'cw_1',
    answers: const ['Manila', 'B', '42'],
    pointsPerQuestion: 2,
    updatedByName: 'T',
    updatedAt: DateTime(2026, 1, 1),
  );

  group('marking', () {
    test('all correct scores full marks', () {
      expect(key.scoreFor(['Manila', 'B', '42']), 6);
      expect(key.correctCount(['Manila', 'B', '42']), 3);
    });

    test('capitals and surrounding space do not matter', () {
      // Marking a student wrong for the shift key would make automatic
      // marking worse than no automatic marking.
      expect(key.correctCount([' manila ', 'b', '42']), 3);
    });

    test('a wrong answer is wrong', () {
      expect(key.scoreFor(['Cebu', 'B', '42']), 4);
    });

    test('a missing answer is wrong, not skipped', () {
      // Otherwise a student raises their percentage by answering less.
      expect(key.correctCount(['Manila']), 1);
      expect(key.scoreFor([]), 0);
    });

    test('extra answers past the key are ignored', () {
      expect(key.correctCount(['Manila', 'B', '42', 'spare']), 3);
    });

    test('an out-of-range question is never correct', () {
      expect(key.isCorrect(99, 'Manila'), isFalse);
      expect(key.isCorrect(-1, 'Manila'), isFalse);
    });
  });

  test('totalPoints is what the whole thing is worth', () {
    expect(key.totalPoints, 6);
    expect(key.questionCount, 3);
  });
}
