import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:premium_ui_kit/premium_ui_kit.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../../services/spotify_service.dart';
import '../../services/ai_service.dart';
import '../../services/log_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLog; 
  ChatMessage({required this.text, required this.isUser, this.isLog = false});
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
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  
  bool _isListening = false;
  bool _isLoading = false; 
  bool _isSaving = false;
  bool _showLogsInChat = false; 
  double _loadingProgress = 0.0;

  late stt.SpeechToText _speech;

  final List<ChatConversation> _conversations = [];
  late ChatConversation _activeConversation;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _searchController.addListener(() => setState(() {})); 
    
    _activeConversation = ChatConversation(
      id: DateTime.now().millisecondsSinceEpoch.toString(), 
      title: 'Nova Curadoria', 
      messages: []
    );
    _conversations.insert(0, _activeConversation);

    LogService().onNewLog = (String log) {
      if (mounted) {
        setState(() {
          if (_showLogsInChat) {
            _activeConversation.messages.add(ChatMessage(text: log, isUser: false, isLog: true));
            _scrollToBottom();
          }

          if (log.contains('👆 UI: Usuário enviou')) _loadingProgress = 0.05;
          if (log.contains('🧠 AI: Analisando')) _loadingProgress = 0.15;
          if (log.contains('🚀 AI: Disparando')) _loadingProgress = 0.3;
          if (log.contains('✅ AI: Resposta recebida')) _loadingProgress = 0.6;
          if (log.contains('🔍 SPOTIFY: Buscando')) _loadingProgress = 0.85;
          
          if (log.contains('⏳ SPOTIFY: Baixando playlist')) _loadingProgress = 0.4;
          
          if (log.contains('💾 UI: Tentando salvar')) _loadingProgress = 0.1;
          if (log.contains('⏳ SPOTIFY: Solicitando')) _loadingProgress = 0.4;
          if (log.contains('✅ SPOTIFY: Playlist criada')) _loadingProgress = 0.7;

          if (log.contains('✅ SPOTIFAI: Curadoria concluída!') || log.contains('✅ SPOTIFY: SUCESSO') || log.contains('✅ SPOTIFY: Playlist')) {
            _loadingProgress = 1.0;
          }
        });

        if (_loadingProgress >= 1.0) {
          Future.delayed(const Duration(milliseconds: 1200), () {
            if (mounted && _loadingProgress >= 1.0) setState(() => _loadingProgress = 0.0);
          });
        }
      }
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    _urlController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _toggleTheme() {
    themeNotifier.value = themeNotifier.value == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
  }

  void _scrollToBottom() {
    if (_chatScrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 600), () {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Color _getLogColor(String log, bool isDark) {
    if (log.contains('❌') || log.contains('ERRO')) return Colors.redAccent;
    if (log.contains('✅') || log.contains('sucesso') || log.contains('SUCESSO')) return const Color(0xFF1DB954);
    if (log.contains('🚀') || log.contains('🧠') || log.contains('UI') || log.contains('SPOTIFY')) return Colors.blueAccent;
    return isDark ? Colors.grey[400]! : Colors.grey[800]!;
  }

  void _importPlaylist(String url) async {
    if (url.isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();

    // VALIDAÇÃO DE LOGIN ANTES DE IMPORTAR
    if (!SpotifyService().isLogged) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ Conecte o Spotify no menu lateral antes de importar.'),
        backgroundColor: Colors.redAccent,
      ));
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
        _activeConversation.tracks = List<Map<String, String>>.from(result['tracks']);
        _activeConversation.messages.add(ChatMessage(
          text: 'Acabei de importar a playlist **"${result['title']}"**. Quais músicas você quer trancar no cadeado e qual o estilo que devemos buscar para as próximas adições?',
          isUser: false
        ));
        _isLoading = false;
      });
      LogService().add('✅ SPOTIFAI: Curadoria concluída!');
      _scrollToBottom();
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Falha ao importar. O link é uma playlist válida e pública?'),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  void _submitSearch(String value) async {
    if (value.isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _activeConversation.messages.add(ChatMessage(text: value, isUser: true));
      _searchController.clear();
    });
    _scrollToBottom();
    LogService().add('👆 UI: Usuário enviou: "$value"');

    try {
      String historyContext = _activeConversation.messages
          .where((m) => !m.isLog) 
          .map((m) => "${m.isUser ? 'Usuário' : 'SpotifAI'}: ${m.text}")
          .join("\n");
      
      String currentPlaylistState = _activeConversation.tracks.isEmpty
          ? "ESTADO DA PLAYLIST: Nenhuma playlist carregada. Opere no MODO CRIADOR."
          : "PLAYLIST ATUAL NO SISTEMA (Opere no MODO EDITOR. Mantenha essa lista intacta, exceto pelo que o usuário alterar):\n" + 
            _activeConversation.tracks.map((t) => "- ${t['title']} (${t['artist']})").join('\n');
      
      List<String> lockedInfo = _activeConversation.tracks
          .where((t) => t['locked'] == 'true')
          .map((t) => "- ${t['title']} (${t['artist']})")
          .toList();
          
      String lockedConstraint = lockedInfo.isEmpty 
          ? "" 
          : "REGRA ABSOLUTA: As seguintes músicas estão TRANCADAS pelo usuário. Você DEVE obrigatóriamente incluí-las na sua resposta JSON final, sem alterar seus nomes:\n${lockedInfo.join('\n')}\n\n";
      
      String promptComContexto = "Histórico da conversa:\n$historyContext\n\n$currentPlaylistState\n\n$lockedConstraint Novo pedido do Usuário: $value\nLembre-se de retornar aquele formato JSON duplo com 'chat_reply' e 'playlist_update'.";

      final aiResult = await AiService().generatePlaylist(promptComContexto);

      if (aiResult != null && mounted) {
        final chatReply = aiResult['chat_reply'] ?? aiResult['description'] ?? 'Aqui está sua atualização!';
        final playlistData = aiResult['playlist_update'] ?? aiResult; 
        
        List<Map<String, String>> newTracks = [];

        if (playlistData['tracks'] != null) {
          final rawTracks = playlistData['tracks'] as List;
          LogService().add('🔍 SPOTIFY: Buscando metadados para ${rawTracks.length} músicas...');

          for (var t in rawTracks) {
            String trackTitle = t['title'] ?? t['titulo'] ?? t['nome'] ?? 'Sem título';
            String trackArtist = t['artist'] ?? t['artista'] ?? t['banda'] ?? 'Desconhecido';

            var existingLockedTrack = _activeConversation.tracks.cast<Map<String, String>?>().firstWhere(
              (oldTrack) => oldTrack!['locked'] == 'true' && oldTrack['title']?.toLowerCase() == trackTitle.toLowerCase(),
              orElse: () => null
            );

            if (existingLockedTrack != null) {
              newTracks.add(existingLockedTrack); 
              continue;
            }

            try {
              final spotifyData = await SpotifyService().searchTrack(trackTitle, trackArtist);
              newTracks.add({
                'title': trackTitle, 'artist': trackArtist,
                'id': spotifyData?['id'] ?? '', 'image': spotifyData?['image'] ?? '',
                'locked': 'false', 
              });
            } catch (e) {
              LogService().add('⚠️ REDE: Falha ao buscar "${t['title']}". Usando fallback.');
              newTracks.add({'title': t['title'] ?? 'Erro', 'artist': t['artist'] ?? '', 'id': '', 'image': '', 'locked': 'false'});
            }
          }
        }

        setState(() {
          _activeConversation.messages.add(ChatMessage(text: chatReply, isUser: false));
          _activeConversation.tracks = newTracks;
          _activeConversation.title = playlistData['title'] ?? _activeConversation.title;
          _isLoading = false;
        });
        
        LogService().add('✅ SPOTIFAI: Curadoria concluída!');
        _scrollToBottom();
      }
    } catch (e) {
      LogService().add('❌ ERRO CRÍTICO: $e');
      if (mounted) {
        setState(() {
          _activeConversation.messages.add(ChatMessage(text: 'Falha no sistema. Abra os logs.', isUser: false));
          _isLoading = false;
        });
        LogService().add('✅ SPOTIFAI: Curadoria concluída!'); 
        _scrollToBottom();
      }
    }
  }

  void _savePlaylist() async {
    if (_activeConversation.tracks.isEmpty || _isSaving) return;
    
    // VALIDAÇÃO DE LOGIN ANTES DE SALVAR
    if (!SpotifyService().isLogged) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('❌ Conecte o Spotify no menu lateral antes de salvar.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }

    setState(() => _isSaving = true);
    LogService().add('💾 UI: Tentando salvar a playlist...');

    List<String> trackUris = _activeConversation.tracks
        .where((t) => t['id'] != null && t['id']!.isNotEmpty)
        .map((t) => t['id']!)
        .toList();

    bool sucesso = await SpotifyService().createAndPopulatePlaylist(
      _activeConversation.title, "Gerada pelo SpotifAI Copilot", trackUris
    );

    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sucesso ? 'Playlist salva no Spotify! 🔥' : 'Erro ao salvar playlist.'),
        backgroundColor: sucesso ? const Color(0xFF1DB954) : Colors.redAccent,
      ));
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) { if (val == 'done' || val == 'notListening') setState(() => _isListening = false); },
        onError: (val) => setState(() => _isListening = false),
      );
      if (available) {
        setState(() { _isListening = true; _searchController.clear(); });
        _speech.listen(onResult: (val) => setState(() => _searchController.text = val.recognizedWords), localeId: 'pt_BR');
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  void _startNewConversation() {
    setState(() {
      _activeConversation = ChatConversation(id: DateTime.now().millisecondsSinceEpoch.toString(), title: 'Nova Curadoria', messages: []);
      _conversations.insert(0, _activeConversation);
      _searchController.clear();
      _urlController.clear();
    });
    Navigator.pop(context);
  }

  void _switchConversation(ChatConversation conversation) {
    setState(() { _activeConversation = conversation; });
    Navigator.pop(context);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppleKitColors>()!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final bool hasStarted = _activeConversation.messages.isNotEmpty || _activeConversation.tracks.isNotEmpty;

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
                  duration: const Duration(milliseconds: 1200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0.0, 0.05), end: Offset.zero).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: !hasStarted
                      ? SizedBox(key: const ValueKey('initial_state'), child: _buildInitialState(isDark)) 
                      : SizedBox(key: const ValueKey('split_screen'), child: _buildSplitScreenResults(isDark, colors)),
                ),
              ),
              
              // ... Fim do Expanded(child: AnimatedSwitcher(...)) ...
              

              // 1. O ESPAÇO AGORA VEM ANTES DA BARRA (Para desgrudar do chat de cima)
              const SizedBox(height: 16), 

              // 2. A BARRA DE PROGRESSO (Sem o padding inferior grande, para grudar na caixa)
              AnimatedOpacity(
                opacity: _loadingProgress > 0 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: Padding(
                  padding: const EdgeInsets.only(left: 4, right: 4, bottom: 0), // bottom de 12 para 4
                  child: Container(
                    height: 2,
                    width: double.infinity,
                    decoration: BoxDecoration(color: isDark ? Colors.white10 : Colors.black, borderRadius: BorderRadius.circular(2)),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 800), 
                            curve: Curves.easeInOutCubic,
                            width: constraints.maxWidth * _loadingProgress,
                            decoration: BoxDecoration(
                              color: Colors.grey, 
                              borderRadius: BorderRadius.circular(2),
                              boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1))]
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),

             
              const SizedBox(height: 12), // ESPAÇO PARA DESGRUDAR O CHAT DA BARRA

              Column(
                children: [
                  AnimatedSize(
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeInOutCubic,
                    child: hasStarted 
                      ? const SizedBox(width: double.infinity, height: 0) 
                      : Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF1DB954).withOpacity(isDark ? 0.2 : 0.1),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF1DB954).withOpacity(0.5)),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Row(
                                children: [
                                  const Icon(CupertinoIcons.link, color: Color(0xFF1DB954), size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _urlController,
                                      style: TextStyle(color: isDark ? Colors.white : Colors.black),
                                      decoration: InputDecoration(
                                        hintText: 'Colar Playlist',
                                        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
                                        border: InputBorder.none,
                                      ),
                                      onSubmitted: _importPlaylist,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(CupertinoIcons.arrow_right_circle_fill, color: Color(0xFF1DB954)),
                                    onPressed: () async {
                                      ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
                                      if (data != null && data.text != null && data.text!.isNotEmpty) {
                                        setState(() => _urlController.text = data.text!);
                                        _importPlaylist(data.text!);
                                      } else if (_urlController.text.isNotEmpty) {
                                        _importPlaylist(_urlController.text);
                                      }
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
                    hintText: _isListening ? 'Ouvindo...' : 'Criar nova Playlist...',
                    onSubmitted: _submitSearch,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _searchController.text.isNotEmpty ? CupertinoIcons.arrow_up_circle_fill : (_isListening ? CupertinoIcons.mic_fill : CupertinoIcons.mic),
                        color: _searchController.text.isNotEmpty ? const Color(0xFF1DB954) : (_isListening ? Colors.redAccent : colors.frostedGlassText),
                        size: _searchController.text.isNotEmpty ? 28 : 24,
                      ),
                      onPressed: () {
                        if (_searchController.text.isNotEmpty) _submitSearch(_searchController.text);
                        else _listen();
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
    final bool hasStarted = _activeConversation.messages.isNotEmpty || _activeConversation.tracks.isNotEmpty;

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
            leading: Builder(builder: (context) => IconButton(icon: Icon(CupertinoIcons.line_horizontal_3, color: isDark ? Colors.white : Colors.black87), onPressed: () => Scaffold.of(context).openDrawer())),
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: hasStarted 
                ? Row(
                    key: const ValueKey('appbar_title_active'),
                    children: [
                      ClipOval(child: Image.asset('assets/images/logo_bw.png', height: 32, width: 32, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.music_albums, size: 24, color: Colors.grey))),
                      const SizedBox(width: 8),
                      Text('SPOTIFAI', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontSize: 16, fontWeight: FontWeight.w900)),
                    ],
                  ) 
                : const SizedBox.shrink(key: ValueKey('appbar_title_empty')),
            ),
            actions: [ThemeToggleButton(isDark: isDark, onToggle: _toggleTheme), const SizedBox(width: 8)],
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
                  decoration: BoxDecoration(color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(12)), 
                  child: Row(children: [Icon(CupertinoIcons.add, color: isDark ? Colors.white : Colors.black), const SizedBox(width: 12), Text('Novo Chat Musical', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold))])
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
                    selectedTileColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                    leading: Icon(CupertinoIcons.chat_bubble_2, color: isActive ? const Color(0xFF1DB954) : colors.frostedGlassText, size: 20),
                    title: Text(conv.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isActive ? (isDark ? Colors.white : Colors.black) : colors.frostedGlassText, fontSize: 14, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                    onTap: () => _switchConversation(conv),
                  );
                },
              ),
            ),

            Divider(color: Colors.grey.withOpacity(0.2)),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const LogsPage()));
                },
                child: PremiumCard(
                  color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[200],
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [const Icon(CupertinoIcons.doc_text_viewfinder, color: Colors.blueAccent), const SizedBox(width: 16), Text('Visualizar Logs', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold))]),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: PremiumCard(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.grey[200],
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.terminal_rounded, color: Colors.orangeAccent), 
                        const SizedBox(width: 16), 
                        Text('Logs no Chat', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    CupertinoSwitch(
                      activeColor: Colors.orangeAccent,
                      value: _showLogsInChat,
                      onChanged: (val) {
                        setState(() => _showLogsInChat = val);
                      },
                    ),
                  ],
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0, top: 4.0),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () async {
                  bool sucesso = await SpotifyService().authenticateUser();
                  if (sucesso && mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Spotify Conectado!'), backgroundColor: Color(0xFF1DB954))); }
                },
                child: PremiumCard(
                  color: const Color(0xFF1DB954).withOpacity(0.15),
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [const Icon(CupertinoIcons.play_circle_fill, color: Color(0xFF1DB954), size: 32), const SizedBox(width: 16), Text('Conectar Spotify', style: TextStyle(color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold))]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialState(bool isDark) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [ClipOval(child: Image.asset('assets/images/logo_bw.png', height: 120, width: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.music_albums, size: 100, color: Colors.grey))), const SizedBox(height: 24), Text('SPOTIFAI', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black)), const SizedBox(height: 16), Text('Qual a vibe de hoje?', style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[600]))]);
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
                      Expanded(child: Text(_activeConversation.title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                      GestureDetector(
                        onTap: _isSaving ? null : _savePlaylist, 
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                          decoration: BoxDecoration(color: const Color(0xFF1DB954), borderRadius: BorderRadius.circular(16)), 
                          child: _isSaving ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Text('Salvar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
                        )
                      )
                    ],
                  ),
                ),
                Expanded(
                  child: _activeConversation.tracks.isEmpty 
                    ? const Center(child: Text('Nenhuma faixa carregada.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                    itemCount: _activeConversation.tracks.length, 
                    itemBuilder: (context, index) { 
                      final track = _activeConversation.tracks[index]; 
                      final bool isLocked = track['locked'] == 'true'; 

                      return ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8), 
                          child: track['image']!.isNotEmpty 
                            ? Image.network(track['image']!, width: 40, height: 40, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(CupertinoIcons.music_note, color: Colors.grey)) 
                            : Container(width: 40, height: 40, color: Colors.grey[800], child: const Icon(CupertinoIcons.music_note, color: Colors.grey))
                        ), 
                        title: Text(track['title'] ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)), 
                        subtitle: Text(track['artist'] ?? '', style: TextStyle(color: Colors.grey[400], fontSize: 12)), 
                        
                        trailing: IconButton(
                          icon: Icon(
                            isLocked ? CupertinoIcons.lock_fill : CupertinoIcons.lock_open,
                            color: isLocked ? const Color(0xFF1DB954) : Colors.grey[600],
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              track['locked'] = isLocked ? 'false' : 'true';
                            });
                          },
                        )
                      ); 
                    }
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
                        : (msg.isLog ? (isDark ? Colors.black : Colors.white) : (isDark ? const Color(0xFF2C2C2E) : Colors.white));
                        
                    return Align(
                      alignment: msg.isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: bgColor,
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(msg.isUser ? 16 : 4),
                            bottomRight: Radius.circular(msg.isUser ? 4 : 16),
                          ),
                          border: msg.isUser || msg.isLog ? null : Border.all(color: Colors.grey.withOpacity(0.2)),
                        ),
                        child: SelectableText(
                          msg.text,
                          style: TextStyle(
                            color: msg.isUser 
                                ? Colors.white 
                                : (msg.isLog ? _getLogColor(msg.text, isDark) : (msg.text.contains('Erro exato') ? Colors.redAccent : (isDark ? Colors.white : Colors.black87))),
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
                      decoration: BoxDecoration(color: isDark ? Colors.black54 : Colors.white70, borderRadius: BorderRadius.circular(16)),
                      child: Row(
                        children: [
                          const CupertinoActivityIndicator(radius: 10),
                          const SizedBox(width: 8),
                          Text('SpotifAI trabalhando...', style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[600]))
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
      appBar: AppBar(title: Text('Terminal', style: TextStyle(color: isDark ? Colors.white : Colors.black)), backgroundColor: isDark ? Colors.black : Colors.white, iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black)),
      body: ValueListenableBuilder<List<String>>(
        valueListenable: LogService().logsNotifier,
        builder: (context, logs, child) {
          if (logs.isEmpty) return const Center(child: Text('A aguardar eventos...'));
          return ListView.builder(
            padding: const EdgeInsets.all(16), itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              Color textColor = Colors.grey[400]!;
              if (log.contains('❌') || log.contains('ERRO')) textColor = Colors.redAccent;
              if (log.contains('✅') || log.contains('sucesso')) textColor = const Color.fromARGB(255, 8, 124, 12);
              if (log.contains('🚀') || log.contains('🧠') || log.contains('UI')) textColor = Colors.blueAccent;
              return Padding(padding: const EdgeInsets.only(bottom: 6.0), child: SelectableText(log, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: textColor)));
            },
          );
        },
      ),
    );
  }
}