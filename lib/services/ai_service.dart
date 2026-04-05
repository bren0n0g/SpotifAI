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

  /// Transforma a lista de artistas favoritos do usuário em 6 botões de "Vibes"
  Future<List<String>> generateDynamicVibes(List<String> topArtists) async {
    // 1. O Plano B: Se tudo der errado, o usuário não percebe e vê botões genéricos
    final List<String> fallbackVibes = [
      "🔥 Pop Hits", 
      "🎸 Rock & Energia", 
      "🛋️ Lo-Fi Relax", 
      "🎤 Rap & Hip-Hop", 
      "💃 Batida Eletrônica", 
      "🎲 Surpreenda-me"
    ];

    // Se o Spotify não devolveu artistas (ex: conta nova sem histórico), usa o Plano B
    if (topArtists.isEmpty) {
      LogService().add('⚠️ AI: Sem artistas base. Usando vibes padrão.');
      return fallbackVibes;
    }

    // 2. O Prompt Cirúrgico
    String prompt = """
    Você é um curador musical especialista em UX. O usuário costuma ouvir estes artistas: ${topArtists.join(', ')}.
    Crie 5 categorias (vibes musicais) curtas, criativas e altamente atraentes baseadas NESSE gosto específico.
    Regras estritas:
    - Máximo de 3 palavras por categoria.
    - Pode (e deve) usar 1 emoji no início de cada uma.
    - A 6ª categoria DEVE ser obrigatoriamente a string exata: "🎲 Surpreenda-me".
    
    IMPORTANTE: Responda APENAS com um array JSON válido contendo as 6 strings. Zero explicações.
    Exemplo do formato exigido:
    ["🎸 Rock Clássico", "🌧️ Sad R&B", "🕺 Swing Pop", "🤠 Modão Raiz", "🎧 Foco Total", "🎲 Surpreenda-me"]
    """;

    try {
      LogService().add('🧠 AI: Analisando artistas para gerar botões dinâmicos...');
      
      // Chama a nossa nova função de apoio interna
      String responseText = await _generateTextFromGemini(prompt); 
      
      // 3. Sanitização Bruta
      responseText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      
      // 4. Transformação
      List<dynamic> decodedArray = jsonDecode(responseText);
      List<String> vibes = decodedArray.map((e) => e.toString()).toList();
      
      if (vibes.length >= 6) {
        LogService().add('✅ AI: Botões dinâmicos gerados com sucesso!');
        return vibes.take(6).toList(); 
      }
      
      return fallbackVibes;
    } catch (e) {
      LogService().add('❌ ERRO AI: Falha ao gerar botões (usando fallback): $e');
      return fallbackVibes;
    }
  }

  /// Função interna de apoio para chamadas rápidas e diretas ao Gemini (Sem instruções do modo Playlist)
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
            "response_mime_type": "application/json" // Força o JSON para garantir o array de strings
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