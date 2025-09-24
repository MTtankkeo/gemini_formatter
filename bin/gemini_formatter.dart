import 'dart:convert';
import 'dart:io';

import 'package:gemini_formatter/source_file.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:gemini_formatter/source_file_binding.dart';
import 'package:yaml/yaml.dart';

String cleanJson(String text) {
  return text.replaceAll(RegExp(r'```[a-zA-Z]*\n?'), '').replaceAll('```', '');
}

void main(List<String> arguments) {
  final configPath = arguments.firstOrNull;
  final configFile = File(configPath ?? "config.yaml");
  final yamlString = configFile.readAsStringSync();
  final config = loadYaml(yamlString);

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

  final inputDir = Directory(config["inputDir"]);
  final inputFiles = SourceFileBinding.load(inputDir);

  final promptsDir = Directory(config["promptsDir"]);
  final promptsFiles = SourceFileBinding.load(promptsDir);

  final constraintsDir = Directory("../prompts");
  final constraintsFiles = SourceFileBinding.load(constraintsDir);

  () async {
    final model = GenerativeModel(
      apiKey: config["apiKey"],
      model: config["model"],
    );

    final systemPrompts = [
      ...constraintsFiles,
      ...promptsFiles,
    ].map((e) => e.text).join("\n\n");

    final sourcePrompts = inputFiles.map((file) {
      return "----------[FILE: ${file.path}]----------"
             "\n${file.text}\n"
             "----------[END FILE]----------";
    }).join("\n\n");

    final contents = [
      Content.text(systemPrompts),
      Content.text(sourcePrompts),
    ];

    final response = await model.generateContent(contents);
    final jsonList = jsonDecode(cleanJson(response.text!)) as List;
    final jsonFile = jsonList.map((json) => SourceFile.fromJson(json));

    for (var output in jsonFile) {
      final file = File(output.path);
      file.writeAsStringSync(output.text);
    }

    print("A total of ${jsonFile.length} files have been formatted by the AI.");
  }();
}
