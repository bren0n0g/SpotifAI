import 'package:hive/hive.dart';

part 'conversation.g.dart'; // Você precisará rodar o build_runner depois, ou remova se preferir usar Map puro

@HiveType(typeId: 0)
class Message {
  @HiveField(0)
  final String text;
  @HiveField(1)
  final bool isUser;
  @HiveField(2)
  final DateTime timestamp;

  Message({required this.text, required this.isUser, DateTime? timestamp}) 
    : timestamp = timestamp ?? DateTime.now();
}

@HiveType(typeId: 1)
class Conversation {
  @HiveField(0)
  final String id;
  @HiveField(1)
  String title;
  @HiveField(2)
  List<Message> messages;
  @HiveField(3)
  List<Map<String, String>> lastPlaylistTracks;

  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    this.lastPlaylistTracks = const [],
  });
}