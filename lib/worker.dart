import 'dart:io';
import 'dart:async';

import 'package:gemini_formatter/source_file.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Signature for the callback that is invoked when a file
/// has been processed by a Worker, providing the file and
/// the elapsed processing time.
typedef WorkerCompletedCallback = void Function(
    SourceFile file, Duration elapsed);

/// Cleans AI output texts by removing Markdown code fences.
String removeCodeFences(String text) {
  return text.replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '').replaceAll('```', '');
}

/// Worker class that handles processing files with a specific API key
class Worker {
  final String apiKey;
  final String model;
  final String systemPrompts;
  final List<SourceFile> contextFiles;
  final bool includeOtherInputs;

  late GenerativeModel _model;

  Worker({
    required this.apiKey,
    required this.model,
    required this.systemPrompts,
    required this.contextFiles,
    required this.includeOtherInputs,
  }) {
    _model = GenerativeModel(
      apiKey: apiKey,
      model: model,
    );
  }

  Future<void> perform({
    required List<SourceFile> files,
    required WorkerCompletedCallback onCompleted,
  }) async {
    await Future.wait([
      for (final file in files) _processFile(file, onCompleted),
    ]);
  }

  /// Process a single file with this API key.
  Future<void> _processFile(
      SourceFile file, WorkerCompletedCallback onCompleted) async {
    final stopwatchFile = Stopwatch()..start();

    String convertToContext(SourceFile source) {
      return "----------[FILE: ${source.path}]----------"
          "\n${source.text}\n"
          "----------[END FILE]----------";
    }

    // Include all files as context for the AI or just the current file.
    final contextPrompts = includeOtherInputs
        ? contextFiles.map(convertToContext).join("\n\n")
        : convertToContext(file);

    // Prepare AI request for current file.
    final contents = [
      Content.text(systemPrompts),
      Content.text(contextPrompts),
      Content.text("Must add comments to this specific file: ${file.path}"),
    ];

    // Generate AI output.
    final response = await _model.generateContent(contents);

    // Write AI-annotated content back to file.
    final annotatedFile = File(file.path);
    final cleanupedText = removeCodeFences(response.text!);
    file.text = cleanupedText;
    annotatedFile.writeAsStringSync(cleanupedText);
    stopwatchFile.stop();

    onCompleted.call(file, stopwatchFile.elapsed);
  }
}
