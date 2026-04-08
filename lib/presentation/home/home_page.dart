import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:premium_ui_kit/premium_ui_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/spotify_service.dart';
import '../../services/ai_service.dart';
import '../../services/log_service.dart';
import 'package:flutter/foundation.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLog;
  ChatMessage({required this.text, required this.isUser, this.isLog = false});
  Map<String, dynamic> toJson() => {
    'text': text,
    'isUser': isUser,
    'isLog': isLog,
  };
  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    text: json['text'],
    isUser: json['isUser'],
    isLog: json['isLog'] ?? false,
  );
}

class ChatConversation {
  final String id;
  String title;
  List<ChatMessage> messages;
  List<Map<String, String>> tracks;
  ChatConversation({
    required this.id,
    required this.title,
    required this.messages,
    this.tracks = const [],
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'tracks': tracks,
  };
  factory ChatConversation.fromJson(Map<String, dynamic> json) =>
      ChatConversation(
        id: json['id'],
        title: json['title'],
        messages: (json['messages'] as List)
            .map((m) => ChatMessage.fromJson(m))
            .toList(),
        tracks: json['tracks'] != null
            ? (json['tracks'] as List)
                  .map((t) => Map<String, String>.from(t))
                  .toList()
            : [],
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _manualGenreController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  // --- MÁQUINA DE ESTADOS DO COPILOTO ---
  bool _isCopilotMode = false;
  int _copilotStep = 1;
  List<dynamic> _copilotVibes = [];
  List<String> _topArtistsCache = [];

  String _selectedVibe = '';
  List<String> _selectedArtists = [];
  double _artistExploration = 0.0; // Começa em 0 (Seguro)
  double _trackExploration = 0.0; // Começa em 0 (Hits)
  double _trackCount = 20.0; // Valor inicial (pode ser 20, 40, 60, 80 ou 100)

  // Novo Controle de Ritmo
  bool _isRhythmEnabled = true;
  double _rhythmLevel = 2.0;

  bool _isListening = false;
  bool _isLoadingCopilot = false;
  double _energyLevel = 2.0; // Slider 3: Energia

  final List<Color> _mixColors = [
    const Color(0xFF985310),
    const Color(0xFF3A5A78),
    const Color(0xFF32148B),
    const Color(0xFF46532B),
    const Color(0xFFA01929),
    const Color(0xFF91145C),
  ];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _showLogsInChat = false;
  double _loadingProgress = 0.0;
  String _lastPollutedText = "";

  late stt.SpeechToText _speech;
  final List<ChatConversation> _conversations = [];
  late ChatConversation _activeConversation;

  @override
  void initState() {
    super.initState();
    SpotifyService().loadKeys().then((_) {
        SpotifyService().loadSavedToken();
      });
    _speech = stt.SpeechToText();
    _searchController.addListener(() => setState(() {}));
    _activeConversation = ChatConversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: 'Nova Curadoria',
      messages: [],
    );
    _conversations.insert(0, _activeConversation);

    _loadHistory();
    

    LogService().onNewLog = (String log) {
      if (mounted) {
        setState(() {
          if (_showLogsInChat) {
            _activeConversation.messages.add(
              ChatMessage(text: log, isUser: false, isLog: true),
            );
            _scrollToBottom();
          }
          if (log.contains('👆 UI: Usuário enviou')) _loadingProgress = 0.05;
          if (log.contains('🧠 AI: Analisando')) _loadingProgress = 0.15;
          if (log.contains('🚀 AI: Disparando')) _loadingProgress = 0.3;
          if (log.contains('✅ AI: Resposta recebida')) _loadingProgress = 0.6;
          if (log.contains('🔍 SPOTIFY: Buscando')) _loadingProgress = 0.85;
          if (log.contains('⏳ SPOTIFY: Baixando playlist'))
            _loadingProgress = 0.4;
          if (log.contains('💾 UI: Tentando salvar')) _loadingProgress = 0.1;
          if (log.contains('⏳ SPOTIFY: Solicitando')) _loadingProgress = 0.4;
          if (log.contains('✅ SPOTIFY: Playlist criada'))
            _loadingProgress = 0.7;
          if (log.contains('✅ SPOTIFAI: Curadoria concluída!') ||
              log.contains('✅ SPOTIFY: SUCESSO') ||
              log.contains('✅ SPOTIFY: Playlist'))
            _loadingProgress = 1.0;
        });
        if (_loadingProgress >= 1.0)
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted && _loadingProgress >= 1.0)
              setState(() => _loadingProgress = 0.0);
          });
      }
    };
    final brightness = PlatformDispatcher.instance.platformBrightness;
    themeNotifier.value = brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  void _startCopilot() async {
    // Coloque isso no começo da _startCopilot() E da _savePlaylist()
    if (!SpotifyService().hasKeys) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Configure sua Chave de API primeiro!'), backgroundColor: Colors.orangeAccent));
      Navigator.push(context, MaterialPageRoute(builder: (context) => const TutorialPage()));
      return;
    }
    if (!SpotifyService().isLogged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Conecte o Spotify no menu lateral primeiro!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      _isLoadingCopilot = true;
      _copilotStep = 1;
      _selectedVibe = '';
      _selectedArtists.clear();
      _artistExploration = 2.0;
      _trackExploration = 2.0;
      _energyLevel = 2.0;
      _manualGenreController.clear();
    });
    LogService().add('👆 UI: Iniciando Modo Copiloto Guiado...');

    List<String> topArtists = await SpotifyService().getUserTopArtists(
      limit: 15,
    );
    _topArtistsCache = topArtists;
    List<dynamic> vibes = await AiService().generateDynamicVibes(topArtists);

    if (mounted) {
      setState(() {
        _copilotVibes = vibes.take(10).toList();
        _copilotVibes.add({
          "vibe": "Escolha você mesmo",
          "artists": [],
          "isManual": true,
        });
        _copilotVibes.add({
          "vibe": "Escolha por artista",
          "artists": [],
          "isArtistSelect": true,
        });
        _isLoadingCopilot = false;
        _isCopilotMode = true;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    _manualGenreController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'spotifai_chats',
      jsonEncode(_conversations.map((c) => c.toJson()).toList()),
    );
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? savedData = prefs.getString('spotifai_chats');
    if (savedData != null && savedData.isNotEmpty) {
      try {
        List<dynamic> decodedData = jsonDecode(savedData);
        setState(() {
          _conversations.clear();
          _conversations.addAll(
            decodedData.map((c) => ChatConversation.fromJson(c)).toList(),
          );
          if (_conversations.isNotEmpty)
            _activeConversation = _conversations.first;
        });
        _scrollToBottom();
      } catch (e) {
        LogService().add('❌ ERRO ao carregar memória: $e');
      }
    }
  }

  Widget _buildCopilotRouter(bool isDark, AppleKitColors colors) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOutQuart,
      switchOutCurve: Curves.easeInQuart,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.15, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _getStepWidget(isDark, colors),
    );
  }

  Widget _getStepWidget(bool isDark, AppleKitColors colors) {
    switch (_copilotStep) {
      case 1:
        return SizedBox(
          key: const ValueKey('step1'),
          child: _buildStep1Genre(isDark, colors),
        );
      case 2:
        return SizedBox(
          key: const ValueKey('step2'),
          child: _buildStep2Artists(isDark, colors),
        );
      case 3:
        return SizedBox(
          key: const ValueKey('step3'),
          child: _buildStep3Manual(isDark, colors),
        );
      case 4:
        return SizedBox(
          key: const ValueKey('step4'),
          child: _buildStep4Exploration(isDark, colors),
        );
      default:
        return SizedBox(
          key: const ValueKey('step1'),
          child: _buildStep1Genre(isDark, colors),
        );
    }
  }

  Widget _buildStep1Genre(bool isDark, AppleKitColors colors) {
    if (_isLoadingCopilot)
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1DB954)),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                CupertinoIcons.clear,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () => setState(() => _isCopilotMode = false),
            ),
            Expanded(
              child: Text(
                'Gênero',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 24),
          child: Text(
            'Comece sua playlist com estilo. (Use a barra de pesquisa para me pedir ajustes!)',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 2.2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _copilotVibes.length, // Agora são 12 botões
            itemBuilder: (context, index) {
              final item = _copilotVibes[index];
              String vibe = item['vibe'] ?? '';
              List<String> artists = List<String>.from(item['artists'] ?? []);
              bool isManual = item['isManual'] == true;
              bool isArtistSelect = item['isArtistSelect'] == true;
              final Color cardColor = isManual || isArtistSelect
                  ? (isDark ? const Color(0xFF2C2C2E) : Colors.grey[300]!)
                  : _mixColors[index % _mixColors.length];

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (isManual) {
                    setState(() => _copilotStep = 3);
                  } else if (isArtistSelect) {
                    setState(() => _copilotStep = 2);
                  } else {
                    setState(() {
                      _selectedVibe = vibe;
                      // FIX: Adiciona os artistas do card como âncoras para a IA respeitar a variabilidade
                      _selectedArtists = List<String>.from(artists);
                      _copilotStep = 4;
                    });
                  }
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: isManual || isArtistSelect
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isManual
                                  ? CupertinoIcons.pencil_outline
                                  : CupertinoIcons.person_3_fill,
                              color: isDark ? Colors.white : Colors.black87,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                vibe,
                                style: TextStyle(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                              ),
                            ),
                          ],
                        )
                      : Stack(
                          children: [
                            Positioned(
                              right: -10,
                              top: -10,
                              child: Transform.rotate(
                                angle: -0.2,
                                child: Icon(
                                  CupertinoIcons.music_albums_fill,
                                  size: 70,
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(10.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    vibe
                                        .replaceAll(RegExp(r'^[^\w\s]+'), '')
                                        .trim(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      height: 1.1,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    artists.isNotEmpty
                                        ? artists.join(', ')
                                        : 'Para você.',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.75),
                                      fontSize: 10,
                                      height: 1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Artists(bool isDark, AppleKitColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                CupertinoIcons.back,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () => setState(() => _copilotStep = 1),
            ),
            Expanded(
              child: Text(
                'Seus Artistas',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 16),
          child: Text(
            'Selecione os pilares da sua playlist',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 3.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _topArtistsCache.length,
            itemBuilder: (context, index) {
              String artist = _topArtistsCache[index];
              bool isSelected = _selectedArtists.contains(artist);
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() {
                  isSelected
                      ? _selectedArtists.remove(artist)
                      : _selectedArtists.add(artist);
                }),
                child: Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF1DB954).withOpacity(0.2)
                        : (isDark ? const Color(0xFF2C2C2E) : Colors.grey[200]),
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: const Color(0xFF1DB954))
                        : null,
                  ),
                  child: Row(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          isSelected
                              ? CupertinoIcons.checkmark_alt_circle_fill
                              : CupertinoIcons.circle,
                          color: isSelected
                              ? const Color(0xFF1DB954)
                              : Colors.grey,
                          size: 20,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          artist,
                          style: TextStyle(
                            color: isSelected
                                ? const Color(0xFF1DB954)
                                : (isDark ? Colors.white : Colors.black),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 8,
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: _selectedArtists.isNotEmpty
                  ? () => setState(() => _copilotStep = 4)
                  : null,
              child: const Text(
                'Continuar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep3Manual(bool isDark, AppleKitColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                CupertinoIcons.back,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () => setState(() => _copilotStep = 1),
            ),
            Expanded(
              child: Text(
                'Sua Ideia',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'O que você tem em mente?',
                  style: TextStyle(
                    color: isDark ? Colors.grey[300] : Colors.black87,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _manualGenreController,
                  autofocus: true,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Ex: Cyberpunk, Jazz de Chuva...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF2C2C2E)
                        : Colors.grey[200],
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 8,
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: () {
                if (_manualGenreController.text.isNotEmpty)
                  setState(() {
                    _selectedVibe = _manualGenreController.text;
                    _copilotStep = 4;
                  });
              },
              child: const Text(
                'Continuar',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStep4Exploration(bool isDark, AppleKitColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(
                CupertinoIcons.back,
                color: isDark ? Colors.white : Colors.black,
              ),
              onPressed: () {
                if (_selectedArtists.isNotEmpty)
                  setState(() => _copilotStep = 2);
                else if (_manualGenreController.text.isNotEmpty)
                  setState(() => _copilotStep = 3);
                else
                  setState(() => _copilotStep = 1);
              },
            ),
            Expanded(
              child: Text(
                'Painel de Mixagem',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 48, bottom: 24),
          child: Text(
            'Ajuste os detalhes da sua playlist',
            style: TextStyle(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontSize: 14,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            children: [
              // --- NOVO BOX DE QUANTIDADE ---
              Text(
                'Tamanho da Playlist',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _buildTrackCountSelector(isDark),
              const SizedBox(height: 40),

              // ------------------------------
              _buildSliderSection(
                'Variabilidade de Artistas',
                'Apenas Selecionados',
                '100% Desconhecidos',
                _artistExploration,
                (val) => setState(() => _artistExploration = val),
                isDark,
              ),
              const SizedBox(height: 32),
              _buildSliderSection(
                'Variabilidade de Músicas',
                'Apenas os Hits',
                'Lados B Obscuros',
                _trackExploration,
                (val) => setState(() => _trackExploration = val),
                isDark,
              ),
              const SizedBox(height: 32),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Ritmo',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  CupertinoSwitch(
                    activeColor: const Color(0xFF1DB954),
                    value: _isRhythmEnabled,
                    onChanged: (val) => setState(() => _isRhythmEnabled = val),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_isRhythmEnabled)
                _buildSliderSection(
                  '',
                  'Acústico / Calmo',
                  'Fritar / Pesado',
                  _rhythmLevel,
                  (val) => setState(() => _rhythmLevel = val),
                  isDark,
                )
              else
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 24.0),
                  child: Text(
                    'Ritmo desabilitado. A IA escolherá livremente.',
                    style: TextStyle(
                      color: isDark ? Colors.grey[600] : Colors.grey[400],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: 8,
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1DB954),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              onPressed: _finishCopilotAndGenerate,
              child: const Text(
                'Gerar Curadoria',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Componente visual para o seletor de 20 a 100
  Widget _buildTrackCountSelector(bool isDark) {
    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF1DB954),
            inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF1DB954).withOpacity(0.2),
            valueIndicatorShape: const PaddleSliderValueIndicatorShape(),
            valueIndicatorColor: const Color(0xFF1DB954),
            valueIndicatorTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          child: Slider(
            value: _trackCount,
            min: 20,
            max: 100,
            divisions: 4, // 20, 40, 60, 80, 100
            label: '${_trackCount.toInt()} músicas',
            onChanged: (val) => setState(() => _trackCount = val),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [20, 40, 60, 80, 100]
                .map(
                  (n) => Text(
                    '$n',
                    style: TextStyle(
                      color: _trackCount.toInt() == n
                          ? const Color(0xFF1DB954)
                          : Colors.grey,
                      fontWeight: _trackCount.toInt() == n
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSliderSection(
    String title,
    String leftLabel,
    String rightLabel,
    double value,
    Function(double) onChanged,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          title,
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: const Color(0xFF1DB954),
            inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
            thumbColor: Colors.white,
            tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 4),
            activeTickMarkColor: Colors.white.withOpacity(0.5),
            inactiveTickMarkColor: Colors.grey.withOpacity(0.5),
          ),
          child: Slider(
            value: value,
            min: 0,
            max: 4,
            divisions: 4,
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              leftLabel,
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              rightLabel,
              style: TextStyle(
                color: isDark ? Colors.grey[500] : Colors.grey[700],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _finishCopilotAndGenerate() async {
    setState(() {
      _isCopilotMode = false;
      _isLoading = true;
      _searchController.clear();

      int totalTracks = _trackCount.toInt();
      int artistPercent = (_artistExploration * 25).toInt();

      String summary = "🎵 Curadoria Mixada:\n\n";
      summary += "• Quantidade: $totalTracks músicas\n";
      if (_selectedVibe.isNotEmpty) summary += "• Base: $_selectedVibe\n";
      if (_selectedArtists.isNotEmpty)
        summary += "• Âncoras: ${_selectedArtists.join(', ')}\n";
      summary += "• Artistas Novos: $artistPercent%\n";
      summary +=
          "• Músicas: Nível ${_trackExploration.toInt()} (Hits vs Lado B)\n";
      summary +=
          "• Ritmo: ${_isRhythmEnabled ? 'Nível ${_rhythmLevel.toInt()}' : 'Livre'}";

      _activeConversation.messages.add(
        ChatMessage(text: summary, isUser: true),
      );
      _saveHistory();
    });

    _scrollToBottom();
    LogService().add(
      '👆 UI: Construindo Prompt Matemático para ${_trackCount.toInt()} músicas...',
    );

    try {
      String base = _selectedVibe.isNotEmpty
          ? _selectedVibe
          : "Baseado nos artistas âncora.";
      String artistas = _selectedArtists.isNotEmpty
          ? _selectedArtists.join(', ')
          : "O gênero base selecionado.";

      // 1. Cálculo de Porcentagem baseado na quantidade escolhida
      int totalTracks = _trackCount.toInt();
      int newArtistsPercent = (_artistExploration * 25).toInt();
      int tracksFromSeeds =
          totalTracks - (totalTracks * newArtistsPercent / 100).round();
      int tracksFromNew = totalTracks - tracksFromSeeds;

      // 2. Trava de Familiaridade
      String trackFamiliarity = "";
      if (_trackExploration == 0)
        trackFamiliarity =
            "APENAS os maiores hits absolutos globais (Top 5 da carreira do artista).";
      else if (_trackExploration == 1)
        trackFamiliarity = "Músicas famosas e singles conhecidos.";
      else if (_trackExploration == 2)
        trackFamiliarity =
            "Metade hits conhecidos, metade faixas normais de álbuns.";
      else if (_trackExploration == 3)
        trackFamiliarity =
            "Maioria de Lados B e faixas que nunca foram singles.";
      else
        trackFamiliarity =
            "APENAS Lados B, deep cuts e músicas obscuras. NENHUM hit global permitido.";

      // 3. Trava de Ritmo
      String rhythmConstraint = _isRhythmEnabled
          ? "- Ritmo/Energia (0=Acústico, 4=Fritar): O usuário definiu o Nível ${_rhythmLevel.toInt()}."
          : "- Ritmo/Energia: LIVRE.";

      // O SUPER PROMPT ATUALIZADO
      String promptComContexto =
          """
      [COMANDO RESTRITO DO COPILOTO]
      Você DEVE gerar uma playlist de EXATAMENTE $totalTracks músicas reais do Spotify seguindo ESTAS REGRAS MATEMÁTICAS:
      
      BASE DA PLAYLIST:
      - Vibe/Estilo: $base
      - Artistas Âncora: $artistas
      
      REGRA DE ARTISTAS (Variabilidade de $newArtistsPercent%):
      - Você DEVE incluir EXATAMENTE $tracksFromSeeds músicas dos "Artistas Âncora" listados acima.
      - Você DEVE incluir EXATAMENTE $tracksFromNew músicas de OUTROS artistas relacionados.
      *(Se a variabilidade for 0%, use apenas os artistas âncora para as $totalTracks músicas).*
      
      REGRA DE MÚSICAS:
      - $trackFamiliarity
      
      REGRA DE RITMO:
      $rhythmConstraint
      
      Retorne APENAS o formato JSON duplo com 'chat_reply' e 'playlist_update'.
      """;

      final aiResult = await AiService().generatePlaylist(promptComContexto);

      if (aiResult != null && mounted) {
        final chatReply = aiResult['chat_reply'] ?? 'Mixagem concluída!';
        final playlistData = aiResult['playlist_update'] ?? aiResult;
        List<Map<String, String>> newTracks = [];

        if (playlistData['tracks'] != null) {
          final rawTracks = playlistData['tracks'] as List;
          LogService().add(
            '🔍 SPOTIFY: Verificando as ${rawTracks.length} faixas geradas...',
          );
          for (var t in rawTracks) {
            String trackTitle = t['title'] ?? t['titulo'] ?? t['nome'] ?? '';
            String trackArtist =
                t['artist'] ?? t['artista'] ?? t['banda'] ?? '';
            try {
              final spotifyData = await SpotifyService().searchTrack(
                trackTitle,
                trackArtist,
              );
              newTracks.add({
                'title': trackTitle,
                'artist': trackArtist,
                'id': spotifyData?['id'] ?? '',
                'image': spotifyData?['image'] ?? '',
                'locked': 'false',
              });
            } catch (e) {
              newTracks.add({
                'title': trackTitle,
                'artist': trackArtist,
                'id': '',
                'image': '',
                'locked': 'false',
              });
            }
          }
        }
        setState(() {
          _activeConversation.messages.add(
            ChatMessage(text: chatReply, isUser: false),
          );
          _activeConversation.tracks = newTracks;
          _activeConversation.title = playlistData['title'] ?? "Mix SpotifAI";
          _isLoading = false;
          _saveHistory();
        });
        LogService().add('✅ SPOTIFAI: Curadoria mixada finalizada!');
        _scrollToBottom();
      }
    } catch (e) {
      LogService().add('❌ ERRO CRÍTICO NA MIXAGEM: $e');
      if (mounted) {
        setState(() {
          _activeConversation.messages.add(
            ChatMessage(text: 'Erro no cálculo da IA.', isUser: false),
          );
          _isLoading = false;
          _saveHistory();
        });
        _scrollToBottom();
      }
    }
  }

  void _submitSearch(String value) async {
    if (value.isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();

    if (_isCopilotMode && _copilotStep == 1) {
      setState(() => _isLoadingCopilot = true);
      LogService().add('👆 UI: Usuário pediu ajuste nos gêneros: "$value"');
      List<dynamic> vibes = await AiService().generateDynamicVibes(
        _topArtistsCache,
        userHint: value,
      );
      if (mounted) {
        setState(() {
          _searchController.clear();
          _copilotVibes = vibes.take(10).toList(); // Garante os 10 itens!
          _copilotVibes.add({
            "vibe": "Escolha você mesmo",
            "artists": [],
            "isManual": true,
          });
          _copilotVibes.add({
            "vibe": "Escolha por artista",
            "artists": [],
            "isArtistSelect": true,
          });
          _isLoadingCopilot = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _activeConversation.messages.add(ChatMessage(text: value, isUser: true));
      _searchController.clear();
      _saveHistory();
    });
    _scrollToBottom();
    LogService().add('👆 UI: Usuário enviou: "$value"');

    try {
      String historyContext = _activeConversation.messages
          .where((m) => !m.isLog)
          .map((m) => "${m.isUser ? 'Usuário' : 'SpotifAI'}: ${m.text}")
          .join("\n");
      String currentPlaylistState = _activeConversation.tracks.isEmpty
          ? "ESTADO DA PLAYLIST: Nenhuma playlist carregada."
          : "PLAYLIST ATUAL NO SISTEMA:\n" +
                _activeConversation.tracks
                    .map((t) => "- ${t['title']} (${t['artist']})")
                    .join('\n');
      List<String> lockedInfo = _activeConversation.tracks
          .where((t) => t['locked'] == 'true')
          .map((t) => "- ${t['title']} (${t['artist']})")
          .toList();
      String lockedConstraint = lockedInfo.isEmpty
          ? ""
          : "REGRA ABSOLUTA: As seguintes músicas estão TRANCADAS pelo usuário. Você DEVE incluí-las:\n${lockedInfo.join('\n')}\n\n";
      String promptComContexto =
          "Histórico da conversa:\n$historyContext\n\n$currentPlaylistState\n\n$lockedConstraint Novo pedido do Usuário: $value\nLembre-se de retornar JSON duplo.";

      final aiResult = await AiService().generatePlaylist(promptComContexto);

      if (aiResult != null && mounted) {
        final chatReply =
            aiResult['chat_reply'] ?? 'Aqui está sua atualização!';
        final playlistData = aiResult['playlist_update'] ?? aiResult;
        List<Map<String, String>> newTracks = [];

        if (playlistData['tracks'] != null) {
          final rawTracks = playlistData['tracks'] as List;
          LogService().add(
            '🔍 SPOTIFY: Buscando metadados para ${rawTracks.length} músicas...',
          );
          for (var t in rawTracks) {
            String trackTitle =
                t['title'] ?? t['titulo'] ?? t['nome'] ?? 'Sem título';
            String trackArtist =
                t['artist'] ?? t['artista'] ?? t['banda'] ?? 'Desconhecido';
            var existingLockedTrack = _activeConversation.tracks
                .cast<Map<String, String>?>()
                .firstWhere(
                  (oldTrack) =>
                      oldTrack!['locked'] == 'true' &&
                      oldTrack['title']?.toLowerCase() ==
                          trackTitle.toLowerCase(),
                  orElse: () => null,
                );
            if (existingLockedTrack != null) {
              newTracks.add(existingLockedTrack);
              continue;
            }
            try {
              final spotifyData = await SpotifyService().searchTrack(
                trackTitle,
                trackArtist,
              );
              newTracks.add({
                'title': trackTitle,
                'artist': trackArtist,
                'id': spotifyData?['id'] ?? '',
                'image': spotifyData?['image'] ?? '',
                'locked': 'false',
              });
            } catch (e) {
              newTracks.add({
                'title': trackTitle,
                'artist': trackArtist,
                'id': '',
                'image': '',
                'locked': 'false',
              });
            }
          }
        }
        setState(() {
          _activeConversation.messages.add(
            ChatMessage(text: chatReply, isUser: false),
          );
          _activeConversation.tracks = newTracks;
          _activeConversation.title =
              playlistData['title'] ?? _activeConversation.title;
          _isLoading = false;
          _saveHistory();
        });
        LogService().add('✅ SPOTIFAI: Curadoria concluída!');
        _scrollToBottom();
      }
    } catch (e) {
      LogService().add('❌ ERRO CRÍTICO: $e');
      if (mounted) {
        setState(() {
          _activeConversation.messages.add(
            ChatMessage(text: 'Falha no sistema.', isUser: false),
          );
          _isLoading = false;
          _saveHistory();
        });
        _scrollToBottom();
      }
    }
  }

  void _toggleTheme() {
    themeNotifier.value = themeNotifier.value == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients)
      Future.delayed(
        const Duration(milliseconds: 600),
        () => _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        ),
      );
  }

  Color _getLogColor(String log, bool isDark) {
    if (log.contains('❌') || log.contains('ERRO')) return Colors.redAccent;
    if (log.contains('✅') || log.contains('sucesso') || log.contains('SUCESSO'))
      return const Color(0xFF1DB954);
    if (log.contains('🚀') ||
        log.contains('🧠') ||
        log.contains('UI') ||
        log.contains('SPOTIFY'))
      return Colors.blueAccent;
    return isDark ? Colors.grey[400]! : Colors.grey[800]!;
  }

  void _importPlaylist(String url) async {
    if (url.isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();
    if (!SpotifyService().isLogged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '❌ Conecte o Spotify no menu lateral antes de importar.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _urlController.clear();
    });
    LogService().add('👆 UI: Usuário enviou link para importação...');
    final result = await SpotifyService().importPlaylistFromUrl(url);
    if (result != null && mounted) {
      setState(() {
        _activeConversation.title = result['title'];
        _activeConversation.tracks = List<Map<String, String>>.from(
          result['tracks'],
        );
        _activeConversation.messages.add(
          ChatMessage(
            text: 'Acabei de importar a playlist **"${result['title']}"**.',
            isUser: false,
          ),
        );
        _isLoading = false;
        _saveHistory();
      });
      LogService().add('✅ SPOTIFAI: Curadoria concluída!');
      _scrollToBottom();
    } else if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao importar.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _savePlaylist() async {
    // Coloque isso no começo da _startCopilot() E da _savePlaylist()
    if (!SpotifyService().hasKeys) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Configure sua Chave de API primeiro!'), backgroundColor: Colors.orangeAccent));
      Navigator.push(context, MaterialPageRoute(builder: (context) => const TutorialPage()));
      return;
    }
    if (_activeConversation.tracks.isEmpty || _isSaving) return;
    if (!SpotifyService().isLogged) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('❌ Conecte o Spotify!'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    LogService().add('💾 UI: Tentando salvar a playlist...');
    List<String> trackUris = _activeConversation.tracks
        .where((t) => t['id'] != null && t['id']!.isNotEmpty)
        .map((t) => t['id']!)
        .toList();
    bool sucesso = await SpotifyService().createAndPopulatePlaylist(
      _activeConversation.title,
      "Gerada pelo SpotifAI Copilot",
      trackUris,
    );
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(sucesso ? 'Playlist salva! 🔥' : 'Erro.'),
          backgroundColor: sucesso ? const Color(0xFF1DB954) : Colors.redAccent,
        ),
      );
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          if (val == 'done' || val == 'notListening')
            setState(() => _isListening = false);
        },
        onError: (val) => setState(() => _isListening = false),
      );
      if (available) {
        setState(() {
          _isListening = true;
          _searchController.clear();
          _lastPollutedText = "";
        });
        _speech.listen(
          onResult: (val) {
            setState(() {
              String recognized = val.recognizedWords;
              if (kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
                if (_lastPollutedText.isNotEmpty &&
                    recognized.startsWith(_lastPollutedText))
                  _searchController.text = recognized.substring(
                    _lastPollutedText.length,
                  );
                else
                  _searchController.text = recognized;
                _lastPollutedText = recognized;
              } else
                _searchController.text = recognized;
              _searchController.selection = TextSelection.fromPosition(
                TextPosition(offset: _searchController.text.length),
              );
            });
          },
          localeId: 'pt-BR',
          listenOptions: stt.SpeechListenOptions(cancelOnError: true),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _startNewConversation() {
    setState(() {
      _activeConversation = ChatConversation(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: 'Nova Curadoria',
        messages: [],
      );
      _conversations.insert(0, _activeConversation);
      _searchController.clear();
      _urlController.clear();
      _saveHistory();
    });
    Navigator.pop(context);
  }

  void _switchConversation(ChatConversation conversation) {
    setState(() {
      _activeConversation = conversation;
    });
    Navigator.pop(context);
    _scrollToBottom();
  }

  void _deleteConversation(ChatConversation conv) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardColor,
        title: const Text('Apagar conversa?'),
        content: Text('A curadoria "${conv.title}" será removida.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _conversations.remove(conv);
                if (_conversations.isEmpty) {
                  _activeConversation = ChatConversation(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    title: 'Nova Curadoria',
                    messages: [],
                  );
                  _conversations.add(_activeConversation);
                } else if (_activeConversation.id == conv.id)
                  _activeConversation = _conversations.first;
                _saveHistory();
              });
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text(
              'Apagar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showKeyPopup() {
    final idController = TextEditingController(text: SpotifyService().clientId); // Se já tiver, mostra
    final secretController = TextEditingController(text: SpotifyService().clientSecret);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.vpn_key, color: Color(0xFF1DB954)),
            const SizedBox(width: 8),
            Text('Suas Chaves API', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(labelText: 'Client ID', labelStyle: const TextStyle(color: Colors.grey), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1DB954)))),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: secretController,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(labelText: 'Client Secret', labelStyle: const TextStyle(color: Colors.grey), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF1DB954)))),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Fecha o popup
              Navigator.push(context, MaterialPageRoute(builder: (context) => const TutorialPage())); // Abre a ajuda
            }, 
            child: const Text('Ajuda / Tutorial', style: TextStyle(color: Colors.blueAccent))
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            onPressed: () async {
              if (idController.text.isNotEmpty && secretController.text.isNotEmpty) {
                await SpotifyService().saveKeys(idController.text, secretController.text);
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Chaves salvas com sucesso!'), backgroundColor: Color(0xFF1DB954)));
                }
              }
            }, 
            child: const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ),
        ],
      )
    );
  }

  // A lógica de Primeira Vez no Menu
  void _handleKeyButtonClick() async {
    final prefs = await SharedPreferences.getInstance();
    bool hasSeenTutorial = prefs.getBool('has_seen_api_tutorial') ?? false;

    if (!hasSeenTutorial) {
      await prefs.setBool('has_seen_api_tutorial', true);
      if (mounted) {
        Navigator.pop(context); // Fecha o Drawer
        Navigator.push(context, MaterialPageRoute(builder: (context) => const TutorialPage()));
      }
    } else {
      Navigator.pop(context); // Fecha o Drawer
      _showKeyPopup();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppleKitColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasStarted =
        _activeConversation.messages.isNotEmpty ||
        _activeConversation.tracks.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      appBar: _buildGlassAppBar(colors, isDark),
      drawer: _buildPremiumDrawer(colors, isDark),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 800),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.05),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                  child: _isCopilotMode
                      ? SizedBox(
                          key: const ValueKey('copilot_router'),
                          child: _buildCopilotRouter(isDark, colors),
                        )
                      : (!hasStarted
                            ? SizedBox(
                                key: const ValueKey('initial_state'),
                                child: _buildInitialState(isDark),
                              )
                            : SizedBox(
                                key: const ValueKey('split_screen'),
                                child: _buildSplitScreenResults(isDark, colors),
                              )),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedOpacity(
                opacity: _loadingProgress > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 0),
                  child: Container(
                    height: 2,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : Colors.black,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) => Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOutCubic,
                          width: constraints.maxWidth * _loadingProgress,
                          decoration: BoxDecoration(
                            color: Colors.grey,
                            borderRadius: BorderRadius.circular(2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.grey.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutCubic,
                    child: hasStarted || _isCopilotMode
                        ? const SizedBox(width: double.infinity, height: 0)
                        : Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF1DB954,
                                  ).withOpacity(isDark ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(
                                      0xFF1DB954,
                                    ).withOpacity(0.5),
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      CupertinoIcons.link,
                                      color: Color(0xFF1DB954),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: TextField(
                                        controller: _urlController,
                                        style: TextStyle(
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: 'Colar Playlist',
                                          hintStyle: TextStyle(
                                            color: isDark
                                                ? Colors.white54
                                                : Colors.black54,
                                          ),
                                          border: InputBorder.none,
                                        ),
                                        onSubmitted: _importPlaylist,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        CupertinoIcons.arrow_right_circle_fill,
                                        color: Color(0xFF1DB954),
                                      ),
                                      onPressed: () async {
                                        ClipboardData? data =
                                            await Clipboard.getData(
                                              Clipboard.kTextPlain,
                                            );
                                        if (data != null &&
                                            data.text != null &&
                                            data.text!.isNotEmpty) {
                                          setState(
                                            () => _urlController.text =
                                                data.text!,
                                          );
                                          _importPlaylist(data.text!);
                                        } else if (_urlController
                                            .text
                                            .isNotEmpty)
                                          _importPlaylist(_urlController.text);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),
                            ],
                          ),
                  ),
                  AppleTranslucentSearchBar(
                    controller: _searchController,
                    hintText: _isListening
                        ? 'Ouvindo...'
                        : 'Criar nova Playlist...',
                    onSubmitted: _submitSearch,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _searchController.text.isNotEmpty
                            ? CupertinoIcons.arrow_up_circle_fill
                            : (_isListening
                                  ? CupertinoIcons.mic_fill
                                  : CupertinoIcons.mic),
                        color: _searchController.text.isNotEmpty
                            ? const Color(0xFF1DB954)
                            : (_isListening
                                  ? Colors.redAccent
                                  : colors.frostedGlassText),
                        size: _searchController.text.isNotEmpty ? 28 : 24,
                      ),
                      onPressed: () {
                        if (_searchController.text.isNotEmpty)
                          _submitSearch(_searchController.text);
                        else
                          _listen();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSize _buildGlassAppBar(AppleKitColors colors, bool isDark) {
    final bool hasStarted =
        _activeConversation.messages.isNotEmpty ||
        _activeConversation.tracks.isNotEmpty ||
        _isCopilotMode;
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AppBar(
            backgroundColor: colors.frostedGlassBackground,
            elevation: 0,
            centerTitle: false,
            titleSpacing: 0,
            leading: Builder(
              builder: (context) => IconButton(
                icon: Icon(
                  CupertinoIcons.line_horizontal_3,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: hasStarted
                  ? Row(
                      key: const ValueKey('appbar_title_active'),
                      children: [
                        ClipOval(
                          child: Image.asset(
                            'assets/images/logo_bw.png',
                            height: 32,
                            width: 32,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              CupertinoIcons.music_albums,
                              size: 24,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'SPOTIFAI',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('appbar_title_empty')),
            ),
            actions: [
              ThemeToggleButton(isDark: isDark, onToggle: _toggleTheme),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPremiumDrawer(AppleKitColors colors, bool isDark) {
    return Drawer(
      backgroundColor: colors.premiumCardBackground,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: InkWell(
                onTap: _startNewConversation,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.add,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Novo Chat Musical',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(color: Colors.grey.withOpacity(0.2)),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _conversations.length,
                itemBuilder: (context, index) {
                  final conv = _conversations[index];
                  final isActive = conv.id == _activeConversation.id;
                  return ListTile(
                    selected: isActive,
                    selectedTileColor: isDark
                        ? Colors.white.withOpacity(0.05)
                        : Colors.black.withOpacity(0.05),
                    leading: Icon(
                      CupertinoIcons.chat_bubble_2,
                      color: isActive
                          ? const Color(0xFF1DB954)
                          : colors.frostedGlassText,
                      size: 20,
                    ),
                    title: Text(
                      conv.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isActive
                            ? (isDark ? Colors.white : Colors.black)
                            : colors.frostedGlassText,
                        fontSize: 14,
                        fontWeight: isActive
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        CupertinoIcons.trash,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      onPressed: () => _deleteConversation(conv),
                    ),
                    onTap: () => _switchConversation(conv),
                  );
                },
              ),
            ),
            Divider(color: Colors.grey.withOpacity(0.2)),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LogsPage()),
                  );
                },
                child: PremiumCard(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[200],
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.doc_text_viewfinder,
                        color: Colors.blueAccent,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Visualizar Logs',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 4.0,
              ),
              child: PremiumCard(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[200],
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.terminal_rounded,
                          color: Colors.orangeAccent,
                        ),
                        const SizedBox(width: 16),
                        Text(
                          'Logs no Chat',
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    CupertinoSwitch(
                      activeColor: Colors.orangeAccent,
                      value: _showLogsInChat,
                      onChanged: (val) => setState(() => _showLogsInChat = val),
                    ),
                  ],
                ),
              ),
            ),

            // ... [dentro do _buildPremiumDrawer, logo acima do Conectar Spotify] ...

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), 
              child: InkWell(
                borderRadius: BorderRadius.circular(16), 
                onTap: _handleKeyButtonClick, // Chama a lógica que criamos
                child: PremiumCard(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[200], 
                  padding: const EdgeInsets.all(16), 
                  child: Row(
                    children: [
                      const Icon(Icons.vpn_key, color: Colors.orangeAccent), 
                      const SizedBox(width: 16), 
                      Text('Colocar Chave API', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold))
                    ]
                  )
                )
              )
            ),

            // [Abaixo vem o Padding do Conectar Spotify que já existe...]

            Padding(
              padding: const EdgeInsets.only(
                left: 16.0,
                right: 16.0,
                bottom: 16.0,
                top: 4.0,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  bool sucesso = await SpotifyService().authenticateUser();
                  if (sucesso && mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Spotify Conectado!'),
                        backgroundColor: Color(0xFF1DB954),
                      ),
                    );
                  }
                },
                child: PremiumCard(
                  color: const Color(0xFF1DB954).withOpacity(0.15),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(
                        CupertinoIcons.play_circle_fill,
                        color: Color(0xFF1DB954),
                        size: 32,
                      ),
                      const SizedBox(width: 16),
                      Text(
                        'Conectar Spotify',
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState(bool isDark) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipOval(
          child: Image.asset(
            'assets/images/logo_bw.png',
            height: 120,
            width: 120,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              CupertinoIcons.music_albums,
              size: 100,
              color: Colors.grey,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'SPOTIFAI',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Qual a vibe de hoje?',
          style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]),
        ),
        const SizedBox(height: 32),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _isLoadingCopilot
              ? const CircularProgressIndicator(color: Color(0xFF1DB954))
              : ElevatedButton.icon(
                  onPressed: _startCopilot,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954).withOpacity(0.15),
                    foregroundColor: const Color(0xFF1DB954),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                      side: BorderSide(
                        color: const Color(0xFF1DB954).withOpacity(0.5),
                      ),
                    ),
                  ),
                  icon: const Icon(CupertinoIcons.wand_stars),
                  label: const Text(
                    'Estou com Sorte',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSplitScreenResults(bool isDark, AppleKitColors colors) {
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: PremiumCard(
            color: const Color(0xFF121212),
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          _activeConversation.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: _isSaving ? null : _savePlaylist,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1DB954),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Salvar',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _activeConversation.tracks.isEmpty
                      ? const Center(
                          child: Text(
                            'Nenhuma faixa carregada.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _activeConversation.tracks.length,
                          itemBuilder: (context, index) {
                            final track = _activeConversation.tracks[index];
                            final bool isLocked = track['locked'] == 'true';
                            return ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: track['image']!.isNotEmpty
                                    ? Image.network(
                                        track['image']!,
                                        width: 40,
                                        height: 40,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Icon(
                                              CupertinoIcons.music_note,
                                              color: Colors.grey,
                                            ),
                                      )
                                    : Container(
                                        width: 40,
                                        height: 40,
                                        color: Colors.grey[800],
                                        child: const Icon(
                                          CupertinoIcons.music_note,
                                          color: Colors.grey,
                                        ),
                                      ),
                              ),
                              title: Text(
                                track['title'] ?? '',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                track['artist'] ?? '',
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  isLocked
                                      ? CupertinoIcons.lock_fill
                                      : CupertinoIcons.lock_open,
                                  color: isLocked
                                      ? const Color(0xFF1DB954)
                                      : Colors.grey[600],
                                  size: 20,
                                ),
                                onPressed: () {
                                  setState(() {
                                    track['locked'] = isLocked
                                        ? 'false'
                                        : 'true';
                                    _saveHistory();
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          flex: 2,
          child: PremiumCard(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.grey[100],
            padding: const EdgeInsets.all(12),
            child: Stack(
              children: [
                ListView.builder(
                  controller: _chatScrollController,
                  itemCount: _activeConversation.messages.length,
                  itemBuilder: (context, index) {
                    final msg = _activeConversation.messages[index];
                    Color bgColor = msg.isUser
                        ? const Color(0xFF1DB954)
                        : (msg.isLog
                              ? (isDark ? Colors.black : Colors.white)
                              : (isDark
                                    ? const Color(0xFF2C2C2E)
                                    : Colors.white));
                    return Align(
                      alignment: msg.isUser
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                          ),
                          border: msg.isUser || msg.isLog
                              ? null
                              : Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: SelectableText(
                          msg.text,
                          style: TextStyle(
                            color: msg.isUser
                                ? Colors.white
                                : (msg.isLog
                                      ? _getLogColor(msg.text, isDark)
                                      : (msg.text.contains('Erro exato')
                                            ? Colors.redAccent
                                            : (isDark
                                                  ? Colors.white
                                                  : Colors.black87))),
                            fontSize: msg.isLog ? 11 : 14,
                            fontFamily: msg.isLog ? 'monospace' : null,
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (_isLoading)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black54 : Colors.white70,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          const CupertinoActivityIndicator(radius: 10),
                          const SizedBox(width: 8),
                          Text(
                            'SpotifAI trabalhando...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text(
          'Terminal',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        backgroundColor: isDark ? Colors.black : Colors.white,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: LogService().logsNotifier,
        builder: (context, logs, child) {
          if (logs.isEmpty)
            return const Center(child: Text('A aguardar eventos...'));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              Color textColor = Colors.grey[400]!;
              if (log.contains('❌') || log.contains('ERRO'))
                textColor = Colors.redAccent;
              if (log.contains('✅') || log.contains('sucesso'))
                textColor = const Color.fromARGB(255, 8, 124, 12);
              if (log.contains('🚀') ||
                  log.contains('🧠') ||
                  log.contains('UI'))
                textColor = Colors.blueAccent;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6.0),
                child: SelectableText(
                  log,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: textColor,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// --- PÁGINA DE TUTORIAL BYOK ---
class TutorialPage extends StatelessWidget {
  const TutorialPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      appBar: AppBar(
        title: Text('Como criar sua Chave Spotify', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? Colors.black : Colors.white,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Liberte o poder do SpotifAI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)),
          const SizedBox(height: 16),
          Text('Para usar a IA sem limites, você precisa conectar o aplicativo diretamente à sua própria conta de desenvolvedor do Spotify. É grátis e leva 2 minutos.', style: TextStyle(fontSize: 16, color: isDark ? Colors.grey[400] : Colors.grey[700])),
          const SizedBox(height: 32),
          
          _buildStep(isDark, '1', 'Acesse o Painel de Desenvolvedor', 'Vá para developer.spotify.com/dashboard e faça login com sua conta normal do Spotify.'),
          // Exemplo de onde colocar seu print:
          // Image.asset('assets/images/tutorial_step1.png', height: 200),
          const SizedBox(height: 24),
          
          _buildStep(isDark, '2', 'Crie um App', 'Clique no botão "Create App". Dê o nome de "SpotifAI Personal" e uma descrição qualquer. Na opção "Redirect URI", coloque: http://localhost:8080/ (ou o link do seu site). Marque as caixinhas aceitando os termos e salve.'),
          const SizedBox(height: 24),
          
          _buildStep(isDark, '3', 'Copie suas Chaves', 'Na página do seu novo App, clique em "Settings" (Configurações). Lá você verá o seu "Client ID". Clique em "View Client Secret" para revelar a segunda chave. Copie ambas.'),
          const SizedBox(height: 24),
          
          _buildStep(isDark, '4', 'Cole no SpotifAI', 'Volte para o nosso aplicativo, clique em "Colocar Chave" no menu e cole os dois códigos. Pronto! O app agora é 100% seu.'),
          
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954), padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              onPressed: () => Navigator.pop(context), 
              child: const Text('Entendi, vamos lá!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStep(bool isDark, String number, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(backgroundColor: const Color(0xFF1DB954), radius: 16, child: Text(number, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(desc, style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 14, height: 1.4)),
            ],
          ),
        )
      ],
    );
  }
}
