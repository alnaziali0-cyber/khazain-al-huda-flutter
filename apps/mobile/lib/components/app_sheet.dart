import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/theme_provider.dart';
import '../design/tokens/app_tokens.dart';
import 'app_text.dart';

/// The standard bottom sheet used for support, dev panel and pickers.
class KzSheet extends ConsumerWidget {
  const KzSheet({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.showHandle = true,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final bool showHandle;

  /// Shows the sheet with the standard radius and dark surface.
  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required WidgetBuilder builder,
    List<Widget>? actions,
    bool isScrollControlled = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      backgroundColor: Colors.transparent,
      barrierColor: KhazainColors.scrim,
      builder: (context) => KzSheet(
        title: title,
        actions: actions,
        child: Builder(builder: builder),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(uiThemeProvider);
    final media = MediaQuery.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.color('surface1'),
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(theme.sheetRadius),
        ),
        border: Border(
          top: BorderSide(color: theme.color('hairline')),
          left: BorderSide(color: theme.color('hairline')),
          right: BorderSide(color: theme.color('hairline')),
        ),
      ),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showHandle)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.color('divider'),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: AppText(
                        title,
                        token: 'h2',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (actions != null) ...actions!,
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      tooltip: 'إغلاق',
                      icon: Icon(
                        Icons.close_rounded,
                        color: theme.color('textMuted'),
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list of selectable options inside a sheet.
class KzOptionList extends StatelessWidget {
  const KzOptionList({
    super.key,
    required this.options,
    required this.onSelected,
    this.selectedId,
  });

  final List<({String id, String label, String? hint})> options;
  final ValueChanged<String> onSelected;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: AppText(option.label, token: 'body'),
            subtitle: option.hint == null
                ? null
                : AppText(option.hint!, token: 'bodyDim'),
            trailing: option.id == selectedId
                ? const Icon(Icons.check_rounded, size: 20)
                : null,
            onTap: () => onSelected(option.id),
          ),
      ],
    );
  }
}
