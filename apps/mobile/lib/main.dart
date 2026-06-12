import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/server_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final savedServerUrl = await readPersistedServerUrl();
  runApp(
    ProviderScope(
      overrides: [
        if (savedServerUrl != null)
          initialServerUrlProvider.overrideWithValue(savedServerUrl),
      ],
      child: const DemsApp(),
    ),
  );
}
