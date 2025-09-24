import 'dart:io';
import 'package:gemini_formatter/source_file.dart';

class SourceFileBinding {
  /// Recursively load all Dart files under [entryDir] and return as SourceFile list.
  static List<SourceFile> load(Directory entryDir) {
    if (!entryDir.existsSync()) {
      throw Exception("Directory '${entryDir.path}' does not exist.");
    }

    final files = <SourceFile>[];

    void collectFiles(Directory dir) {
      for (var entity in dir.listSync()) {
        if (entity is File) {
          final content = entity.readAsStringSync();
          files.add(SourceFile(path: entity.path, text: content));
        } else if (entity is Directory) {
          collectFiles(entity);
        }
      }
    }

    collectFiles(entryDir);
    return files;
  }
}
