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

  O título deve ter até 17 dígitos + " SpotifAI"
  ''';

  /// Geração da Playlist Completa (O Motor Principal)
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

  /// -------------------------------------------------------------------------
  /// NOVAS FUNÇÕES: MODO "ESTOU COM SORTE" (COPILOTO GUIADO)
  /// -------------------------------------------------------------------------

  /// Transforma a lista de artistas favoritos do usuário em 6 botões detalhados
  Future<List<Map<String, dynamic>>> generateDynamicVibes(List<String> topArtists, {String? userHint}) async {
    final List<Map<String, dynamic>> fallbackVibes = List.generate(6, (index) => {"vibe": "🎧 Vibe Padrão", "artists": ["Artista 1"]});
    if (topArtists.isEmpty) return fallbackVibes;

    // Se o usuário der um pitaco no chat, a IA recebe essa instrução extra
    String hintInstruction = userHint != null && userHint.isNotEmpty 
        ? "\nREGRA EXTRA DO USUÁRIO: O usuário pediu a seguinte modificação nas opções: '$userHint'. Ajuste as 5 categorias para respeitar estritamente esse pedido." 
        : "";

    String prompt = """
    Você é um curador musical. O usuário ouve: ${topArtists.join(', ')}.$hintInstruction
    Crie 5 categorias (vibes musicais) curtas com base no gosto dele (ou no pedido extra, se houver). 
    A 6ª categoria DEVE ser "🎲 Surpreenda-me".
    Para CADA categoria, escolha exatamente 3 artistas que representem essa vibe.
    
    IMPORTANTE: Responda APENAS com um array JSON. Sem formatação markdown.
    Exemplo exato:
    [
      {"vibe": "🎸 Rock Clássico", "artists": ["AC/DC", "Queen", "Led Zeppelin"]}
    ]
    """;

    try {
      LogService().add('🧠 AI: Gerando grade de vibes...');
      String responseText = await _generateTextFromGemini(prompt); 
      responseText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      List<dynamic> decodedArray = jsonDecode(responseText);
      List<Map<String, dynamic>> vibes = decodedArray.map((e) => {
        "vibe": e["vibe"].toString(),
        "artists": (e["artists"] as List).map((a) => a.toString()).toList()
      }).toList();
      
      if (vibes.length >= 6) return vibes.take(6).toList(); 
      return fallbackVibes;
    } catch (e) {
      return fallbackVibes;
    }
  }
  /// Função interna de apoio para chamadas rápidas e diretas ao Gemini
  Future<String> _generateTextFromGemini(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('$_workerUrl/v1beta/models/gemini-2.5-flash:generateContent'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
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
        return data['candidates'][0]['content']['parts'][0]['text'];
      } else {
        throw Exception('HTTP ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      rethrow;
    }
  }
}