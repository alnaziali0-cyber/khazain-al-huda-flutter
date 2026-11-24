import 'package:flutter/material.dart';

import '../dev_panel_screen.dart';

/// The dev log: every action performed in the panel, newest first.
class LogTab extends StatelessWidget {
  const LogTab({super.key, required this.log});

  final DevLogController log;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: log,
      builder: (context, _) {
        final entries = log.entries;
        if (entries.isEmpty) {
          return const Center(
            child: Text(
              'لا توجد عمليات مسجّلة بعد.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          itemCount: entries.length,
          itemBuilder: (context, index) => Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A2A2A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              entries[index],
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        );
      },
    );
  }
}
