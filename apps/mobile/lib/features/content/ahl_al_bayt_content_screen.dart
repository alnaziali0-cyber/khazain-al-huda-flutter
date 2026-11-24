import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AhlAlBaytContentScreen extends StatelessWidget {
  const AhlAlBaytContentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                'الزيارات والأدعية',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              const Text('مكتبة نصية محلية للأدعية والزيارات، مع مواد تعريفية وقصص تربوية.'),
              const SizedBox(height: 18),
              _SectionAction(
                icon: Icons.account_balance_rounded,
                title: 'الزيارات',
                subtitle: 'نصوص ومقتطفات محلية موثقة',
                onTap: () => context.push('/visits'),
              ),
              const SizedBox(height: 10),
              _SectionAction(
                icon: Icons.volunteer_activism_rounded,
                title: 'الأدعية',
                subtitle: 'مقتطفات أدعية وبطاقات إرشادية',
                onTap: () => context.push('/duas'),
              ),
              const SizedBox(height: 10),
              _SectionAction(
                icon: Icons.menu_book_rounded,
                title: 'موسوعة زيارات المعصومين',
                subtitle: 'مقتطفات الزيارات وآدابها',
                onTap: () => context.push('/visits'),
              ),
              const SizedBox(height: 10),
              _SectionAction(
                icon: Icons.auto_stories_rounded,
                title: 'قصص تربوية',
                subtitle: 'حكايات خيالية أصلية، وليست روايات تاريخية',
                onTap: () => context.push('/stories'),
              ),
              const SizedBox(height: 10),
              _SectionAction(
                icon: Icons.people_alt_rounded,
                title: 'سيرة أهل البيت',
                subtitle: 'بيانات تعريفية محلية من الحزمة',
                onTap: () => context.push('/imams'),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

class _SectionAction extends StatelessWidget {
  const _SectionAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding:
            const EdgeInsetsDirectional.fromSTEB(16, 10, 12, 10),
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(icon, color: theme.colorScheme.onSecondaryContainer),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: onTap,
      ),
    );
  }
}
