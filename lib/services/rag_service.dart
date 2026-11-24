import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'nearby_places_service.dart';
import '../models/itinerary_model.dart';

// 🎭 Tourist Emotion Modes (must be outside class)
enum TouristMode {
  excited,      // Enthusiastic, energetic
  calm,         // Peaceful, meditative
  storytelling  // Narrative, engaging
}

class RAGService {
  final String geminiApiKey = "AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA";
  
  // Knowledge base loaded from JSON
  final Map<String, List<Map<String, dynamic>>> _knowledgeBase = {};
  bool _isInitialized = false;
  
  // 🗺️ Nearby places service
  final NearbyPlacesService _nearbyService = NearbyPlacesService();

  // 💬 Conversation Memory (last 20 turns, persisted across sessions)
  final List<Map<String, String>> _conversationHistory = [];
  String? _lastDetectedObject;

  // 📍 Current location context (set when landmark is detected)
  double? _currentLat;
  double? _currentLng;
  String? _currentLandmarkName;
  
  // 🧠 User Memory for Personalization
  final Map<String, dynamic> _userMemory = {
    'preferences': <String, int>{}, // Topic interest scores
    'pastQueries': <String>[],
    'favoriteMode': TouristMode.storytelling,
    'language': 'en',
    'visitedTopics': <String>[],
  };

  // 📚 Hardcoded instant knowledge for all YOLO-detected classes
  // No API call needed — used for startup auto-detection greeting
  static const Map<String, String> _classKnowledge = {
    'Achievement':
        'Welcome to the Achievement Wall,' 
        'celebrating the outstanding accomplishments of our students and faculty.' 
        'It highlights awards, national recognitions, and key milestones that reflect the excellence and pride of our institution. Explore and be inspired!',

    'Benches':
        'These are the campus benches — a beloved gathering spot for students '
        'to relax, discuss ideas, and form friendships between classes. '
        'This open space is the social heartbeat of our college campus. ',

    'Classroom':
        'Welcome to the classroom, where curiosity meets knowledge every day. '
        'Our classrooms are equipped for interactive learning, enabling students '
        'to engage deeply with faculty and peers. This is where future engineers '
        'and innovators begin their journey.',

    'Corridor':
        'This college corridor is the lifeline connecting departments and facilities.'
        'Students and faculty pass through between lectures, labs, and offices—feel the '
        'vibrant academic buzz around you.',

    'CSEDS_Gate':
        'You are standing at the CSEDS Gate — the main entrance to the Computer '
        'Science and Engineering Department. Welcome to the '
        'hub of computing excellence!',

    'CSEDS_Staff_Room':
        'This is the CSEDS Staff Room, where our dedicated faculty members '
        'prepare lectures, conduct research, and guide students. It is the '
        'intellectual nerve center of the department, where mentorship and '
        'academic guidance come to life every day.',

    'Lab':
        'Welcome to the Computer Laboratory! This state-of-the-art lab is '
        'equipped with modern workstations for programming, networking, and '
        'research. Students work on real-world projects here, bringing their '
        'academic learning into practical application.',

    'PC':
        'These are the personal computers in our lab, each a gateway to '
        'programming, data analysis, simulations, and creative projects. '
        'Students use these systems to build software, run experiments, '
        'and develop the skills that power the digital world.',

    'Shrimant_Dagdusheth_Halwai_Ganpati_Bappa':
        'Ganpati Bappa Morya , You are in the presence of the Shrimant Dagdusheth Halwai Ganpati,' 
        'established in the 19th century, is one of Pune\'s most revered temples.'
        'Surrounded by Tulsi Baug, Laxmi Road, and Shaniwar Wada.',

    'Taj_Mahal':
        'Welcome to the magnificent Taj Mahal, one of the Seven Wonders of the World.' 
        'Built in 1632 by Emperor Shah Jahan in memory of Mumtaz Mahal,' 
        'this UNESCO World Heritage Site is a masterpiece of Mughal architecture, famed for its shimmering white marble.',

    'Gate Way of India':
        'Welcome to the Gateway of India, Mumbai’s most iconic landmark.'
        'Built in 1924, Located at Apollo Bunder on the Arabian Sea,'
        'with the iconic Taj Mahal Palace Hotel behind it and Colaba Causeway nearby for street shopping and local food.',

    'Taj Hotel':
        'The Taj Mahal Palace Hotel, built in 1903, is Mumbai’s most iconic luxury hotel,'
        'overlooking the Gateway of India and the Arabian Sea.',

    'Taxi':
        'The iconic Mumbai black-and-yellow taxi has been a symbol of the city’s fast-paced life,'
        'offering affordable rides across its bustling streets.',

    'Boat':
        'You are looking at a boat on the waters near Mumbai. '
        'The harbour ferries and tourist boats here connect the Gateway of India to the Elephanta Caves, '
        'a UNESCO World Heritage Site just 10 km away. Boat rides are a wonderful way to see Mumbai from the sea.',
  };

  // � Hindi translations for startup knowledge
  static const Map<String, String> _classKnowledgeHindi = {
    'Achievement':
        'उपलब्धि दीवार में आपका स्वागत है, जो हमारे छात्रों और शिक्षकों की उत्कृष्ट उपलब्धियों का जश्न मनाती है। '
        'यह पुरस्कारों, राष्ट्रीय मान्यताओं और प्रमुख मील के पत्थर पर प्रकाश डालती है। '
        'घूमें और प्रेरित हों!',

    'Benches':
        'ये परिसर के बेंच हैं — छात्रों के लिए आराम करने, विचारों पर चर्चा करने और कक्षाओं के बीच दोस्ती बनाने के लिए एक पसंदीदा मिलन स्थल। '
        'यह खुला स्थान हमारे कॉलेज परिसर का सामाजिक हृदय है।',

    'Classroom':
        'कक्षा में आपका स्वागत है, जहाँ जिज्ञासा हर दिन ज्ञान से मिलती है। '
        'हमारी कक्षाएँ इंटरैक्टिव सीखने के लिए सुसज्जित हैं। यहीं से भविष्य के इंजीनियरों और नवप्रवर्तकों की यात्रा शुरू होती है।',

    'Corridor':
        'यह कॉलेज कॉरिडोर विभागों और सुविधाओं को जोड़ने वाली जीवन रेखा है। '
        'छात्र और शिक्षक व्याख्यान और प्रयोगशालाओं के बीच यहाँ से गुजरते हैं।',

    'CSEDS_Gate':
        'आप CSEDS गेट पर खड़े हैं — कंप्यूटर विज्ञान और इंजीनियरिंग विभाग का मुख्य प्रवेश द्वार। '
        'कंप्यूटिंग उत्कृष्टता के केंद्र में आपका स्वागत है!',

    'CSEDS_Staff_Room':
        'यह CSEDS स्टाफ रूम है, जहाँ हमारे समर्पित शिक्षक व्याख्यान तैयार करते हैं और छात्रों का मार्गदर्शन करते हैं। '
        'यह विभाग का बौद्धिक तंत्रिका केंद्र है।',

    'Lab':
        'कंप्यूटर प्रयोगशाला में आपका स्वागत है! यह अत्याधुनिक लैब प्रोग्रामिंग और अनुसंधान के लिए आधुनिक वर्कस्टेशन से सुसज्जित है।',

    'PC':
        'ये हमारी लैब के पीसी हैं, जो प्रोग्रामिंग, डेटा विश्लेषण और रचनात्मक परियोजनाओं के लिए एक प्रवेश द्वार हैं।',

    'Shrimant_Dagdusheth_Halwai_Ganpati_Bappa':
        'गणपति बाप्पा मोरया, आप श्रीमंत दगडूशेठ हलवाई गणपति की उपस्थिति में हैं। '
        '19वीं शताब्दी में स्थापित, यह पुणे के सबसे प्रतिष्ठित मंदिरों में से एक है।',

    'Taj_Mahal':
        'दुनिया के सात अजूबों में से एक, शानदार ताजमहल में आपका स्वागत है। '
        '1632 में सम्राट शाहजहाँ द्वारा मुमताज महल की याद में बनाया गया, यह मुगल वास्तुकला का एक उत्कृष्ट नमूना है।',

    'Gate Way of India':
        'मुंबई के सबसे प्रतिष्ठित मील के पत्थर, गेटवे ऑफ इंडिया में आपका स्वागत है। '
        '1924 में निर्मित, यह अरब सागर पर अपोलो बंदर में स्थित है।',

    'Taj Hotel':
        'ताज महल पैलेस होटल, 1903 में निर्मित, मुंबई का सबसे प्रतिष्ठित लक्जरी होटल है, जहाँ से गेटवे ऑफ इंडिया दिखता है।',

    'Taxi':
        'मुंबई की प्रतिष्ठित काली-पीली टैक्सी शहर के तेज-तर्रार जीवन का प्रतीक रही है।',

    'Boat':
        'आप मुंबई के पास पानी पर एक नाव देख रहे हैं। यह गेटवे ऑफ इंडिया को एलीफेंटा गुफाओं से जोड़ती है।',
  };

  // �📍 Real-world GPS coordinates — keys must match EXACT YOLO class names
  static const Map<String, Map<String, double>> _classCoordinates = {
    'Shrimant_Dagdusheth_Halwai_Ganpati_Bappa': {'lat': 18.5165, 'lng': 73.8565},
    'Taj_Mahal':          {'lat': 27.1751, 'lng': 78.0421},
    'Gate Way of India':  {'lat': 18.9220, 'lng': 72.8347},
    'Taj Hotel':          {'lat': 18.9217, 'lng': 72.8332},
    'Taxi':               {'lat': 18.9220, 'lng': 72.8347}, // Mumbai area
    'Boat':               {'lat': 18.9220, 'lng': 72.8347}, // Mumbai harbour
    // College campus (DJ Sanghvi)
    'Achievement':        {'lat': 19.1076, 'lng': 72.8375},
    'Benches':            {'lat': 19.1076, 'lng': 72.8375},
    'Classroom':          {'lat': 19.1076, 'lng': 72.8375},
    'Corridor':           {'lat': 19.1076, 'lng': 72.8375},
    'CSEDS_Gate':         {'lat': 19.1076, 'lng': 72.8375},
    'CSEDS_Staff_Room':   {'lat': 19.1076, 'lng': 72.8375},
    'Lab':                {'lat': 19.1076, 'lng': 72.8375},
    'PC':                 {'lat': 19.1076, 'lng': 72.8375},
  };

  /// 🎯 Get instant hardcoded context for a detected YOLO class.
  /// Returns null if the class is not in our knowledge map.
  String? getContextForClass(String detectedClass, {String language = 'en'}) {
    final map = (language == 'hi') ? _classKnowledgeHindi : _classKnowledge;
    
    // Normalize: try exact match first, then case-insensitive
    String? text = map[detectedClass];
    if (text == null) {
      final key = map.keys.firstWhere(
        (k) => k.toLowerCase() == detectedClass.toLowerCase(),
        orElse: () => '',
      );
      text = key.isNotEmpty ? map[key] : null;
    }
    return text;
  }

  /// 📍 Get GPS coordinates for a detected YOLO class.
  /// Returns null if no coordinates are registered for this class.
  Map<String, double>? getCoordinatesForClass(String detectedClass) {
    Map<String, double>? coords = _classCoordinates[detectedClass];
    if (coords == null) {
      final key = _classCoordinates.keys.firstWhere(
        (k) => k.toLowerCase() == detectedClass.toLowerCase(),
        orElse: () => '',
      );
      coords = key.isNotEmpty ? _classCoordinates[key] : null;
    }
    return coords;
  }

  /// 📍 Set current location context (called when a landmark is detected)
  void setLocationContext(String landmarkName, double lat, double lng) {
    _currentLandmarkName = landmarkName;
    _currentLat = lat;
    _currentLng = lng;
    print('📍 Location context set: $landmarkName ($lat, $lng)');
  }

  // Initialize RAG service
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    await _loadKnowledgeFromJSON();
    await _loadUserMemory();
    await _loadConversationHistory(); // 💾 Load persisted conversation history
    _isInitialized = true;
    print('✅ Tourist Guide initialized');
  }

  // Load knowledge base from JSON files
  Future<void> _loadKnowledgeFromJSON() async {
    try {
      final monumentsJson = await rootBundle.loadString('assets/knowledge/monuments.json');
      final monumentsData = jsonDecode(monumentsJson);
      _knowledgeBase['monuments'] = List<Map<String, dynamic>>.from(
        monumentsData['monuments'].map((m) => Map<String, dynamic>.from(m))
      );
      
      final collegesJson = await rootBundle.loadString('assets/knowledge/colleges.json');
      final collegesData = jsonDecode(collegesJson);
      _knowledgeBase['colleges'] = List<Map<String, dynamic>>.from(
        collegesData['colleges'].map((c) => Map<String, dynamic>.from(c))
      );
      
      print('📚 Loaded ${_knowledgeBase['monuments']?.length ?? 0} monuments');
      print('📚 Loaded ${_knowledgeBase['colleges']?.length ?? 0} colleges');
    } catch (e) {
      print('⚠️ Error loading knowledge: $e');
      _knowledgeBase['monuments'] = [];
      _knowledgeBase['colleges'] = [];
    }
  }

  // Load user memory
  Future<void> _loadUserMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefsJson = prefs.getString('user_preferences');
      if (prefsJson != null) {
        final decoded = jsonDecode(prefsJson);
        _userMemory['preferences'] = Map<String, int>.from(decoded);
      }
      
      final queries = prefs.getStringList('past_queries') ?? [];
      _userMemory['pastQueries'] = queries.take(20).toList();
      
      final visited = prefs.getStringList('visited_topics') ?? [];
      _userMemory['visitedTopics'] = visited;
      
      print('🧠 Loaded user memory');
    } catch (e) {
      print('⚠️ Error loading user memory: $e');
    }
  }

  // Save user memory
  Future<void> _saveUserMemory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_preferences', jsonEncode(_userMemory['preferences']));
      await prefs.setStringList('past_queries', List<String>.from(_userMemory['pastQueries']));
      await prefs.setStringList('visited_topics', List<String>.from(_userMemory['visitedTopics']));
      print('💾 Saved user memory');
    } catch (e) {
      print('⚠️ Error saving user memory: $e');
    }
  }

  // ─── 💾 Persistent Conversation History ──────────────────────────────────

  /// Load conversation history from SharedPreferences (cross-session memory)
  Future<void> _loadConversationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('conversation_history');
      if (historyJson != null) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _conversationHistory.clear();
        for (final item in decoded) {
          _conversationHistory.add(Map<String, String>.from(item));
        }
        // Keep only the last 20 turns from previous sessions
        while (_conversationHistory.length > 20) {
          _conversationHistory.removeAt(0);
        }
        print('💬 Loaded ${_conversationHistory.length} turns from previous session');
      }
    } catch (e) {
      print('⚠️ Error loading conversation history: $e');
    }
  }

  /// Save conversation history to SharedPreferences
  Future<void> _saveConversationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Store last 20 turns only
      final toSave = _conversationHistory.length > 20
          ? _conversationHistory.sublist(_conversationHistory.length - 20)
          : List<Map<String, String>>.from(_conversationHistory);
      await prefs.setString('conversation_history', jsonEncode(toSave));
    } catch (e) {
      print('⚠️ Error saving conversation history: $e');
    }
  }

  // 💬 Add to conversation history (in-memory + persist)
  void _addToConversation(String role, String message) {
    _conversationHistory.add({'role': role, 'message': message});
    if (_conversationHistory.length > 20) { // Keep last 20 turns (10 exchanges)
      _conversationHistory.removeAt(0);
    }
    // Persist asynchronously (don't await — non-blocking)
    _saveConversationHistory();
  }

  // 💬 Get conversation context string for prompts
  String _getConversationContext() {
    if (_conversationHistory.isEmpty) return '';
    
    final buffer = StringBuffer('Recent conversation:\n');
    // Use last 6 turns (3 exchanges) for prompt context
    final recent = _conversationHistory.length > 6
        ? _conversationHistory.sublist(_conversationHistory.length - 6)
        : _conversationHistory;
    for (final turn in recent) {
      buffer.writeln('${turn['role']}: ${turn['message']}');
    }
    return buffer.toString();
  }

  // ─── 🗺️ Nearby Places Intent Detection ──────────────────────────────────

  /// Detect if the user's query is asking about nearby places/attractions
  bool _isNearbyIntent(String query) {
    final q = query.toLowerCase();
    final nearbyKeywords = [
      'nearby', 'near here', 'close by', 'around here', 'around me',
      'attraction', 'attractions', 'places to visit', 'things to do',
      'restaurant', 'restaurants', 'eat', 'food', 'dining', 'where to eat',
      'hotel', 'hotels', 'stay', 'accommodation', 'lodge',
      'what\'s around', 'what is around', 'explore', 'visit',
      'आसपास', 'नजदीक', 'खाना', 'होटल', // Hindi keywords
    ];
    return nearbyKeywords.any((kw) => q.contains(kw));
  }

  /// Detect if user is asking about the thing currently visible on camera
  bool _isThisPlaceQuery(String query) {
    final q = query.toLowerCase();
    final thisKeywords = [
      'what is this', 'what\'s this', 'whats this',
      'what am i looking at', 'what are we looking at',
      'tell me about this', 'explain this', 'describe this',
      'what place is this', 'which place is this', 'what building is this',
      'what monument is this', 'what temple is this', 'what landmark is this',
      'where am i', 'what is here', 'what\'s here',
      'ye kya hai', 'yeh kya hai', 'यह क्या है', 'ये क्या है', // Hindi
      'ithe kay aahe', // Marathi
    ];
    return thisKeywords.any((kw) => q.contains(kw));
  }

  /// Detect the category of nearby places being asked about
  String _detectNearbyCategory(String query) {
    final q = query.toLowerCase();
    if (q.contains('restaurant') || q.contains('eat') || q.contains('food') ||
        q.contains('dining') || q.contains('खाना') || q.contains('cafe')) {
      return 'restaurant';
    }
    if (q.contains('hotel') || q.contains('stay') || q.contains('accommodation') ||
        q.contains('lodge') || q.contains('hostel') || q.contains('होटल')) {
      return 'hotel';
    }
    return 'attraction'; // default
  }

  /// Fetch nearby places and build a voice-friendly description
  Future<String> _buildNearbyPlacesContext(String category) async {
    if (_currentLat == null || _currentLng == null) {
      return '';
    }

    try {
      List<PlaceResult> places;
      switch (category) {
        case 'restaurant':
          places = await _nearbyService.fetchRestaurants(
            lat: _currentLat!,
            lng: _currentLng!,
          );
          break;
        case 'hotel':
          places = await _nearbyService.fetchHotels(
            lat: _currentLat!,
            lng: _currentLng!,
          );
          break;
        default:
          places = await _nearbyService.fetchAttractions(
            lat: _currentLat!,
            lng: _currentLng!,
          );
      }

      if (places.isEmpty) return '';

      // Take top 5 places for voice context
      final top = places.take(5).toList();
      final buffer = StringBuffer();
      buffer.writeln('Nearby ${category}s near ${_currentLandmarkName ?? "your location"}:');
      for (int i = 0; i < top.length; i++) {
        final p = top[i];
        buffer.write('${i + 1}. ${p.name}');
        if (p.cuisine != null) buffer.write(' (${p.cuisine})');
        if (p.openingHours != null) buffer.write(' — open: ${p.openingHours}');
        buffer.writeln();
      }
      return buffer.toString();
    } catch (e) {
      print('⚠️ Error fetching nearby places for voice: $e');
      return '';
    }
  }

  // 🎯 Smart context retrieval
  Future<List<Map<String, dynamic>>> retrieveRelevantContext(String query) async {
    if (!_isInitialized) await initialize();

    final queryLower = query.toLowerCase();
    final matches = <Map<String, dynamic>>[];

    for (final category in _knowledgeBase.keys) {
      for (final entry in _knowledgeBase[category]!) {
        final keywords = List<String>.from(entry['keywords'] ?? []);
        final name = (entry['name'] as String).toLowerCase();
        
        bool isMatch = false;
        double similarity = 0.0;
        
        if (queryLower.contains(name) || name.contains(queryLower.split(' ').first)) {
          isMatch = true;
          similarity = 0.9;
        }
        
        if (!isMatch) {
          for (final keyword in keywords) {
            if (queryLower.contains(keyword.toLowerCase())) {
              isMatch = true;
              similarity = 0.7;
              break;
            }
          }
        }
        
        final prefs = _userMemory['preferences'] as Map<String, int>;
        final interestCount = prefs[entry['name']] ?? 0;
        if (interestCount > 0) {
          similarity += (interestCount * 0.05).clamp(0.0, 0.2);
        }
        
        if (isMatch) {
          matches.add({...entry, 'similarity': similarity});
        }
      }
    }

    matches.sort((a, b) => (b['similarity'] as double).compareTo(a['similarity'] as double));
    final topMatches = matches.take(3).toList();
    
    if (topMatches.isNotEmpty) {
      await _updateUserPreferences(query, topMatches);
    }
    
    return topMatches;
  }

  // Update user preferences
  Future<void> _updateUserPreferences(String query, List<Map<String, dynamic>> matches) async {
    final queries = _userMemory['pastQueries'] as List<String>;
    queries.insert(0, query);
    if (queries.length > 20) queries.removeLast();
    
    final prefs = _userMemory['preferences'] as Map<String, int>;
    final visited = _userMemory['visitedTopics'] as List<String>;
    
    for (final match in matches) {
      final topic = match['name'] as String;
      prefs[topic] = (prefs[topic] ?? 0) + 1;
      if (!visited.contains(topic)) {
        visited.add(topic);
      }
    }
    
    await _saveUserMemory();
  }

  // 🎬 Generate proactive scene-triggered dialogue
  Future<String> generateSceneDialogue(String detectedObject, String language) async {
    if (!_isInitialized) await initialize();
    
    _lastDetectedObject = detectedObject;
    
    // Auto-set location context from class coordinates
    final coords = getCoordinatesForClass(detectedObject);
    if (coords != null) {
      setLocationContext(detectedObject.replaceAll('_', ' '), coords['lat']!, coords['lng']!);
    }

    // Find relevant knowledge about detected object
    final context = await retrieveRelevantContext(detectedObject);
    
    final prompt = '''You are a professional tour guide who just noticed something interesting.

Detected Object/Scene: $detectedObject

${context.isNotEmpty ? 'Information about this:\n${_buildContextString(context, TouristMode.storytelling)}' : ''}

IMPORTANT RULES:
- Do NOT start with filler words like "ah", "oh", "well", "so"
- Start directly with the information
- Your response MUST be between 20 and 50 words. Not less, not more.
- Write in complete sentences only. Never cut off mid-sentence.
- Be professional and engaging

${language == 'hi' ? 'Respond in Hindi.' : language == 'mr' ? 'Respond in Marathi.' : language == 'gu' ? 'Respond in Gujarati.' : 'Respond in English.'}

Good example: "I see we're looking at the Taj Mahal. This magnificent monument was built by Emperor Shah Jahan in memory of his wife. The white marble changes color throughout the day. Would you like to know more about its history?"
Bad example: "Ah, my dear friend, oh what a sight!"''';

    final response = await _callGeminiAPI(prompt);
    _addToConversation('Guide', response);
    return response;
  }

  // 💡 Generate proactive suggestions
  Future<String> generateProactiveSuggestion(String language) async {
    if (!_isInitialized) await initialize();
    
    final visited = _userMemory['visitedTopics'] as List<String>;
    final prefs = _userMemory['preferences'] as Map<String, int>;
    
    // Find unvisited topics
    final allTopics = <String>[];
    for (final category in _knowledgeBase.values) {
      for (final entry in category) {
        allTopics.add(entry['name'] as String);
      }
    }
    
    final unvisited = allTopics.where((t) => !visited.contains(t)).toList();
    
    final prompt = '''You are a professional tour guide making a helpful suggestion.

Visited topics: ${visited.join(', ')}
Available topics: ${unvisited.take(3).join(', ')}

IMPORTANT: Do NOT use filler words. Your response MUST be between 20 and 50 words. Write in complete sentences only.
${language == 'hi' ? 'Respond in Hindi.' : language == 'mr' ? 'Respond in Marathi.' : language == 'gu' ? 'Respond in Gujarati.' : 'Respond in English.'}

Example: "Since you enjoyed the Taj Mahal, you might love the Red Fort. It's another stunning Mughal masterpiece in Delhi. Shall we explore it?"''';

    return await _callGeminiAPI(prompt);
  }

  // 🗣️ Generate conversational response with memory + nearby places awareness
  // [detectedObject] — the landmark currently visible on camera (optional)
  Future<String> generateConversationalResponse(
    String query,
    String language,
    TouristMode mode, {
    String? detectedObject,
  }) async {
    if (!_isInitialized) await initialize();

    // Add user query to conversation
    _addToConversation('Tourist', query);
    
    // ─── 📍 NEARBY PLACES INTENT ─────────────────────────────────────────
    if (_isNearbyIntent(query)) {
      final category = _detectNearbyCategory(query);
      print('🗺️ Nearby intent detected — category: $category');

      // Fetch nearby places
      final nearbyContext = await _buildNearbyPlacesContext(category);

      String nearbyPrompt;
      if (nearbyContext.isNotEmpty) {
        nearbyPrompt = '''You are a friendly tour guide. The tourist is asking about nearby $category places.

$nearbyContext

Tourist asked: "$query"

IMPORTANT RULES:
- Mention 2-3 specific places by name from the list above
- Keep the response between 40 and 70 words
- Be natural and conversational
- Recommend the best ones warmly
- Do NOT start with filler words
- Write in complete sentences only

${language == 'hi' ? 'Respond in Hindi.' : language == 'mr' ? 'Respond in Marathi.' : language == 'gu' ? 'Respond in Gujarati.' : 'Respond in English.'}

Example: "Near the Taj Mahal, you should definitely try Peshawri at ITC Mughal for Mughal cuisine. For something casual, Joney\'s Place is very popular with tourists. Both are within walking distance!"''';
      } else {
        // No location context yet — give generic helpful advice
        nearbyPrompt = '''You are a friendly tour guide. The tourist is asking about nearby $category places but you don't have their exact location yet.

Tourist asked: "$query"

Tell them to use the "Explore Nearby" button visible on screen to see a full map of nearby places. Keep it under 40 words, be warm and helpful.
${language == 'hi' ? 'Respond in Hindi.' : language == 'mr' ? 'Respond in Marathi.' : language == 'gu' ? 'Respond in Gujarati.' : 'Respond in English.'}''';
      }

      final response = await _callGeminiAPI(nearbyPrompt);
      _addToConversation('Guide', response);
      return response;
    }

    // ─── 🧠 MEMORY RECALL ────────────────────────────────────────────────
    // Check if asking about past questions
    if (query.toLowerCase().contains('earlier') || 
        query.toLowerCase().contains('before') ||
        query.toLowerCase().contains('previous') ||
        query.toLowerCase().contains('last question') ||
        query.toLowerCase().contains('पहले') ||
        query.toLowerCase().contains('पहले से')) {
      final pastQueries = _userMemory['pastQueries'] as List<String>;
      if (pastQueries.isNotEmpty) {
        final recent = pastQueries.take(3).join(', ');
        final response = language == 'hi' 
            ? 'आपने पहले पूछा था: $recent'
            : 'You previously asked about: $recent';
        _addToConversation('Guide', response);
        return response;
      }
    }
    
    // ─── 🎯 "WHAT IS THIS?" DETECTED-PLACE AWARE INTENT ─────────────────
    // If user asks about the current thing visible on camera, use detected object
    final effectiveObject = detectedObject ?? _lastDetectedObject;
    final isThisQuery = _isThisPlaceQuery(query);

    if (isThisQuery && effectiveObject != null) {
      print('🔍 "What is this?" intent with detected: $effectiveObject');
      // Get hardcoded knowledge first (instant, no API)
      final hardcoded = getContextForClass(effectiveObject, language: language);
      // Also check JSON knowledge base
      final jsonContext = await retrieveRelevantContext(effectiveObject);
      final jsonInfo = jsonContext.isNotEmpty ? _buildContextString(jsonContext, mode) : '';

      final landmark = effectiveObject.replaceAll('_', ' ');
      final detectedPrompt = '''You are a professional tour guide. The tourist is pointing their camera at "$landmark" and asking: "$query"

${hardcoded != null ? 'Key facts about $landmark:\n$hardcoded' : ''}
${jsonInfo.isNotEmpty ? '\nAdditional context:\n$jsonInfo' : ''}

IMPORTANT RULES:
- Tell them specifically about $landmark — use its real name
- Do NOT say "this" vaguely — name the place clearly
- Your response MUST be between 30 and 60 words
- Write in complete sentences only
- Be engaging and informative

${language == 'hi' ? 'Respond in Hindi.' : language == 'mr' ? 'Respond in Marathi.' : language == 'gu' ? 'Respond in Gujarati.' : 'Respond in English.'}

Example: "You are looking at the Gateway of India, Mumbai\'s most iconic arch monument built in 1924. It stands at the edge of the Arabian Sea and was the last exit point of the British from India. Would you like to know more?"''';

      final response = await _callGeminiAPI(detectedPrompt);
      _addToConversation('Guide', response);
      return response;
    }

    // Get relevant context
    final context = await retrieveRelevantContext(query);
    
    // Build conversational prompt with persistent memory
    final conversationContext = _getConversationContext();
    final contextInfo = context.isNotEmpty ? _buildContextString(context, mode) : '';

    // Build location + detected-object note for the prompt — computed cleanly
    String locationNote;
    final detectedName = effectiveObject?.replaceAll('_', ' ');
    if (_currentLandmarkName != null && detectedName != null) {
      locationNote = 'Current location: $_currentLandmarkName (detected: $detectedName)';
    } else if (_currentLandmarkName != null) {
      locationNote = 'Current location: $_currentLandmarkName';
    } else if (detectedName != null) {
      locationNote = 'Currently detected on camera: $detectedName';
    } else {
      locationNote = '';
    }
    
    final prompt = '''You are a professional tour guide having a natural conversation.

${conversationContext.isNotEmpty ? conversationContext : ''}

${contextInfo.isNotEmpty ? 'Information available:\n$contextInfo' : ''}

${locationNote.isNotEmpty ? locationNote : ''}

Tourist: $query

IMPORTANT RULES:
- Do NOT start with filler words like "ah", "oh", "well", "so"
- Start directly with the answer
- Your response MUST be between 20 and 50 words total. Not less, not more.
- Write in complete sentences only. Never cut off mid-sentence.
- If a location or detected landmark is mentioned above, use that context to make your answer specific.
- Be informative and natural within that word limit.
- ${_getModeInstructions(mode)}

${language == 'hi' ? 'Respond in Hindi.' : language == 'mr' ? 'Respond in Marathi.' : language == 'gu' ? 'Respond in Gujarati.' : 'Respond in English.'}

Remember to:
- Reference previous conversation if relevant
- Suggest related topics naturally
- Guide the flow ("Now let's move to...", "You might also enjoy...")
- Be conversational, not just Q&A''';

    final response = await _callGeminiAPI(prompt);
    _addToConversation('Guide', response);
    return response;
  }

  // Build context string
  String _buildContextString(List<Map<String, dynamic>> context, TouristMode mode) {
    final buffer = StringBuffer();
    
    for (final item in context.take(2)) {
      buffer.writeln('📍 ${item['name']} (${item['location']})');
      
      if (item['facts'] != null) {
        final facts = List<String>.from(item['facts']);
        for (final fact in facts.take(3)) {
          buffer.writeln('  • $fact');
        }
      }
      
      if (item['stories'] != null) {
        final stories = item['stories'] as Map;
        String? story;
        
        switch (mode) {
          case TouristMode.excited:
            story = stories['romantic'] ?? stories['historical'];
            break;
          case TouristMode.calm:
            story = stories['architectural'] ?? stories['historical'];
            break;
          case TouristMode.storytelling:
            story = stories['historical'] ?? stories['romantic'];
            break;
        }
        
        if (story != null) {
          buffer.writeln('Story: $story');
        }
      }
      buffer.writeln();
    }
    
    return buffer.toString();
  }

  // Get mode instructions
  String _getModeInstructions(TouristMode mode) {
    switch (mode) {
      case TouristMode.excited:
        return 'Be enthusiastic and energetic, but professional. Express genuine interest.';
      case TouristMode.calm:
        return 'Be peaceful and informative. Use a calm, measured tone.';
      case TouristMode.storytelling:
        return 'Tell engaging stories in a narrative style. Be descriptive and professional.';
    }
  }

  // Call Gemini API
  Future<String> _callGeminiAPI(String prompt) async {
    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'role': 'user', 'parts': [{'text': prompt}]}],
          'generationConfig': {
            'temperature': 0.7,
            'maxOutputTokens': 800,
            'topP': 0.9,
            'topK': 40,
          }
        }),
      );

      print('📡 Gemini API Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['candidates'] != null && data['candidates'].isNotEmpty) {
          final candidate = data['candidates'][0];
          final finishReason = candidate['finishReason'] ?? 'UNKNOWN';
          print('🏁 Gemini finishReason: $finishReason');
          final reply = candidate['content']?['parts']?[0]?['text'];
          if (reply != null && reply.toString().trim().isNotEmpty) {
            print('📝 Gemini full reply (${reply.toString().split(' ').length} words): $reply');
            return reply.toString().trim();
          }
        }
        return 'I apologize, but I couldn\'t generate a proper response. Could you rephrase that?';
      } else if (response.statusCode == 429) {
        return 'Please wait a moment before asking again.';
      } else {
        return 'Something went wrong. Please try again.';
      }
    } catch (e) {
      print('⚠️ API error: $e');
      return 'Sorry, I\'m having trouble connecting. Please try again.';
    }
  }
  
  // Get last detected object
  String? getLastDetectedObject() => _lastDetectedObject;
  
  // Clear conversation history (in-memory + persisted)
  Future<void> clearConversation() async {
    _conversationHistory.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('conversation_history');
    print('🗑️ Conversation history cleared');
  }

  // ─── Getters for diagnostics ─────────────────────────────────────────────
  int get conversationTurnCount => _conversationHistory.length;
  String? get currentLandmarkName => _currentLandmarkName;
}
