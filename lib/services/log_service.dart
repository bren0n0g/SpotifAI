import 'package:flutter/material.dart';

class LogService {
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;
  LogService._internal();

  final List<String> _logs = [];
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);
  
  // O megafone: avisa a HomePage quando um log novo chega
  Function(String)? onNewLog;

  void add(String message) {
    // Removemos a geração da variável 'time' e deixamos o log apenas com a mensagem pura
    final log = message;
    
    _logs.insert(0, log); 
    logsNotifier.value = List.from(_logs); 
    print(log); // Continua imprimindo no console do VS Code se você precisar

    // Dispara o log em tempo real para o Chat
    onNewLog?.call(log);
  }
}