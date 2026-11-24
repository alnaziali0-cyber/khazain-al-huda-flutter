import 'package:flutter_test/flutter_test.dart';
import 'package:khazain_al_huda/features/sections/section_catalogue.dart';
import 'package:khazain_al_huda/icons/khazain_icons.dart';

void main() {
  test('the icon set holds exactly eighteen hand-authored glyphs', () {
    expect(kKhazainIcons.length, 18);
  });

  test('every icon id is unique and every path is non-empty', () {
    final ids = <String>{};
    for (final icon in kKhazainIcons) {
      expect(ids.add(icon.id), isTrue, reason: 'duplicate id ${icon.id}');
      expect(icon.paths, isNotEmpty);
      expect(icon.accentPaths, isNotEmpty);
      for (final path in <String>[...icon.paths, ...icon.accentPaths]) {
        expect(path.startsWith('M'), isTrue,
            reason: 'path of ${icon.id} must start with a move command');
      }
    }
  });

  test('every icon sits on the 24px grid with a 2px stroke', () {
    for (final icon in kKhazainIcons) {
      final def = icon.toIconDef();
      expect(def.size, 24);
      expect(def.stroke, 2);
      expect(def.primary, '#376E6A');
      expect(def.secondary, '#C77A57');
      expect(def.secondaryPathCount, icon.accentPaths.length);
    }
  });

  test('the two-tone split keeps the accent paths separate', () {
    for (final icon in kKhazainIcons) {
      final def = icon.toIconDef();
      expect(def.primaryPaths.length, icon.paths.length);
      expect(def.accentPaths.length, icon.accentPaths.length);
      expect(def.paths.length,
          icon.paths.length + icon.accentPaths.length);
    }
  });

  test('every catalogue section points at an existing icon', () {
    for (final section in kAppSections) {
      expect(khazainIconById(section.iconId), isNotNull,
          reason: 'section ${section.id} has no icon');
    }
  });

  test('the catalogue holds unique sections with a real route', () {
    expect(kAppSections.length, 33);
    final ids = <String>{};
    final titles = <String>{};
    for (final section in kAppSections) {
      expect(ids.add(section.id), isTrue);
      expect(titles.add(section.title), isTrue,
          reason: 'duplicated section title ${section.title}');
      expect(section.route.startsWith('/'), isTrue);
      expect(section.title.trim(), isNotEmpty);
    }
  });

  test('the sections are divided into the five shipped groups', () {
    for (final group in kAppSectionGroups) {
      expect(
        kAppSections.where((section) => section.group == group),
        isNotEmpty,
        reason: 'group $group is empty',
      );
    }
    expect(kAppSectionGroups.length, 5);
  });
}
