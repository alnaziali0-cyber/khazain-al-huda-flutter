import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The developer panel must stay hidden: it has no route, no visible
/// affordance and no entry point other than the long-press gesture on the
/// logo in the bottom navigation.
void main() {
  test('the router exposes no developer panel route', () {
    final router = File('lib/app/router.dart').readAsStringSync();
    expect(router, isNot(contains("path: '/developer'")));
    expect(router, isNot(contains('DevPanelScreen')));
    expect(router, isNot(contains('DevPanel')));
  });

  test('no visible control opens the developer panel', () {
    final lib = Directory('lib');
    final sources = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.contains('devpanel'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    // The only reference outside the panel itself is the launcher that
    // reacts to the long-press on the logo.
    expect(sources, isNot(contains('context.push(\'/developer')));
    expect(sources, isNot(contains('context.go(\'/developer')));
    expect(sources, isNot(contains('Navigator.of(context).pushNamed(')));
  });

  test('the panel is opened by a long-press gesture on the logo', () {
    final launcher = File('lib/devpanel/open.dart').readAsStringSync();
    expect(launcher, contains('Duration(milliseconds: 900)'));
    expect(launcher, contains('DevPanelOpener'));
  });
}
