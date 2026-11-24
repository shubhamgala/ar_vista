import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final apiKey = "AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA";
  
  print('🧪 Testing Gemini API...');
  
  try {
    final response = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'role': 'user',
            'parts': [{'text': 'Say hello in one word'}]
          }
        ],
      }),
    );

    print('Status: ${response.statusCode}');
    print('Response: ${response.body}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('✅ API is working!');
      print('Reply: ${data['candidates']?[0]?['content']?['parts']?[0]?['text']}');
    } else {
      print('❌ API Error');
    }
  } catch (e) {
    print('⚠️ Exception: $e');
  }
}
