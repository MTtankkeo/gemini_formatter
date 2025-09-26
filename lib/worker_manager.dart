import 'dart:collection';
import 'package:gemini_formatter/source_file.dart';
import 'package:gemini_formatter/worker.dart';

/// Manages multiple Workers and distributes files across them
/// using a shared queue. Each Worker is tied to a unique API key.
class WorkerManager {
  WorkerManager({
    required this.apiKeys,
    required this.model,
    required this.systemPrompts,
    required this.contextFiles,
    required this.processFiles,
    required this.batchSize,
    required this.delaySeconds,
    required this.includeOtherInputs,
  });

  /// List of API keys, each used to create a dedicated Worker.
  final List<String> apiKeys;

  /// Model name used for AI requests.
  final String model;

  /// System-level prompts shared across all Workers.
  final String systemPrompts;

  /// Context files included in AI requests for reference.
  final List<SourceFile> contextFiles;

  /// Files that need to be processed and formatted by AI.
  final List<SourceFile> processFiles;

  /// Maximum number of files a Worker processes at once.
  final int batchSize;

  /// Delay (in seconds) applied between requests for each Worker.
  final int delaySeconds;

  /// Whether to include other files as context when processing.
  final bool includeOtherInputs;

  /// Tracks how many files have been fully processed.
  int completedCount = 0;

  /// Runs all Workers concurrently and waits for completion.
  Future<void> perform() async {
    final queue = Queue<SourceFile>.from(processFiles);

    final workers = apiKeys.map((apiKey) {
      return Worker(
        apiKey: apiKey,
        model: model,
        systemPrompts: systemPrompts,
        contextFiles: contextFiles,
        includeOtherInputs: includeOtherInputs,
      );
    }).toList();

    final tasks = workers.map((worker) => _runWorker(worker, queue)).toList();

    await Future.wait(tasks);
  }

  /// Continuously pulls batches from the queue and assigns
  /// them to the given Worker until the queue is empty.
  Future<void> _runWorker(Worker worker, Queue<SourceFile> queue) async {
    while (queue.isNotEmpty) {
      final batch = <SourceFile>[];
      for (var i = 0; i < batchSize && queue.isNotEmpty; i++) {
        batch.add(queue.removeFirst());
      }

      await worker.perform(
        files: batch,
        onCompleted: onCompleted,
      );

      // Apply delay per API key after each batch.
      if (queue.isNotEmpty && delaySeconds > 0) {
        print("API Key ${worker.apiKey.substring(0, 8)}... waiting for $delaySeconds seconds...");
        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }
  }

  /// Callback invoked when a file has been processed,
  /// logs progress with elapsed time.
  void onCompleted(SourceFile file, Duration elapsed) {
    completedCount += 1;
    final message = "${file.path} has been formatted by AI in ${elapsed.inSeconds} seconds.";
    final current = "($completedCount/${processFiles.length})";
    print("$message $current");
  }
}
