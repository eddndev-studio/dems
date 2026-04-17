import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class EvaluationPage extends ConsumerWidget {
  const EvaluationPage({super.key, required this.prototipoId});

  final String prototipoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Evaluación')),
      body: Center(child: Text('Prototipo: $prototipoId')),
    );
  }
}
