import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/player/player_controller.dart';

void main() {
  test('unsupported dynaudnorm filter is harmless, not a dead source', () {
    expect(
      PlayerCubit.isHarmlessPlaybackError(
        "Option af: 'dynaudnorm' isn't supported.",
      ),
      isTrue,
    );
  });

  test('existing harmless errors stay harmless', () {
    expect(
      PlayerCubit.isHarmlessPlaybackError('Audio device failed'),
      isTrue,
    );
    expect(
      PlayerCubit.isHarmlessPlaybackError('subtitle track failed'),
      isTrue,
    );
  });

  test('a real dead link is still fatal', () {
    expect(
      PlayerCubit.isHarmlessPlaybackError(
        'Failed to open https://x.test/v.m3u8',
      ),
      isFalse,
    );
  });
}
