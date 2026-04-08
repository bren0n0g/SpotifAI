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

  Future<Map<String, dynamic>?> generatePlaylist(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('$_workerUrl/v1beta/models/gemini-3.1-pro:generateContent'), 
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

  /// Transforma a lista de artistas favoritos do usuário em 10 botões detalhados
  Future<List<Map<String, dynamic>>> generateDynamicVibes(List<String> topArtists, {String? userHint}) async {
    // 🔥 MUDANÇA: Sem "fallbackVibes" (A boia de salvação falsa). 
    // Se não tiver artistas, ele trava e lança um erro para a tela vermelha.
    if (topArtists.isEmpty) throw Exception('Seu histórico do Spotify está vazio ou inacessível.');

    String hintInstruction = userHint != null && userHint.isNotEmpty 
        ? "\nREGRA EXTRA DO USUÁRIO: O usuário pediu a seguinte modificação nas opções: '$userHint'. Ajuste as 9 categorias para respeitar estritamente esse pedido." 
        : "";

    String prompt = """
    Você é um curador musical. O usuário ouve: ${topArtists.join(', ')}.$hintInstruction
    Crie 9 categorias (vibes musicais) curtas com base no gosto dele (ou no pedido extra, se houver). 
    A 10ª categoria DEVE ser "🎲 Surpreenda-me".
    Para CADA categoria, escolha exatamente 3 artistas que representem essa vibe.
    
    IMPORTANTE: Responda APENAS com um array JSON contendo EXATAMENTE 10 objetos. Sem formatação markdown.
    Exemplo exato:
    [
      {"vibe": "🎸 Rock Clássico", "artists": ["AC/DC", "Queen", "Led Zeppelin"]},
      {"vibe": "🌧️ Sad R&B", "artists": ["The Weeknd", "Joji", "Chase Atlantic"]}
    ]
    """;

    try {
      LogService().add('🧠 AI: Gerando grade expandida de vibes (10 opções)...');
      String responseText = await _generateTextFromGemini(prompt); 
      responseText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      List<dynamic> decodedArray = jsonDecode(responseText);
      List<Map<String, dynamic>> vibes = decodedArray.map((e) => {
        "vibe": e["vibe"].toString(),
        "artists": (e["artists"] as List).map((a) => a.toString()).toList()
      }).toList();
      
      if (vibes.length >= 10) return vibes.take(10).toList(); 
      throw Exception('A IA não gerou as 10 categorias corretamente.');
    } catch (e) {
      LogService().add('❌ ERRO AI: $e');
      rethrow; // 🔥 Repassa o erro para o Flutter mostrar o aviso na tela e abortar.
    }
  }

  /// Traduz uma vibe manual em 2 artistas para servir de semente no Spotify
  Future<List<String>> getArtistsForVibe(String vibe) async {
    String prompt = "O usuário quer uma playlist com a vibe: '$vibe'. Me retorne APENAS um array JSON com os nomes de 2 artistas reais do Spotify que representem essa vibe perfeitamente. Exemplo: [\"The Weeknd\", \"Kavinsky\"]. Nenhuma outra palavra.";
    try {
      String responseText = await _generateTextFromGemini(prompt);
      responseText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      List<dynamic> decodedArray = jsonDecode(responseText);
      return decodedArray.map((e) => e.toString()).toList();
    } catch (e) {
      return ["Coldplay", "The Weeknd"]; 
    }
  }

  Future<String> _generateTextFromGemini(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('$_workerUrl/v1beta/models/gemini-3.1-flash:generateContent'),
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