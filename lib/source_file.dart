class SourceFile {
  const SourceFile({
    required this.path,
    required this.text,
  });

  final String path;
  final String text;

  factory SourceFile.fromJson(Map<String, dynamic> json) {
    return SourceFile(path: json["path"], text: json["text"]);
  }
}
