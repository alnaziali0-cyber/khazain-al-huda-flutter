import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ImamsScreen extends StatelessWidget {
  const ImamsScreen({super.key});

  Future<List<_PersonRecord>> _loadPeople() async {
    final source = await rootBundle
        .loadString('assets/data/ahl_al_bayt_biographies.json');
    final decoded = jsonDecode(source);
    if (decoded is! List) {
      throw const FormatException('Invalid Ahl al-Bayt biographies dataset.');
    }
    return decoded
        .whereType<Map>()
        .map((item) =>
            _PersonRecord.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text('سيرة أهل البيت',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text('بطاقات تعريفية محلية من بيانات الحزمة الإضافية.'),
              const SizedBox(height: 14),
              FutureBuilder<List<_PersonRecord>>(
                future: _loadPeople(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const _InfoCard(
                        text: 'تعذر تحميل بيانات السيرة المحلية.');
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Column(
                    children: snapshot.data!.map((person) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 9),
                        child: ExpansionTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.secondaryContainer,
                            child: Icon(Icons.person_rounded,
                                color: theme.colorScheme.onSecondaryContainer),
                          ),
                          title: Text(person.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, height: 1.4)),
                          subtitle: person.titles.isEmpty
                              ? null
                              : Text(person.titles),
                          childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                              16, 0, 16, 16),
                          expandedCrossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          children: [
                            if (person.birth.isNotEmpty)
                              _FactLine(label: 'الولادة', value: person.birth),
                            if (person.death.isNotEmpty)
                              _FactLine(label: 'الوفاة / الشهادة', value: person.death),
                            if (person.birthPlace.isNotEmpty)
                              _FactLine(label: 'مكان الولادة', value: person.birthPlace),
                            if (person.mother.isNotEmpty)
                              _FactLine(label: 'الوالدة', value: person.mother),
                            if (person.burial.isNotEmpty)
                              _FactLine(label: 'المرقد / موضع الدفن', value: person.burial),
                          ],
                        ),
                      );
                    }).toList(growable: false),
                  );
                },
              ),
              const SizedBox(height: 10),
              const _InfoCard(
                text:
                    'نُقلت بيانات التواريخ والمواضع كما وردت في المصدر، وبعضها يذكر اختلافاً تاريخياً. هذه بطاقة تعريفية وليست تحقيقاً تاريخياً أو اعتماداً مرجعياً نهائياً.',
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _PersonRecord {
  const _PersonRecord({
    required this.name,
    required this.titles,
    required this.birth,
    required this.death,
    required this.birthPlace,
    required this.burial,
    required this.mother,
  });

  final String name;
  final String titles;
  final String birth;
  final String death;
  final String birthPlace;
  final String burial;
  final String mother;

  factory _PersonRecord.fromJson(Map<String, dynamic> json) => _PersonRecord(
        name: json['name_ar'] as String? ?? '',
        titles: json['titles'] as String? ?? '',
        birth: json['birth_hijri'] as String? ?? '',
        death: json['death_hijri'] as String? ?? '',
        birthPlace: json['birth_place'] as String? ?? '',
        burial: json['burial'] as String? ?? '',
        mother: json['mother'] as String? ?? '',
      );
}

class _FactLine extends StatelessWidget {
  const _FactLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 9),
        child: RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style.copyWith(height: 1.55),
            children: [
              TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              TextSpan(text: value),
            ],
          ),
        ),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline_rounded),
              const SizedBox(width: 9),
              Expanded(child: Text(text, style: const TextStyle(height: 1.65))),
            ],
          ),
        ),
      );
}
