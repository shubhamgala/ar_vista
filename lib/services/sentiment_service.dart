import 'dart:convert';
import 'package:http/http.dart' as http;

class SentimentService {
  final String geminiApiKey = "AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA";

  // Analyze sentiment of user query
  Future<String> analyzeSentiment(String text) async {
    // Quick keyword-based detection for common cases
    final lowerText = text.toLowerCase();
    
    // Positive indicators
    if (lowerText.contains(RegExp(r'\b(wow|amazing|great|awesome|excellent|love|wonderful)\b'))) {
      return 'positive';
    }
    
    // Negative indicators
    if (lowerText.contains(RegExp(r'\b(bad|terrible|hate|worst|disappointed|angry)\b'))) {
      return 'negative';
    }
    
    // Confused indicators
    if (lowerText.contains(RegExp(r'\b(confused|unclear|help|what|how)\b')) ||
        lowerText.contains("don't understand") ||
        text.contains('?')) {
      return 'confused';
    }

    // For more complex cases, use Gemini API
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
                  'text': '''Analyze the sentiment of this text and respond with ONLY ONE WORD: positive, negative, confused, or neutral.

Text: $text

Sentiment:'''
                }
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final sentiment = data['candidates']?[0]?['content']?['parts']?[0]?['text']?.trim().toLowerCase();
        
        if (sentiment != null && ['positive', 'negative', 'confused', 'neutral'].contains(sentiment)) {
          return sentiment;
        }
      }
    } catch (e) {
      print('Sentiment analysis error: $e');
    }

    return 'neutral';
  }

  // Get response tone based on sentiment
  String getResponseTone(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return 'enthusiastic and encouraging';
      case 'negative':
        return 'empathetic and helpful';
      case 'confused':
        return 'patient and clear, explaining step-by-step';
      case 'neutral':
      default:
        return 'professional and informative';
    }
  }

  // Get emoji based on sentiment
  String getSentimentEmoji(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return '😊';
      case 'negative':
        return '😔';
      case 'confused':
        return '🤔';
      case 'neutral':
      default:
        return '💬';
    }
  }

  // Adjust animation based on sentiment
  String getAnimationForSentiment(String sentiment) {
    switch (sentiment) {
      case 'positive':
        return 'waving'; // Enthusiastic gesture
      case 'negative':
        return 'talking'; // Calm, empathetic
      case 'confused':
        return 'pointing_front'; // Guiding gesture
      case 'neutral':
      default:
        return 'talking'; // Standard talking
    }
  }
}
