import 'dart:convert';
import 'package:http/http.dart' as http;
import 'log_service.dart';

class AiService {
  static final AiService _instance = AiService._internal();
  factory AiService() => _instance;
  AiService._internal();

  // ⚠️ COLOQUE O LINK DO SEU WORKER AQUI (Sem barra / no final)
  final String _workerUrl = 'https://spotifai-proxy.brenomachado2003.workers.dev';

  final String systemInstruction = '''
  Você é um curador musical especialista e um assistente conversacional.
  O usuário enviará o histórico da conversa, o estado atual da playlist e um novo pedido.
  
  MODOS DE OPERAÇÃO:
  
  1. MODO CRIADOR (Quando o estado atual for "Nenhuma playlist carregada"): 
  Seja criativo. A lista padrão deve ter 10 músicas, mas se for pedido pode ir até 50 músicas reais que existam no Spotify.
  
  2. MODO EDITOR (Quando o prompt contiver a "PLAYLIST ATUAL NO SISTEMA"): 
  Aja como um AGENTE DE SOFTWARE RESTRITO E LITERAL. Se o usuário pedir para remover um artista ou uma característica (ex: "ao vivo"), você DEVE:
  - Remover APENAS o que foi explicitamente pedido.
  - REPETIR TODAS AS OUTRAS MÚSICAS EXATAMENTE COMO ESTÃO NA LISTA ATUAL.
  - NUNCA adicionar músicas novas a menos que seja solicitado.
  - NUNCA truncar ou diminuir a playlist.
  
  Você DEVE retornar APENAS um JSON estrito com esta estrutura dupla:
  {
    "chat_reply": "Sua resposta natural para o usuário",
    "playlist_update": {
      "title": "Nome criativo",
      "tracks": [
        {"title": "Nome da Música", "artist": "Nome do Artista"}
      ]
    }
  }
  ''';

  Future<Map<String, dynamic>?> generatePlaylist(String prompt) async {
    LogService().add('🚀 AI: Disparando prompt para a nuvem da Cloudflare...');

    try {
      final response = await http.post(
        Uri.parse('$_workerUrl/v1beta/models/gemini-2.5-flash:generateContent'), 
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "system_instruction": {
            "parts": [{"text": systemInstruction}]
          },
          "contents": [{
            "parts": [{"text": prompt}]
          }],
          "generationConfig": {
            "response_mime_type": "application/json"
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final content = data['candidates'][0]['content']['parts'][0]['text'];
        LogService().add('✅ AI: Resposta recebida em segurança da nuvem!');
        return jsonDecode(content);
      } else {
        LogService().add('❌ AI ERRO HTTP: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      LogService().add('❌ AI EXCEÇÃO: $e');
      return null;
    }
  }
}