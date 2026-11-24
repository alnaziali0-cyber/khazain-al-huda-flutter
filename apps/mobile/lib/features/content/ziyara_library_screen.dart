import 'package:flutter/material.dart';
import 'local_text_library.dart';

/// Local, offline text index for licensed visit excerpts and editorial guides.
class ZiyaraLibraryScreen extends StatelessWidget {
  const ZiyaraLibraryScreen({super.key, this.initialSearch});

  final String? initialSearch;

  @override
  Widget build(BuildContext context) => LocalTextLibraryScreen(
        category: 'visit',
        title: 'موسوعة الزيارات',
        initialSearch: initialSearch,
      );
}

/// Legacy deep links remain valid and resolve through the local text catalogue.
class ZiyaraVolumeTextScreen extends StatelessWidget {
  const ZiyaraVolumeTextScreen({super.key, required this.volumeId});

  final String volumeId;

  @override
  Widget build(BuildContext context) => LocalTextReaderScreen(entryId: volumeId);
}
