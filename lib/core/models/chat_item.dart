class ChatItem {
  final String id;
  final String title;
  final DateTime created;

  ChatItem({required this.id, required this.title, required this.created});

  ChatItem copyWith({String? id, String? title, DateTime? created}) =>
      ChatItem(id: id ?? this.id, title: title ?? this.title, created: created ?? this.created);
}

