import 'dart:io';
import 'package:gemini_formatter/source_file.dart';

/// Utility class for loading source files from a directory.
class SourceFileBinding {

  /// Recursively loads all files under [entryDir] and
  /// returns them as a list of [SourceFile] instances.
  /// Throws an exception if [entryDir] does not exist.
  static List<SourceFile> load(Directory entryDir) {
    if (!entryDir.existsSync()) {
      throw Exception("Directory '${entryDir.path}' does not exist.");
    }

    final files = <SourceFile>[];

    /// Helper function to traverse directories recursively.
    void collectFiles(Directory dir) {
      for (var entity in dir.listSync()) {
        if (entity is File) {

          // Read file content and create a SourceFile instance
          final content = entity.readAsStringSync();
          files.add(SourceFile(path: entity.path, text: content));
        } else if (entity is Directory) {

          // Recursively collect files from subdirectories
          collectFiles(entity);
        }
      }
    }

    collectFiles(entryDir);
    return files;
  }

  /// Handles a given file system [path] by calling the appropriate callback.
  static void handlePath({
    required String path,
    required Function(File) onFile,
    required Function(Directory) onDirectory,
  }) {
    final entity = FileSystemEntity.typeSync(path);

    switch (entity) {
      case FileSystemEntityType.file:
        onFile(File(path)); break;

      case FileSystemEntityType.directory:
        onDirectory(Directory(path)); break;

      default:
        throw Exception("The path does not exist: $path");
    }
  }
}
