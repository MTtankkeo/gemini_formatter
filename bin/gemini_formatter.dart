import 'dart:io';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:gemini_formatter/source_file_binding.dart';
import 'package:yaml/yaml.dart';
import 'package:path/path.dart';

/// Cleans AI output texts by removing Markdown code fences.
String removeCodeFences(String text) {
  return text.replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '').replaceAll('```', '');
}

/// Recursively searches parent directories starting from [startDir] to find 
/// the package root directory. (i.e., the directory containing pubspec.yaml).
Directory findPackageRoot(Directory startDir) {
  var dir = startDir;
  while (true) {
    final pubspec = File(join(dir.path, 'pubspec.yaml'));
    if (pubspec.existsSync()) {
      return dir;
    }
    if (dir.parent.path == dir.path) {
      throw Exception('The package root not found.');
    }
    dir = dir.parent;
  }
}

void main(List<String> arguments) {
  // Load configuration file, defaulting to gemini_formatter.yaml.
  final configPath = arguments.firstOrNull;
  final configFile = File(configPath ?? "gemini_formatter.yaml");
  final yamlString = configFile.readAsStringSync();
  final config = loadYaml(yamlString);

  // Validate required config fields.
  if (config["apiKey"] == "") {
    throw Exception("API Key is missing. Please set 'apiKey' in your config file.");
  }

  if (config["model"] == "") {
    throw Exception("AI model is missing. Please set 'model' in your config file.");
  }

  if (config["inputDir"] == "") {
    throw Exception("Input directory is missing. Please set 'inputDir' in your config file.");
  }

  if (config["promptsDir"] == "") {
    throw Exception("Prompts directory is missing. Please set 'promptsDir' in your config file.");
  }

  // Load input files and prompt templates.
  final inputDir = Directory(config["inputDir"]);
  final inputFiles = SourceFileBinding.load(inputDir);

  final promptsDir = Directory(config["promptsDir"]);
  final promptsFiles = SourceFileBinding.load(promptsDir);

  final packageDir = findPackageRoot(Directory(Platform.script.toFilePath()));
  final constraintsDir = Directory(join(packageDir.path, "./prompts"));
  final constraintsFiles = SourceFileBinding.load(constraintsDir);

  final stopwatchTotal = Stopwatch()..start(); // 전체 시간 측정

  () async {
    final model = GenerativeModel(
      apiKey: config["apiKey"],
      model: config["model"],
    );

    // Combine all system-level prompts. (constraints + templates)
    final systemPrompts = [
      ...constraintsFiles,
      ...promptsFiles,
    ].map((e) => e.text).join("\n\n");

    // Process each input file individually.
    for (var file in inputFiles) {
      final stopwatchFile = Stopwatch()..start();

      // Include all files as context for the AI.
      final sourcePrompts = inputFiles.map((file) {
        return "----------[FILE: ${file.path}]----------"
              "\n${file.text}\n"
              "----------[END FILE]----------";
      }).join("\n\n");

      // Prepare AI request for current files.
      final contents = [
        Content.text(systemPrompts),
        Content.text(sourcePrompts),
        Content.text("Must add comments to this specific file: ${file.path}"),
      ];

      // Generate AI output.
      final response = await model.generateContent(contents);

      // Write AI-annotated content back to file.
      final annotatedFile = File(file.path);
      final cleanupedText = removeCodeFences(response.text!);
      annotatedFile.writeAsStringSync(cleanupedText);
      stopwatchFile.stop();
      file.text = cleanupedText;

      print("${file.path} has been formatted by the AI in ${stopwatchFile.elapsed.inSeconds} seconds.");

      // Apply optional delay between requests to respect rate limits.
      if (config["requestDelaySeconds"] != null
       && config["requestDelaySeconds"] != 0) {
        final int delaySeconds = config["requestDelaySeconds"];
        print("Waiting for $delaySeconds seconds before formatting...");

        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }

    stopwatchTotal.stop();
    print("All files formatted in ${stopwatchTotal.elapsed.inSeconds} seconds.");
  }();
}
