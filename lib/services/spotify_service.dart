import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'log_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal();

  String? _accessToken;
  bool get isLogged => _accessToken != null;

  final String _apiBase = utf8.decode(base64Decode('aHR0cHM6Ly9hcGkuc3BvdGlmeS5jb20vdjE='));
  final String _accountsDomain = utf8.decode(base64Decode('YWNjb3VudHMuc3BvdGlmeS5jb20='));

  // --- ADICIONADO: FUNÇÕES DE MEMÓRIA DO TOKEN ---
  
  // Salva o token no navegador
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotify_token', token);
  }

  // Tenta puxar o token quando o app abre
  Future<bool> loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('spotify_token');
    if (token != null && token.isNotEmpty) {
      _accessToken = token;
      LogService().add('✅ SPOTIFY: Sessão restaurada da memória.');
      return true;
    }
    return false;
  }

  // Apaga o token (Logout)
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_token');
    _accessToken = null;
    LogService().add('⚠️ SPOTIFY: Sessão encerrada.');
  }
  // ------------------------------------------------

  Future<bool> authenticateUser() async {
    LogService().add('🔐 SPOTIFY: Iniciando fluxo de autenticação...');
    final clientId = dotenv.env['SPOTIFY_CLIENT_ID']!;
    final clientSecret = dotenv.env['SPOTIFY_CLIENT_SECRET']!;
    
    // O DESVIO INTELIGENTE: Se for Web, usa o localhost temporário. Se for Mobile, usa o .env
    final redirectUri = 'https://spotifai.brenomachado2003.workers.dev/callback.html';

    final String scope = 'playlist-modify-public playlist-modify-private playlist-read-private user-read-private user-read-email user-top-read';
    final url = Uri.https(_accountsDomain, '/authorize', {
      'client_id': clientId,
      'response_type': 'code',
      'redirect_uri': redirectUri,
      'scope': scope,
      'show_dialog': 'true', 
    });

    try {
      final result = await FlutterWebAuth2.authenticate(
        url: url.toString(),
        callbackUrlScheme: 'spotifai', 
      );

      final code = Uri.parse(result).queryParameters['code'];
      if (code == null) {
        LogService().add('❌ SPOTIFY: Código de autorização retornou nulo.');
        return false;
      }

      final tokenResponse = await http.post(
        Uri.https(_accountsDomain, '/api/token'),
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'Authorization': 'Basic ' + base64Encode(utf8.encode('$clientId:$clientSecret')),
        },
        body: {
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirectUri,
        },
      );

      if (tokenResponse.statusCode == 200) {
        final jsonResponse = jsonDecode(tokenResponse.body);
        _accessToken = jsonResponse['access_token'];
        
        // --- ADICIONADO: Salva o token assim que logar com sucesso ---
        await saveToken(_accessToken!);
        
        LogService().add('✅ SPOTIFY: Autenticado com sucesso!');
        return true;
      } else {
        LogService().add('❌ SPOTIFY API ERRO (Token): HTTP ${tokenResponse.statusCode}');
        return false;
      }
    } catch (e) {
      LogService().add('❌ SPOTIFY EXCEÇÃO (Login): $e');
      return false;
    }
  }

  Future<Map<String, String>?> searchTrack(String title, String artist) async {
    final query = 'track:$title artist:$artist';
    final response = await http.get(
      Uri.parse('$_apiBase/search?q=${Uri.encodeComponent(query)}&type=track&limit=1'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final tracks = data['tracks']['items'] as List;
      if (tracks.isNotEmpty) {
        return {
          'id': tracks[0]['uri'], 
          'image': tracks[0]['album']['images'][0]['url'], 
        };
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> importPlaylistFromUrl(String url) async {
    if (!isLogged) {
      LogService().add('❌ SPOTIFY: Conecte sua conta antes de importar.');
      return null;
    }

    try {
      final RegExp regExp = RegExp(r'playlist\/([a-zA-Z0-9]+)');
      final match = regExp.firstMatch(url);
      
      if (match == null) {
        LogService().add('❌ SPOTIFY: Link inválido. Copie o link direto da playlist.');
        return null;
      }
      
      final playlistId = match.group(1);
      LogService().add('⏳ SPOTIFY: Baixando playlist original (ID: $playlistId)...');

      final response = await http.get(
        Uri.parse('$_apiBase/playlists/$playlistId'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final title = data['name'] ?? 'Playlist Importada';
        final List<Map<String, String>> importedTracks = [];

        // O PULO DO GATO: A adaptação para a API V2 do Spotify
        // Ele tenta ler a gaveta nova ('items'), se não achar, tenta a antiga ('tracks')
        final rootItemsFolder = data['items'] ?? data['tracks'];

        if (rootItemsFolder != null && rootItemsFolder['items'] != null) {
          
          final trackList = rootItemsFolder['items'] as List;

          for (var element in trackList) {
            if (element == null) continue; 
            
            // Outra adaptação V2: Ele procura 'item', e se não achar procura 'track'
            final trackNode = element['item'] ?? element['track'];
            
            if (trackNode != null && trackNode['uri'] != null) {
              
              String artistName = 'Desconhecido';
              if (trackNode['artists'] != null && trackNode['artists'].isNotEmpty) {
                artistName = trackNode['artists'][0]['name'] ?? 'Desconhecido';
              }
              
              String imageUrl = '';
              if (trackNode['album'] != null && trackNode['album']['images'] != null && trackNode['album']['images'].isNotEmpty) {
                imageUrl = trackNode['album']['images'][0]['url'] ?? '';
              }

              importedTracks.add({
                'id': trackNode['uri'],
                'title': trackNode['name'] ?? 'Sem Título',
                'artist': artistName,
                'image': imageUrl,
                'locked': 'false', 
              });
            }
          }
        }
        
        LogService().add('✅ SPOTIFY: Playlist "$title" processada. Encontrou ${importedTracks.length} músicas compatíveis.');
        return {'title': title, 'tracks': importedTracks};
      } else {
        LogService().add('❌ SPOTIFY ERRO (Importação): HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      LogService().add('❌ SPOTIFY EXCEÇÃO (Importação): $e');
      return null;
    }
  }

  Future<bool> createAndPopulatePlaylist(String name, String description, List<String> trackUris) async {
    if (!isLogged) return false;

    try {
      LogService().add('⏳ SPOTIFY: Criando playlist na rota oficial /me/playlists...');
      String safeDescription = description.length > 3000 ? '${description.substring(0, 297)}...' : description;
      
      final createResponse = await http.post(
        Uri.parse('$_apiBase/me/playlists'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'description': safeDescription,
          'public': false, 
        }),
      );

      if (createResponse.statusCode != 201 && createResponse.statusCode != 200) {
        LogService().add('❌ SPOTIFY ERRO (Criação): HTTP ${createResponse.statusCode} - ${createResponse.body}');
        return false;
      }

      final playlistId = jsonDecode(createResponse.body)['id'];
      LogService().add('✅ SPOTIFY: Playlist oficializada (ID: $playlistId).');

      if (trackUris.isEmpty) {
        LogService().add('❌ SPOTIFY: Nenhuma música para injetar.');
        return false;
      }

      LogService().add('⏳ SPOTIFY: Injetando ${trackUris.length} faixas (Nova Rota V2)...');
      
      final addResponse = await http.post(
        Uri.parse('$_apiBase/playlists/$playlistId/items'), 
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'uris': trackUris}),
      );

      if (addResponse.statusCode != 201 && addResponse.statusCode != 200) {
        LogService().add('❌ SPOTIFY ERRO (Injeção): HTTP ${addResponse.statusCode} - ${addResponse.body}');
        return false;
      }

      LogService().add('✅ SPOTIFY: SUCESSO ABSOLUTO! Músicas na biblioteca.');
      return true;
    } catch (e) {
      LogService().add('❌ SPOTIFY EXCEÇÃO: $e');
      return false;
    }
  }
  /// Extrai os artistas favoritos do usuário para alimentar a IA do modo "Estou com Sorte"
  Future<List<String>> getUserTopArtists({int limit = 30}) async {
    if (!isLogged) {
      LogService().add('⚠️ SPOTIFY: Tentou buscar Top Artistas sem estar logado.');
      return [];
    }

    // medium_term = calcula com base nos últimos 6 meses.
    final url = Uri.parse('https://api.spotify.com/v1/me/top/artists?limit=$limit&time_range=medium_term');

    try {
      LogService().add('🔍 SPOTIFY: Analisando o DNA musical do usuário...');
      
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List;
        
        // Mapeia o JSON puxando apenas o nome de cada artista
        List<String> topArtists = items.map((item) => item['name'].toString()).toList();
        
        LogService().add('✅ SPOTIFY: DNA Extraído! Top $limit: ${topArtists.join(", ")}');
        return topArtists;
      } else {
        LogService().add('❌ ERRO SPOTIFY: Falha ao puxar Top Artistas (Status: ${response.statusCode})');
        return [];
      }
    } catch (e) {
      LogService().add('❌ ERRO CRÍTICO SPOTIFY: Falha de rede ao buscar Top Artistas: $e');
      return [];
    }
  }

  /// Busca apenas o ID de um artista pelo nome
  Future<String?> searchArtistId(String artistName) async {
    final url = Uri.parse('https://api.spotify.com/v1/search?q=track:$title artist:$artistName&type=artist&limit=1');
    try {
      final response = await http.get(url, headers: {'Authorization': 'Bearer $_accessToken'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['artists']['items'].isNotEmpty) {
          return data['artists']['items'][0]['id'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// O Motor de Busca Nativo do Spotify (Bypassa a IA)
  Future<List<Map<String, String>>> getRecommendations({
    required List<String> seedArtists,
    required double targetEnergy,
    required int targetPopularity,
  }) async {
    // O Spotify exige que os IDs sejam separados por vírgula
    String seeds = seedArtists.join(',');
    
    // Monta a URL com a matemática exata dos seus sliders
    final url = Uri.parse('https://developer.spotify.com/documentation/web-api/concepts/rate-limits3'
        'limit=15'
        '&seed_artists=$seeds'
        '&target_energy=$targetEnergy'
        '&target_popularity=$targetPopularity');

    try {
      final response = await http.get(url, headers: {'Authorization': 'Bearer $_accessToken'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, String>> tracks = [];
        
        for (var t in data['tracks']) {
          tracks.add({
            'title': t['name'] ?? 'Sem título',
            'artist': t['artists'][0]['name'] ?? 'Desconhecido',
            'id': t['uri'] ?? '',
            'image': t['album']['images'].isNotEmpty ? t['album']['images'][0]['url'] : '',
            'locked': 'false',
          });
        }
        return tracks;
      } else {
        throw Exception('Erro na API de recomendações: ${response.body}');
      }
    } catch (e) {
      LogService().add('❌ ERRO Recomendação: $e');
      throw e;
    }
  }
  
}