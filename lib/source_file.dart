class SourceFile {
  SourceFile({
    required this.path,
    required this.text,
  });

  String path;
  String text;

  factory SourceFile.fromJson(Map<String, dynamic> json) {
    return SourceFile(path: json["path"], text: json["text"]);
  }
}
