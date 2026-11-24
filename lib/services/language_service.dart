import 'dart:convert';
import 'package:http/http.dart' as http;

class LanguageService {
  final String geminiApiKey = "AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA";

  // Detect language from text
  String detectLanguage(String text) {
    // Check for non-ASCII characters first
    final hasDevanagari = RegExp(r'[\u0900-\u097F]+').hasMatch(text);
    final hasGujarati = RegExp(r'[\u0A80-\u0AFF]+').hasMatch(text);
    
    // Gujarati detection (must check before Hindi as both use similar scripts)
    if (hasGujarati) {
      return 'gu';
    }
    
    // Hindi/Marathi detection (both use Devanagari script)
    if (hasDevanagari) {
      // Check for Marathi-specific words
      final marathiWords = ['आहे', 'कुठे', 'काय', 'कसे', 'कोण', 'का', 'नाही', 'मला', 'तुम्ही'];
      for (final word in marathiWords) {
        if (text.contains(word)) {
          print('🌍 Detected language: Marathi');
          return 'mr';
        }
      }
      // Default Devanagari to Hindi
      print('🌍 Detected language: Hindi');
      return 'hi';
    }
    
    // Check for common Romanized Hindi/Hinglish words
    final hindiRomanized = [
      'kya', 'kaise', 'kaisa', 'kahi', 'kahan', 'kyu', 'kab', 'aur', 
      'hai', 'hain', 'tha', 'thi', 'hoon', 'main', 'tum', 'aap', 
      'namaste', 'dhanyavad', 'theek', 'acha', 'bura', 'sahi', 'galat'
    ];
    
    final lowerText = text.toLowerCase();
    for (final word in hindiRomanized) {
      // Check for whole words to avoid false positives in English (e.g. 'tha' is not a word in English, but 'main' might be)
      // simplistic check: space + word + space, or start/end
      if (lowerText.contains(RegExp(r'\b' + word + r'\b'))) {
        print('🌍 Detected language: Hindi (Romanized)');
        return 'hi';
      }
    }
    
    // Default to English
    print('🌍 Detected language: English');
    return 'en';
  }

  // Get language name
  String getLanguageName(String code) {
    switch (code) {
      case 'hi':
        return 'Hindi';
      case 'mr':
        return 'Marathi';
      case 'gu':
        return 'Gujarati';
      case 'en':
      default:
        return 'English';
    }
  }

  // Translate text using Gemini API (better context than Google Translate)
  Future<String> translate(String text, String targetLang) async {
    if (targetLang == 'en') return text;

    final langMap = {
      'hi': 'Hindi',
      'mr': 'Marathi',
      'gu': 'Gujarati',
    };

    final targetLanguage = langMap[targetLang] ?? 'English';
    
    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {
                  'text': 'Translate the following text to $targetLanguage. Only provide the translation, nothing else.\n\nText: $text'
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translation = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        return translation?.trim() ?? text;
      }
    } catch (e) {
      print('Translation error: $e');
    }
    
    return text;
  }

  // Get greeting in user's language
  String getGreeting(String language) {
    switch (language) {
      case 'hi':
        return 'नमस्ते! मैं आपका वर्चुअल गाइड हूं।';
      case 'mr':
        return 'नमस्कार! मी तुमचा व्हर्च्युअल मार्गदर्शक आहे।';
      case 'gu':
        return 'નમસ્તે! હું તમારો વર્ચ્યુઅલ માર્ગદર્શક છું।';
      case 'en':
      default:
        return 'Hello! I\'m your virtual guide.';
    }
  }

  // Get common phrases in different languages
  Map<String, String> getPhrases(String language) {
    final phrases = {
      'en': {
        'listening': 'Listening...',
        'processing': 'Processing your question...',
        'error': 'Sorry, I couldn\'t understand that.',
        'noInfo': 'I don\'t have information about that.',
      },
      'hi': {
        'listening': 'सुन रहा हूं...',
        'processing': 'आपके प्रश्न को समझ रहा हूं...',
        'error': 'माफ़ कीजिए, मैं समझ नहीं पाया।',
        'noInfo': 'मुझे इस बारे में जानकारी नहीं है।',
      },
      'mr': {
        'listening': 'ऐकत आहे...',
        'processing': 'तुमचा प्रश्न समजत आहे...',
        'error': 'माफ करा, मला समजले नाही।',
        'noInfo': 'मला याबद्दल माहिती नाही।',
      },
      'gu': {
        'listening': 'સાંભળી રહ્યો છું...',
        'processing': 'તમારો પ્રશ્ન સમજી રહ્યો છું...',
        'error': 'માફ કરશો, હું સમજી શક્યો નહીં।',
        'noInfo': 'મને આ વિશે માહિતી નથી।',
      },
    };

    return phrases[language] ?? phrases['en']!;
  }
}
