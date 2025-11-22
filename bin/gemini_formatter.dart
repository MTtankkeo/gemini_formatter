import 'dart:io';

import 'package:args/args.dart';
import 'package:gemini_formatter/source_file.dart';
import 'package:gemini_formatter/worker_manager.dart';
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
  final argParser = ArgParser()
    ..addOption("config",
        abbr: "c",
        help: "Path to config file",
        defaultsTo: "gemini_formatter.yaml",
        mandatory: false);

  final argResults = argParser.parse(arguments);

  // Load configuration file, defaulting to gemini_formatter.yaml.
  final configPath = argResults["config"];
  final configFile = File(configPath);
  final yamlString = configFile.readAsStringSync();
  final config = loadYaml(yamlString);

  // Validate required config fields.
  if (config["apiKey"] == null ||
      config["apiKey"] == "" ||
      config["apiKey"] == []) {
    throw Exception(
        "API Key is missing. Please set 'apiKey' in your config file.");
  }

  if (config["model"] == null || config["model"] == "") {
    throw Exception(
        "AI model is missing. Please set 'model' in your config file.");
  }

  if (config["contextDir"] == null || config["contextDir"] == "") {
    throw Exception(
      "Prompts directory is missing. Please set 'contextDir' in your config file.",
    );
  }

  if (config["promptsDir"] == null || config["promptsDir"] == "") {
    throw Exception(
      "Prompts directory is missing. Please set 'promptsDir' in your config file.",
    );
  }

  // Load context files and prompt templates.
  final contextDir = Directory(config["contextDir"]);
  final contextFiles = SourceFileBinding.load(contextDir);

  final promptsDir = Directory(config["promptsDir"]);
  final promptsFiles = SourceFileBinding.load(promptsDir);
  final apiKeys = <String>[];

  // List of files to be formatted.
  final processFiles = <SourceFile>[];

  // Add API keys from the config, supporting both single string and list of strings.
  if (config["apiKey"] is String) {
    apiKeys.add(config["apiKey"]);
  } else if (config["apiKey"] is YamlList) {
    apiKeys.addAll((config["apiKey"] as YamlList).cast<String>());
  } else {
    throw Exception("Invalid or missing API Key.");
  }

  if (apiKeys.isEmpty) {
    throw Exception("No valid API keys found.");
  }

  // Load process files from command-line argument.
  if (arguments.firstOrNull != null) {
    SourceFileBinding.handlePath(
      path: arguments.firstOrNull!,

      // Read the file content and add as a SourceFile.
      onFile: (file) {
        final source =
            SourceFile(path: file.path, text: file.readAsStringSync());
        processFiles.add(source);
      },

      // Load all files from the directory and add them to contextFiles.
      onDirectory: (dir) {
        processFiles.addAll(SourceFileBinding.load(dir));
      },
    );
  } else {
    processFiles.addAll(contextFiles);
  }

  final batchSize = (config["batchSize"] as int?) ?? 1;
  final delaySeconds = (config["requestDelaySeconds"] as int?) ?? 0;
  final includeOtherInputs = (config["includeOtherInputs"] as bool?) ?? true;

  final stopwatchTotal = Stopwatch()..start();

  () async {
    // Combine all system-level prompts. (constraints + templates)
    final systemPrompts = [
      "----------[System Prompts Start]----------",
      "The following are absolute rules and MUST be followed strictly without exception.\n",
      "Do NOT use the official formatter(e.g. Dart) style. Follow ONLY the rules written below.\n",
      "If there is any conflict, the rules below ALWAYS take precedence over any other style.\n",
      "",
      "Format the following code strictly according to the rules below.",
      "Do NOT use any default or official formatter style.",
      "Preserve all code exactly as given.",
      "",
      "Critical rules (no exceptions):",
      "1. NEVER remove, change, or reorder any import/include statements. All imports/includes must remain exactly as in the original file.",
      "2. NEVER remove, change, or rename any other code (functions, variables, classes, logic).",
      "3. NEVER omit or skip any line. The output must include the entire file exactly as given.",
      "4. ONLY adjust formatting or add comments to improve readability. No other modifications are allowed.",
      "5. The code’s functionality must remain 100% identical to the original.",
      "6. Output only the raw code, without Markdown code blocks (```) or JSON wrapping.",
      "",
      ...promptsFiles.map((e) => e.text),
      "\n",
      "----------[System Prompts End]----------",
    ].join("\n\n");

    await WorkerManager(
            apiKeys: apiKeys,
            model: config["model"],
            systemPrompts: systemPrompts,
            contextFiles: contextFiles,
            processFiles: processFiles,
            batchSize: batchSize,
            delaySeconds: delaySeconds,
            includeOtherInputs: includeOtherInputs)
        .perform();

    stopwatchTotal.stop();
    print(
      "All files formatted in ${stopwatchTotal.elapsed.inSeconds} seconds.",
    );
  }();
}
