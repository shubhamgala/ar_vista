import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../services/voice_service.dart';
import '../services/yolo_service.dart';
import '../services/rag_service.dart';
import '../services/language_service.dart';
import '../services/sentiment_service.dart';
import '../main.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'maps.dart';
import 'nearby_places_screen.dart';
import '../widgets/itinerary_setup_sheet.dart';

class ARScreen extends StatefulWidget {
  const ARScreen({super.key});

  @override
  State<ARScreen> createState() => _ARScreenState();
}

class _ARScreenState extends State<ARScreen> {
  CameraController? _cameraController;
  bool _isReady = false;
  bool _isListening = false;
  bool _isHoldActive = false;  // 🔒 Hold Picture feature
  bool _isDetecting = false;   // 🔍 YOLO detection in progress
  bool _isStartupScanning = false; // 🔍 Scanning badge at startup
  bool _detectionReady = false;    // ✅ True only after context was spoken
  String? _frozenFramePath;    // path to captured still frame
  String? _lastDetectedClass;  // 🏛️ last successfully detected YOLO class
  Map<String, double>? _detectedCoords; // lat/lng for detected class
  String _conversation = "";
  double _speechRate = 1.0;
  bool _isDetailed = false;
  bool _showChatBox = false;

  final VoiceService _voiceService = VoiceService();
  final YoloService _yoloService = YoloService();
  final RAGService _ragService = RAGService();
  final LanguageService _languageService = LanguageService();
  final SentimentService _sentimentService = SentimentService();

  final String _modelFile = 'assets/all_anim.glb';
  String? _currentAnimation = 'waving';
  String _currentLanguage = 'en';
  String _currentSentiment = 'neutral';
  int _responseCount = 0; // alternates talking vs pointing_right animation

  /// Returns animations in a specific pattern:
  /// Every 6th: talking
  /// Every 2nd (except 6th): pointing_right
  /// Others: talking
  String _nextTalkingAnimation() {
    _responseCount++;
    if (_responseCount % 6 == 0) return 'talking';
    if (_responseCount % 2 == 0) return 'pointing_right';
    return 'talking';
  }

  @override
  void initState() {
    super.initState();
    _initCamera();
    _initRAG();
  }

  // Guard to ensure auto-detection runs only once on startup
  bool _autoDetectionDone = false;
  // Holds detected context until intro finishes
  String? _pendingStartupContext;

  Future<void> _initCamera() async {
    _cameraController = CameraController(
      cameras![0],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _cameraController?.initialize();
    if (!mounted) return;

    setState(() => _isReady = true);

    // 1 second for camera warm-up
    await Future.delayed(const Duration(seconds: 1));

    // Run YOLO detection in background — capture result before speaking
    final detectionFuture = _runStartupDetection();

    final introCompleter = Completer<void>();
    _voiceService.playIntroAudio(
      isHindi: _currentLanguage == 'hi',
      onStart: () => setState(() => _currentAnimation = 'talking'),
      onEnd: () {
        print('🤖 Intro audio finished signalling Completer');
        if (!introCompleter.isCompleted) introCompleter.complete();
      },
    );

    // Wait for BOTH intro to finish AND detection to complete
    print('⏳ Waiting for intro + YOLO detection...');
    await Future.wait([introCompleter.future, detectionFuture]);

    // Small gap so audio player resets cleanly between clips
    print('⏳ Sequential gap (1200ms)...');
    await Future.delayed(const Duration(milliseconds: 1200));
    if (mounted) await _speakPendingContext();
  }

  /// 🔍 Captures frames, runs YOLO (with Gemini Vision fallback), stores result.
  Future<void> _runStartupDetection() async {
    if (_autoDetectionDone) return;
    _autoDetectionDone = true;

    if (mounted) setState(() => _isStartupScanning = true);

    // Warmup delay so camera gets a stable frame
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    // ——— All YOLO class names exactly as the model returns them ———
    const knownLandmarks = [
      'Shrimant_Dagdusheth_Halwai_Ganpati_Bappa',
      'Taj_Mahal',
      'Gate Way of India',  // YOLO uses spaces, not underscores
      'Taj Hotel',
      'Taxi',
      'Boat',
    ];
    const knownCampus = [
      'Achievement', 'Benches', 'Classroom', 'Corridor',
      'CSEDS_Gate', 'CSEDS_Staff_Room', 'Lab', 'PC',
    ];
    final allKnown = [...knownLandmarks, ...knownCampus];

    String? detected;
    XFile? photo;

    // ——— Try YOLO up to 2 times ———
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        photo = await _cameraController?.takePicture();
        if (photo == null) break;

        final yoloResult = await _yoloService.detectObject(photo.path);
        print('🔍 YOLO attempt $attempt: $yoloResult');

        final isKnownClass = allKnown.any(
          (k) => k.toLowerCase() == yoloResult.toLowerCase(),
        );
        if (isKnownClass) {
          detected = yoloResult;
          break;
        }
      } catch (e) {
        print('⚠️ YOLO attempt $attempt error: $e');
      }
      if (attempt < 2) await Future.delayed(const Duration(milliseconds: 800));
    }

    // ——— Gemini Vision fallback when YOLO doesn\'t recognise the landmark ———
    if ((detected == null || detected.isEmpty) && photo != null && mounted) {
      print('🔍 YOLO unknown — trying Gemini Vision fallback...');
      detected = await _identifyWithGeminiVision(photo.path);
      print('🧠 Gemini Vision result: $detected');
    }

    if (!mounted) {
      setState(() => _isStartupScanning = false);
      return;
    }

    if (detected == null || detected.isEmpty) {
      setState(() => _isStartupScanning = false);
      return;
    }

    // Look up hardcoded context (no API call)
    final context = _ragService.getContextForClass(detected,
        language: _currentLanguage);

    if (context == null || context.isEmpty) {
      setState(() => _isStartupScanning = false);
      return;
    }

    // Store context — will be spoken when intro finishes
    _pendingStartupContext = context;

    // Store class + coords for action buttons
    final coords = _ragService.getCoordinatesForClass(detected);

    // 📍 Propagate location to RAG for nearby-places queries
    if (coords != null) {
      _ragService.setLocationContext(
        detected.replaceAll('_', ' '),
        coords['lat']!,
        coords['lng']!,
      );
    }

    final detectedLabel = detected.replaceAll('_', ' ');
    setState(() {
      _lastDetectedClass = detected;
      _detectedCoords = coords;
      _conversation += '\n📸 Detected: $detectedLabel\n🤖 Guide: $context\n';
      _showChatBox = true;
      _isStartupScanning = false;
    });

    print('📋 Detection ready — will speak after intro finishes.');
  }

  /// 🧠 Use Gemini Vision to identify a landmark from an image file.
  /// Returns a key matching _classKnowledge, or empty string if unrecognised.
  Future<String> _identifyWithGeminiVision(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final base64Image = base64Encode(bytes);

      const apiKey = 'AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA';
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  }
                },
                {
                  'text':
                      'Identify if this image shows one of these landmarks: '
                      'Gateway of India Mumbai, Taj Mahal Palace Hotel Mumbai, Taj Mahal Agra, '
                      'Shrimant Dagdusheth Halwai Ganpati Pune. '
                      'Reply with ONLY the exact key matching what you see: '
                      '"Gate Way of India" OR "Taj Hotel" OR "Taj_Mahal" OR "Shrimant_Dagdusheth_Halwai_Ganpati_Bappa". '
                      'If none are visible, reply with: unknown'
                }
              ]
            }
          ],
          'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 30},
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw =
            data['candidates']?[0]?['content']?['parts']?[0]?['text']
                as String? ??
            '';
        final key = raw.trim().split('\n').first.trim();
        // Must match EXACT YOLO class names
        const validKeys = [
          'Gate Way of India',
          'Taj_Mahal',
          'Taj Hotel',
          'Shrimant_Dagdusheth_Halwai_Ganpati_Bappa',
        ];
        if (validKeys.contains(key)) return key;
      }
    } catch (e) {
      print('⚠️ Gemini Vision error: $e');
    }
    return '';
  }

  /// 🔊 Called by intro onEnd — speaks detected context as seamless continuation
  Future<void> _speakPendingContext() async {
    final context = _pendingStartupContext;
    print('🔈 _speakPendingContext called. Context present: ${context != null}');
    if (context == null || context.isEmpty || !mounted) return;

    // Clear pending so it doesn't fire twice
    _pendingStartupContext = null;

    print('🔈 Starting landmark audio: ${context.substring(0, context.length > 30 ? 30 : context.length)}...');

    await _voiceService.speakWithElevenLabs(
      context,
      rate: _speechRate,
      isHindi: _currentLanguage == 'hi',
      onStart: () => setState(() => _currentAnimation = _nextTalkingAnimation()),
    );

    if (!mounted) return;
    // ✅ Mark detection as fully ready AFTER context is spoken
    // — this is when Explore Nearby + Plan Itinerary buttons become visible
    setState(() {
      _currentAnimation = 'waving';
      _detectionReady = true;
    });
  }

  Future<void> _initRAG() async {
    await _ragService.initialize();
    print('✅ RAG Service initialized with knowledge base');
  }

  /// 📷 Toggle Hold: captures+freezes the frame. YOLO only runs on voice query.
  Future<void> _toggleHold() async {
    if (!_isHoldActive) {
      // ——— Activate hold: capture + freeze current frame only ———
      try {
        final photo = await _cameraController?.takePicture();
        if (photo != null) {
          setState(() {
            _isHoldActive = true;
            _frozenFramePath = photo.path;
          });
          print('📌 Frame held: ${photo.path}');
        }
      } catch (e) {
        print('⚠️ Hold capture error: $e');
        setState(() => _isHoldActive = true);
      }
    } else {
      // ——— Release hold: resume live feed ———
      setState(() {
        _isHoldActive = false;
        _frozenFramePath = null;
      });
    }
  }

  /// 🎤 Enhanced voice query handler with RAG, language detection, and sentiment analysis
  Future<void> _handleVoiceQuery() async {
    if (_isListening) return;
    setState(() => _isListening = true);

    // Set animation to talking
    setState(() => _currentAnimation = 'talking');

    // Listen to user speech
    String? query = await _voiceService.listenUserSpeech();
    if (query == null || query.isEmpty) {
      setState(() {
        _conversation += "\n❌ Couldn't hear properly.\n";
        _isListening = false;
        _currentAnimation = 'waving';
      });
      return;
    }

    // Detect language
    _currentLanguage = _languageService.detectLanguage(query);
    final langName = _languageService.getLanguageName(_currentLanguage);
    print('🗣️ User query: "$query"');
    print('🌍 Detected language: $_currentLanguage ($langName)');

    // DISABLED: Skip sentiment analysis to reduce API calls
    _currentSentiment = await _sentimentService.analyzeSentiment(query);
    // _currentSentiment = 'neutral'; // Use default sentiment
    print('💭 Using default sentiment: $_currentSentiment');
    final sentimentEmoji = _sentimentService.getSentimentEmoji(_currentSentiment); // Still need emoji for UI

    setState(() => _conversation += "\n🗣️ You [$langName $sentimentEmoji]: $query\n");

    // 📸 Use frozen frame if Hold is active, else take a fresh live picture
    String imagePath;
    if (_isHoldActive && _frozenFramePath != null) {
      imagePath = _frozenFramePath!;
      print('📌 Using held frame for YOLO: $imagePath');
    } else {
      final picture = await _cameraController?.takePicture();
      imagePath = picture!.path;
    }
    String detected = await _yoloService.detectObject(imagePath);
    bool objectDetected =
        detected.isNotEmpty && detected.toLowerCase() != "no object detected";

    String reply;
    
    // 🎬 PROACTIVE MODE: If object detected, auto-start conversation
    if (objectDetected && query.isEmpty) {
      setState(() => _conversation += "📸 Detected: $detected\n🤖 Guide starting...\\n");
      
      // Auto-triggered scene dialogue
      reply = await _ragService.generateSceneDialogue(detected, _currentLanguage);

      // ✅ Show reply text IMMEDIATELY in chatbox (before audio starts)
      if (mounted) {
        setState(() {
          // Replace "Guide starting..." line with the actual reply
          _conversation = _conversation.replaceFirst(
            '🤖 Guide starting...\\n', '');
          _conversation += '🤖 Guide: $reply\n';
        });
      }

      // 🔊 Start audio WITHOUT await so text stays visible while audio plays
      _voiceService.speakWithElevenLabs(
        reply,
        rate: _speechRate,
        isHindi: _currentLanguage == 'hi',
        onStart: () {
          if (mounted) setState(() => _currentAnimation = _nextTalkingAnimation());
        },
        onEnd: () {
          if (mounted) setState(() => _currentAnimation = 'waving');
        },
      );
    } else {
      // 💬 CONVERSATIONAL MODE: User asked a question
      if (objectDetected) {
        // 📍 Propagate location context so RAG can answer nearby-places queries
        final voiceCoords = _ragService.getCoordinatesForClass(detected);
        if (voiceCoords != null) {
          _ragService.setLocationContext(
            detected.replaceAll('_', ' '),
            voiceCoords['lat']!,
            voiceCoords['lng']!,
          );
          setState(() {
            _lastDetectedClass = detected;
            _detectedCoords = voiceCoords;
          });
        }
        setState(() => _conversation += "📸 Detected: $detected\n");
      }
      
      setState(() => _conversation += "🤖 Thinking...\n");
      
      // Map sentiment to tourist mode
      final touristMode = _currentSentiment == 'positive' 
          ? TouristMode.excited
          : _currentSentiment == 'confused'
              ? TouristMode.calm
              : TouristMode.storytelling;
      
      // Generate conversational response with memory + detected object context
      reply = await _ragService.generateConversationalResponse(
        query, 
        _currentLanguage, 
        touristMode,
        detectedObject: objectDetected ? detected : _lastDetectedClass,
      );

      // ✅ Show reply text IMMEDIATELY — replace "Thinking..." with actual reply
      if (mounted) {
        setState(() {
          // Remove the last "🤖 Thinking...\n" line and replace with actual reply
          final thinkingTag = '🤖 Thinking...\n';
          if (_conversation.contains(thinkingTag)) {
            _conversation = _conversation.replaceFirst(thinkingTag, '');
          }
          _conversation += '🤖 Guide: $reply\n';
          _showChatBox = true;
        });
      }

      // 🔊 Start audio WITHOUT await — text is already visible, audio plays alongside
      _voiceService.speakWithElevenLabs(
        reply,
        rate: _speechRate,
        isHindi: _currentLanguage == 'hi',
        onStart: () {
          if (mounted) setState(() => _currentAnimation = _nextTalkingAnimation());
        },
        onEnd: () {
          if (mounted) setState(() => _currentAnimation = 'waving');
        },
      );
    }

    // ✅ Only update listening state — reply text already shown above
    if (mounted) {
      setState(() => _isListening = false);
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _voiceService.dispose();
    // No need to dispose RAGService anymore (no database)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isReady) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.orange),
              SizedBox(height: 20),
              Text(
                'Initializing AR Guide...',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Camera preview (live) OR frozen still frame overlay
          Positioned.fill(
            child: _frozenFramePath != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Frozen still image
                      Image.file(
                        File(_frozenFramePath!),
                        fit: BoxFit.cover,
                      ),
                      // "HOLD" badge overlay
                      Positioned(
                        top: 50,
                        right: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade700.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.camera_alt,
                                      color: Colors.white, size: 14),
                                  SizedBox(width: 5),
                                  Text(
                                    'HOLD',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_isDetecting) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.orangeAccent,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Detecting…',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                : CameraPreview(_cameraController!),
          ),

          // 3D AR Guide Model
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 20, bottom: 20),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.5,
                height: MediaQuery.of(context).size.height * 0.65,
                child: ModelViewer(
                  key: ValueKey(_currentAnimation ?? 'waving'),
                  src: _modelFile,
                  alt: '3D guide',
                  ar: false,
                  autoRotate: false,
                  cameraControls: true,
                  disableZoom: false,
                  backgroundColor: Colors.transparent,
                  animationName: _currentAnimation,
                  autoPlay: true,
                  arScale: ArScale.auto,
                ),
              ),
            ),
          ),

          // Language indicator
          Positioned(
            top: 60,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.language, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    _languageService.getLanguageName(_currentLanguage),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Sentiment indicator
          Positioned(
            top: 100,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue, width: 2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _sentimentService.getSentimentEmoji(_currentSentiment),
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _currentSentiment.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Short/Detailed switch
          Positioned(
            top: 140,
            left: 20,
            child: Row(
              children: [
                const Text("Short",
                    style: TextStyle(color: Colors.white, fontSize: 14)),
                Switch(
                  activeColor: Colors.orangeAccent,
                  value: _isDetailed,
                  onChanged: (v) => setState(() => _isDetailed = v),
                ),
                const Text("Detailed",
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),

          // Chat box
          if (_showChatBox)
            Positioned(
              bottom: 175,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxHeight: 360),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isHoldActive ? Colors.amber : Colors.orange,
                    width: 2,
                  ),
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: Text(
                    _conversation,
                    style: const TextStyle(color: Colors.white, fontSize: 14,
                        height: 1.5),
                    softWrap: true,
                    overflow: TextOverflow.visible,
                  ),
                ),
              ),
            ),

          // 🗺️ Explore Nearby + Plan Itinerary — shown ONLY after landmark detected AND context spoken
          if (_detectionReady && _lastDetectedClass != null && _detectedCoords != null)
            Positioned(
              bottom: 110,
              left: 10,
              right: 10,
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.explore, size: 16),
                      label: const Text('Explore Nearby',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => NearbyPlacesScreen(
                              landmarkName:
                                  _lastDetectedClass!.replaceAll('_', ' '),
                              lat: _detectedCoords!['lat']!,
                              lng: _detectedCoords!['lng']!,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepOrange.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Plan Itinerary',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => ItinerarySetupSheet(
                            landmarkName:
                                _lastDetectedClass!.replaceAll('_', ' '),
                            lat: _detectedCoords!['lat']!,
                            lng: _detectedCoords!['lng']!,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

          Positioned(
            bottom: 25,
            left: 0,
            right: 0,
            child: Center(
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  // Map button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const MapScreen()),
                      );
                    },
                    child: const Text(
                      "Map",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),

                  // Chat toggle button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      minimumSize: const Size(54, 54),
                      shape: const CircleBorder(),
                    ),
                    onPressed: () => setState(() => _showChatBox = !_showChatBox),
                    child: Icon(
                      _showChatBox ? Icons.chat_bubble : Icons.chat_bubble_outline,
                      color: Colors.white,
                    ),
                  ),

                  // Voice input button
                  FloatingActionButton(
                    backgroundColor:
                        _isListening ? Colors.redAccent : Colors.orange,
                    onPressed: _handleVoiceQuery,
                    child: Icon(
                      _isListening ? Icons.hearing : Icons.mic,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),

                  // 🔒 Hold Picture toggle button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _isHoldActive ? Colors.amber.shade700 : Colors.grey.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      side: BorderSide(
                        color: _isHoldActive ? Colors.amber : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    onPressed: _toggleHold,
                    icon: Icon(
                      _isHoldActive
                          ? Icons.pause_circle
                          : Icons.pause_circle_outline,
                      size: 20,
                    ),
                    label: Text(
                      _isHoldActive ? 'Held' : 'Hold',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // RAG status indicator (for debugging)
          if (_isListening)
            Positioned(
              top: 180,
              left: 20,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'RAG Processing...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
