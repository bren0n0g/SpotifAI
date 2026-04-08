import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

class SpotifyService {
  static final SpotifyService _instance = SpotifyService._internal();
  factory SpotifyService() => _instance;
  SpotifyService._internal();

  // Variáveis do Cofre (BYOK)
  String _clientId = '';
  String _clientSecret = '';
  String _accessToken = '';
  bool isLogged = false;

  // URLs oficiais e blindadas da API do Spotify
  final String _accountsDomain = 'accounts.spotify.com';
  final String _apiBase = 'https://api.spotify.com/v1';

  // Getters para a interface conseguir ler o estado
  String get clientId => _clientId;
  String get clientSecret => _clientSecret;
  bool get hasKeys => _clientId.isNotEmpty && _clientSecret.isNotEmpty;

  // --- GERENCIAMENTO DE CHAVES LOCAIS ---
  
  Future<void> loadKeys() async {
    final prefs = await SharedPreferences.getInstance();
    _clientId = prefs.getString('spotify_client_id') ?? '';
    _clientSecret = prefs.getString('spotify_client_secret') ?? '';
  }

  Future<void> saveKeys(String id, String secret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotify_client_id', id.trim());
    await prefs.setString('spotify_client_secret', secret.trim());
    _clientId = id.trim();
    _clientSecret = secret.trim();
  }

  // --- GERENCIAMENTO DE SESSÃO E TOKEN ---

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('spotify_token', token);
  }

  Future<bool> loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('spotify_token');
    if (token != null && token.isNotEmpty) {
      _accessToken = token;
      isLogged = true; // Sincroniza o estado
      LogService().add('✅ SPOTIFY: Sessão restaurada da memória.');
      return true;
    }
    return false;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('spotify_token');
    _accessToken = ''; // Usar String vazia e não null!
    isLogged = false;  // Sincroniza o estado
    LogService().add('⚠️ SPOTIFY: Sessão encerrada.');
  }

  // --- AUTENTICAÇÃO OFICIAL ---

  Future<bool> authenticateUser() async {
    if (!hasKeys) {
      LogService().add('❌ SPOTIFY: Tentativa de login sem chaves de API configuradas.');
      return false;
    }

    LogService().add('🔐 SPOTIFY: Iniciando fluxo de autenticação (BYOK)...');
    
    final redirectUri = 'https://spotifai.brenomachado2003.workers.dev/callback.html';
    final String scope = 'playlist-modify-public playlist-modify-private playlist-read-private user-read-private user-read-email user-top-read';
    
    final url = Uri.https(_accountsDomain, '/authorize', {
      'client_id': _clientId, // Puxa do cofre, não do .env
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
          'Authorization': 'Basic ' + base64Encode(utf8.encode('$_clientId:$_clientSecret')),
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
        isLogged = true; // Sincroniza o estado
        
        await saveToken(_accessToken);
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

  // --- FUNÇÕES DE BUSCA E MANIPULAÇÃO ---

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

        final rootItemsFolder = data['items'] ?? data['tracks'];

        if (rootItemsFolder != null && rootItemsFolder['items'] != null) {
          final trackList = rootItemsFolder['items'] as List;

          for (var element in trackList) {
            if (element == null) continue; 
            
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
      LogService().add('⏳ SPOTIFY: Criando playlist na rota oficial...');
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

      LogService().add('⏳ SPOTIFY: Injetando ${trackUris.length} faixas...');
      
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

  /// Extrai os artistas favoritos do usuário (Corrigido para a API Real do Spotify)
  Future<List<String>> getUserTopArtists({int limit = 30}) async {
    if (!isLogged) {
      LogService().add('⚠️ SPOTIFY: Tentou buscar Top Artistas sem estar logado.');
      return [];
    }

    final url = Uri.parse('$_apiBase/me/top/artists?time_range=medium_term&limit=$limit');

    try {
      LogService().add('🔍 SPOTIFY: Analisando o DNA musical do usuário...');
      
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = data['items'] as List;
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
    final url = Uri.parse('$_apiBase/search?q=artist:${Uri.encodeComponent(artistName)}&type=artist&limit=1');
    
    try {
      final response = await http.get(url, headers: {'Authorization': 'Bearer $_accessToken'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['artists'] != null && data['artists']['items'].isNotEmpty) {
          return data['artists']['items'][0]['id'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// O Motor de Busca Nativo do Spotify (Bypassa a IA) - Corrigido para a API Real
  Future<List<Map<String, String>>> getRecommendations({
    required List<String> seedArtists,
    required double targetEnergy,
    required int targetPopularity,
  }) async {
    String seeds = seedArtists.join(',');
    final url = Uri.parse('$_apiBase/recommendations?limit=15&seed_artists=$seeds&target_energy=$targetEnergy&target_popularity=$targetPopularity');

    try {
      final response = await http.get(url, headers: {'Authorization': 'Bearer $_accessToken'});
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List<Map<String, String>> tracks = [];
        
        for (var t in data['tracks']) {
          tracks.add({
            'title': t['name'] ?? 'Sem título',
            'artist': (t['artists'] as List).isNotEmpty ? t['artists'][0]['name'] : 'Desconhecido',
            'id': t['uri'] ?? '',
            'image': (t['album']['images'] as List).isNotEmpty ? t['album']['images'][0]['url'] : '',
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