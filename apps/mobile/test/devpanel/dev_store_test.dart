import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/devpanel/models.dart';
import 'package:khazain_al_huda/devpanel/store.dart';
import 'package:khazain_al_huda/features/sections/section_catalogue.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late DevStoreController store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = DevStoreController(prefs);
  });

  test('a patch applies and the state is persisted under khzain.dev.v1', () {
    store.applyPatch(UIPatch(tokens: <String, dynamic>{
      'colors': <String, String>{'gold': '#FFCC00'},
    }));

    expect(store.state.colorOverrides['dark']?['gold'], '#FFCC00');
    expect(prefs.getString(kDevStateKey), isNotNull);
    expect(prefs.getString(kDevStateKey), contains('"gold"'));
  });

  test('undo restores the previous state exactly (deep equality)', () {
    final before = store.state;
    store.applyPatch(UIPatch(tokens: <String, dynamic>{
      'colors': <String, String>{'gold': '#FFCC00'},
    }));
    expect(store.state, isNot(equals(before)));

    store.undo();
    expect(store.state.colorOverrides, before.colorOverrides);
    expect(store.state.toJson(), before.toJson());
  });

  test('redo re-applies the undone patch', () {
    store.applyPatch(UIPatch(tokens: <String, dynamic>{
      'colors': <String, String>{'gold': '#FFCC00'},
    }));
    store.undo();
    store.redo();
    expect(store.state.colorOverrides['dark']?['gold'], '#FFCC00');
  });

  test('the history keeps at most fifty steps', () {
    for (var index = 0; index < 60; index++) {
      store.applyPatch(UIPatch(tokens: <String, dynamic>{
        'colors': <String, String>{'gold': '#${index.toRadixString(16).padLeft(6, '0')}'},
      }));
    }
    expect(store.canUndo, isTrue);
    // Undoing everything the store still remembers must not throw.
    var steps = 0;
    while (store.canUndo && steps < 200) {
      store.undo();
      steps++;
    }
    expect(steps, lessThanOrEqualTo(50));
  });

  test('a failing transaction rolls the state back completely', () {
    store.applyPatch(UIPatch(tokens: <String, dynamic>{
      'colors': <String, String>{'gold': '#FFCC00'},
    }));
    final before = store.state.toJson();

    expect(
      () => store.applyPatch(UIPatch(sections: [
        {
          'op': 'add',
          'section': <String, dynamic>{'title': 'قسم بلا معرّف'},
        },
      ])),
      throwsA(isA<FormatException>()),
    );
    expect(store.state.toJson(), before);
  });

  test('section operations add, update, reorder and remove', () {
    store.applyPatch(UIPatch(sections: [
      {
        'op': 'add',
        'section': <String, dynamic>{
          'id': 'custom',
          'title': 'قسم مخصص',
          'iconId': 'quran',
          'group': 'أرشيف',
          'order': 3,
          'visible': true,
          'locked': false,
          'route': '/sections',
        },
      },
    ]));
    expect(store.state.sections.length, 1);

    store.applyPatch(UIPatch(sections: [
      {
        'op': 'update',
        'section': <String, dynamic>{'id': 'custom', 'title': 'عنوان جديد'},
      },
    ]));
    expect(store.state.sections.single.title, 'عنوان جديد');

    store.applyPatch(UIPatch(sections: [
      {
        'op': 'reorder',
        'section': <String, dynamic>{'id': 'custom', 'order': 9},
      },
    ]));
    expect(store.state.sections.single.order, 9);

    store.applyPatch(UIPatch(sections: [
      {
        'op': 'remove',
        'section': <String, dynamic>{'id': 'custom'},
      },
    ]));
    expect(store.state.sections, isEmpty);
  });

  test('legacy developer catalogues gain new sections without losing edits', () {
    final restored = DevState.fromJson({
      'sections': [
        {
          'id': 'quran',
          'title': 'مصحفي',
          'iconId': 'quran',
          'group': 'قرآن وأذكار',
          'order': 7,
          'visible': true,
          'locked': false,
          'route': '/quran',
        },
        {
          'id': 'adhkar',
          'title': 'الأذكار',
          'iconId': 'adhkar',
          'group': 'قرآن وأذكار',
          'order': 1,
          'visible': false,
          'locked': false,
          'route': '/adhkar',
        },
      ],
    });

    final byId = {for (final section in restored.sections) section.id: section};
    expect(byId['quran']?.title, 'مصحفي');
    expect(byId['quran']?.order, 7);
    expect(byId['adhkar']?.visible, isFalse);
    expect(byId.containsKey('shiavoice'), isTrue);
    expect(byId.containsKey('quranRecitations'), isTrue);
    expect(byId.length, greaterThanOrEqualTo(kAppSections.length));
  });

  test('the state exports and imports without losing data', () async {
    store.applyPatch(UIPatch(
      tokens: <String, dynamic>{
        'colors': <String, String>{'gold': '#FFCC00'},
      },
      strings: <String, String>{'hello': 'مرحبا'},
    ));

    final exported = store.export();
    SharedPreferences.setMockInitialValues({});
    final other = DevStoreController(await SharedPreferences.getInstance());
    other.importJson(exported);

    expect(other.state.colorOverrides['dark']?['gold'], '#FFCC00');
    expect(other.state.strings['hello'], 'مرحبا');
  });

  test('an invalid import keeps the previous state', () {
    final before = store.state.toJson();
    expect(() => store.importJson('not json'), throwsA(isA<FormatException>()));
    expect(store.state.toJson(), before);
  });
}
