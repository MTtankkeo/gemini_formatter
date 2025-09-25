import 'dart:io';

import 'package:args/args.dart';
import 'package:gemini_formatter/source_file.dart';
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
  final argParser = ArgParser()
    ..addOption(
      "config",
      abbr: "c",
      help: "Path to config file",
      defaultsTo: "gemini_formatter.yaml",
      mandatory: false
    );

  final argResults = argParser.parse(arguments);

  // Load configuration file, defaulting to gemini_formatter.yaml.
  final configPath = argResults["config"];
  final configFile = File(configPath);
  final yamlString = configFile.readAsStringSync();
  final config = loadYaml(yamlString);

  // Validate required config fields.
  if (config["apiKey"] == null
   || config["apiKey"] == "") {
    throw Exception("API Key is missing. Please set 'apiKey' in your config file.");
  }

  if (config["model"] == null
   || config["model"] == "") {
    throw Exception("AI model is missing. Please set 'model' in your config file.");
  }

  if (config["promptsDir"] == null
   || config["promptsDir"] == "") {
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

  // List of files to be formatted.
  final processFiles = <SourceFile>[];

  // Load process files from command-line argument.
  if (arguments.firstOrNull != null) {
    SourceFileBinding.handlePath(
      path: arguments.firstOrNull!,

      // Read the file content and add as a SourceFile.
      onFile: (file) {
        final source = SourceFile(path: file.path, text: file.readAsStringSync());
        processFiles.add(source);
      },

      // Load all files from the directory and add them to inputFiles.
      onDirectory: (dir) {
        processFiles.addAll(SourceFileBinding.load(dir));
      }
    );
  } else {
    processFiles.addAll(inputFiles);
  }

  final stopwatchTotal = Stopwatch()..start();
  final includeOtherInputs = (config["includeOtherInputs"] as bool?) ?? true;

  () async {
    final model = GenerativeModel(
      apiKey: config["apiKey"],
      model: config["model"],
    );

    // Combine all system-level prompts. (constraints + templates)
    final systemPrompts = [
      "----------[System Prompts Start]----------",
      "The following are absolute rules and MUST be followed strictly without exception.\n",
      "Do NOT use the official formatter(e.g. Dart) style. Follow ONLY the rules written below.\n",
      "If there is any conflict, the rules below ALWAYS take precedence over any other style.\n",
      "",
      ...constraintsFiles.map((e) => e.text),
      ...promptsFiles.map((e) => e.text),
      "\n",
      "----------[System Prompts End]----------",
    ].join("\n\n");

    // Process each input file individually.
    for (int i = 0; i < processFiles.length; i++) {
      final file = processFiles[i];
      final isLast = i == processFiles.length - 1;
      final stopwatchFile = Stopwatch()..start();

      String convertToContext(SourceFile source) {
        return "----------[FILE: ${source.path}]----------"
               "\n${source.text}\n"
               "----------[END FILE]----------";
      }

      // Include all files as context for the AI.
      final sourcePrompts = includeOtherInputs
        ? inputFiles.map(convertToContext).join("\n\n")
        : convertToContext(file);

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

      final message = "${file.path} has been formatted by the AI in ${stopwatchFile.elapsed.inSeconds} seconds.";
      final current = "(${i + 1}/${processFiles.length})";
      print("$message $current");

      // Apply optional delay between requests to respect rate limits.
      if (config["requestDelaySeconds"] != null
       && config["requestDelaySeconds"] != 0
       && isLast == false) {
        final int delaySeconds = config["requestDelaySeconds"];
        print("Waiting for $delaySeconds seconds before formatting...");

        await Future.delayed(Duration(seconds: delaySeconds));
      }
    }

    stopwatchTotal.stop();
    print("All files formatted in ${stopwatchTotal.elapsed.inSeconds} seconds.");
  }();
}
