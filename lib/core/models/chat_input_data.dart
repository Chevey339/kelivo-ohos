class DocumentAttachment {
  final String path; // absolute file path
  final String fileName;
  final String mime; // e.g. application/pdf, text/plain

  const DocumentAttachment({required this.path, required this.fileName, required this.mime});
}

class ChatInputData {
  final String text;
  final List<String> imagePaths; // absolute file paths or data URLs
  final List<DocumentAttachment> documents; // selected files

  const ChatInputData({
    required this.text,
    this.imagePaths = const [],
    this.documents = const [],
  });
}
