import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/hive/safe_box.dart';
import 'package:watch_app/core/notify/subscription_store.dart';

/// A subscription's box key is `sourceId|url`, built from the same source id
/// and show url that `my_list` and `watch_history` key on — and those go
/// through [hiveKey] because Hive writes a String key's length into a single
/// byte, so a key past 255 bytes is written with a wrapped length and the box
/// is unreadable from that frame on.
///
/// These drive the real store against a real box file, then reopen it through
/// [openBoxSafely] the way startup does: that is where an oversized key is
/// paid for, by the box being quarantined and reopened empty.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('subkey');
    Hive.init(dir.path);
    hiveBoxDir = dir.path;
    quarantinedBoxes.clear();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  Subscription sub(String sourceId, String url) =>
      Subscription(sourceId: sourceId, url: url, title: 'A Show', lastCount: 1);

  /// Closes every box and opens the subscriptions box again, exactly as a
  /// fresh launch does.
  Future<SubscriptionStore> relaunch() async {
    await Hive.close();
    Hive.init(dir.path);
    hiveBoxDir = dir.path;
    await SubscriptionStore.init();
    return SubscriptionStore();
  }

  test('a url that is short in characters but long in bytes keeps the box '
      'readable', () async {
    // 215 characters, 575 bytes: it passes Hive's own `assertKey` (which
    // counts characters) while the file counts bytes, so even a debug build
    // writes it straight to disk. Reading sources hand out paths with the
    // title unescaped in them.
    final url = 'https://example.test/manga/${'進' * 180}';

    await SubscriptionStore.init();
    final store = SubscriptionStore();
    // Subscribed first, and the one the user loses.
    await store.add(sub('ani:1', 'https://example.test/show/1'));
    await store.add(sub('mi:Some', url));

    final reopened = await relaunch();

    expect(
      quarantinedBoxes,
      isEmpty,
      reason: 'the box file came back unreadable, so every alert was dropped',
    );
    expect(
      reopened.all().map((s) => s.sourceId).toList(),
      containsAll(<String>['ani:1', 'mi:Some']),
    );
    expect(reopened.contains('mi:Some', url), isTrue);
  });

  test('a CloudStream url carrying a data blob survives a relaunch', () async {
    // The shape named in the My List / Watch History report: the show id
    // travels as a JSON blob in the query, for keys of several kilobytes.
    final url = 'https://example.test/e?data=${'{"u":"${'x' * 4000}"}'}';

    await SubscriptionStore.init();
    final store = SubscriptionStore();
    await store.add(sub('ani:1', 'https://example.test/show/1'));
    await store.add(sub('cs:AnimeWitcher', url));

    final reopened = await relaunch();

    expect(quarantinedBoxes, isEmpty);
    expect(reopened.all().length, 2);
    expect(reopened.contains('cs:AnimeWitcher', url), isTrue);
  });

  test('setCount still finds the row it wrote', () async {
    final url = 'https://example.test/manga/${'進' * 180}';

    await SubscriptionStore.init();
    final store = SubscriptionStore();
    await store.add(sub('mi:Some', url));

    await store.setCount('mi:Some', url, 7);

    expect(store.all().single.lastCount, 7);
    final reopened = await relaunch();
    expect(reopened.all().single.lastCount, 7);
  });

  test('an ordinary subscription keeps the key it already has on disk',
      () async {
    await SubscriptionStore.init();
    final store = SubscriptionStore();
    const url = 'https://example.test/show/1';
    await store.add(sub('ani:1', url));

    // Rows written before this change must still be found, so the key for
    // anything that fits has to stay byte-for-byte what it was.
    expect(Hive.box(SubscriptionStore.boxName).keys, ['ani:1|$url']);
    expect(store.contains('ani:1', url), isTrue);
  });
}
