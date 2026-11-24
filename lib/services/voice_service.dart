import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart'; // backup TTS
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter/foundation.dart';

class VoiceService {
  // 🎙️ Speech & Audio
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _player = AudioPlayer();
  final FlutterTts _fallbackTts = FlutterTts();
  StreamSubscription? _playerCompleteSub; // track to avoid listener accumulation

  // 🔑 API Keys
  final String geminiApiKey = "AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA";
  final String elevenLabsApiKey = const String.fromEnvironment('ELEVENLABS_API_KEY', defaultValue: "YOUR_ELEVENLABS_API_KEY"); // Put your key here or pass via --dart-define 
  final String elevenVoiceId = "JBFqnCBsd6RMkjVDRZzb";
  final String geminiModel = "gemini-2.5-flash";

  // ✅ Detect if text is Hindi
  bool _isHindi(String text) {
    final hindiRegex = RegExp(r'[\u0900-\u097F]+');
    return hindiRegex.hasMatch(text);
  }

  // 🎧 ElevenLabs speech
  Future<void> speakWithElevenLabs(
    String text, {
    double rate = 1.0,
    bool isHindi = false,
    VoidCallback? onStart,
    VoidCallback? onEnd,
  }) async {
    if (elevenLabsApiKey.isEmpty || elevenLabsApiKey == "YOUR_ELEVENLABS_API_KEY") {
      onStart?.call();
      await _fallbackTts.speak(text);
      onEnd?.call();
      return;
    }

    final voiceId = elevenVoiceId;
    final uri = Uri.parse("https://api.elevenlabs.io/v1/text-to-speech/$voiceId");

    final body = jsonEncode({
      "text": text,
      "model_id": "eleven_multilingual_v2",
      "voice_settings": {
        "stability": 0.40,
        "similarity_boost": 0.85,
        "style": rate.clamp(0.5, 1.5),
        "use_speaker_boost": true
      }
    });

    try {
      final response = await http.post(
        uri,
        headers: {
          "Accept": "audio/mpeg",
          "Content-Type": "application/json",
          "xi-api-key": elevenLabsApiKey,
        },
        body: body,
      );

      print('🔊 ElevenLabs status: ${response.statusCode}');
      print('🔊 ElevenLabs content-type: ${response.headers['content-type']}');

      if (response.statusCode == 200 &&
          (response.headers['content-type']?.contains('audio') ?? false)) {
        final dir = await getTemporaryDirectory();
        final file = File("${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3");
        await file.writeAsBytes(response.bodyBytes);
        print('🔊 Audio file written: ${response.bodyBytes.length} bytes → ${file.path}');

        // ✅ Standard mode (not lowLatency) is more reliable for onPlayerComplete on Android
        await _player.stop();
        await _player.setVolume(1.0);
        await _player.setSource(DeviceFileSource(file.path));

        final playCompleter = Completer<void>();
        _playerCompleteSub = _player.onPlayerComplete.listen((_) {
          print('🔊 Audio playback complete → onEnd fired');
          onEnd?.call();
          if (!playCompleter.isCompleted) playCompleter.complete();
        });

        onStart?.call();
        await _player.resume();
        print('🔊 AudioPlayer.resume() called');

        // Wait for completion with 90s safety timeout (landmarks can be long)
        await playCompleter.future.timeout(
          const Duration(seconds: 90),
          onTimeout: () {
            print('⚠️ Audio timeout — proceeding');
            if (!playCompleter.isCompleted) playCompleter.complete();
          },
        );
      } else {
        print("❌ ElevenLabs failed — status: ${response.statusCode}");
        print("❌ ElevenLabs body: ${response.body}");
        onStart?.call();
        final ttsCompleter = Completer<void>();
        _fallbackTts.setCompletionHandler(() {
          if (!ttsCompleter.isCompleted) ttsCompleter.complete();
        });
        await _fallbackTts.speak(text);
        await ttsCompleter.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            if (!ttsCompleter.isCompleted) ttsCompleter.complete();
          },
        );
        onEnd?.call();
      }
    } catch (e) {
      print("⚠️ ElevenLabs exception: $e");
      onStart?.call();
      final ttsCompleter = Completer<void>();
      _fallbackTts.setCompletionHandler(() {
        if (!ttsCompleter.isCompleted) ttsCompleter.complete();
      });
      await _fallbackTts.speak(text);
      await ttsCompleter.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {},
      );
      onEnd?.call();
    }
  }

  // 🎤 Long-duration speech recognition (Hindi + English)
  Future<String?> listenUserSpeech({
    Duration maxDuration = const Duration(seconds: 60),
    String initialLocale = "en-IN",
  }) async {
    bool available = await _speech.initialize(
      onError: (err) => print("⚠️ Speech error: $err"),
      onStatus: (status) => print("🎧 Status: $status"),
    );

    if (!available) {
      print("❌ Speech recognition unavailable");
      return null;
    }

    String finalResult = "";
    bool isListening = true;

    // Listen in English first
    await _speech.listen(
      listenFor: maxDuration,
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
      localeId: initialLocale,
      onResult: (result) {
        final text = result.recognizedWords.trim();
        if (text.isNotEmpty) {
          finalResult = text;
        }
      },
    );

    // Wait until listening finishes
    final start = DateTime.now();
    while (isListening && DateTime.now().difference(start) < maxDuration) {
      await Future.delayed(const Duration(milliseconds: 500));
      if (!_speech.isListening) {
        isListening = false;
      }
    }

    await _speech.stop();

    // If empty or Hindi detected → try Hindi mode
    if (finalResult.isEmpty || _isHindi(finalResult)) {
      print("🔁 Switching to Hindi recognition...");
      finalResult = "";
      await _speech.listen(
        listenFor: maxDuration,
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        localeId: "hi-IN",
        onResult: (result) {
          final text = result.recognizedWords.trim();
          if (text.isNotEmpty) {
            finalResult = text;
          }
        },
      );

      final start2 = DateTime.now();
      bool listeningHindi = true;
      while (listeningHindi && DateTime.now().difference(start2) < maxDuration) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!_speech.isListening) {
          listeningHindi = false;
        }
      }
      await _speech.stop();
    }

    print("🎙️ Final Speech Result: $finalResult");
    return finalResult.isNotEmpty ? finalResult : null;
  }

  // 🧠 Get Gemini reply (now optimized for RAG)
  Future<String> getGeminiReply(String query, {bool detailed = false}) async {
    try {
      final response = await http.post(
        Uri.parse(
            "https://generativelanguage.googleapis.com/v1beta/models/$geminiModel:generateContent?key=$geminiApiKey"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "contents": [
            {"role": "user", "parts": [{"text": query}]}
          ],
          "generationConfig": {
            "temperature": 0.7,
            "maxOutputTokens": detailed ? 500 : 200,
          }
        }),
      );

      final data = jsonDecode(response.body);
      final reply = data["candidates"]?[0]?["content"]?["parts"]?[0]?["text"];

      return reply ?? "Sorry, I couldn't generate a response.";
    } catch (e) {
      print("⚠️ Gemini API error: $e");
      return "Something went wrong. Please try again.";
    }
  }

  // 🎵 Intro audio — onEnd fires when playback fully completes
  Future<void> playIntroAudio({bool isHindi = false, VoidCallback? onStart, VoidCallback? onEnd}) async {
    final text = isHindi
        ? "नमस्ते! मैं आपकी पर्सनल टूर गाइड हूँ। अपने कैमरे को किसी भी ऐतिहासिक स्थल की ओर घुमाएँ — मैं उसके बारे में बताऊँगी। चलिए साथ मिलकर घूमते हैं!"
        : "Welcome! I'm your personal tour guide. Point your camera at any landmark — I’ll explain it. Let's explore together!";
    
    await speakWithElevenLabs(
      text,
      onStart: onStart,
      onEnd: onEnd,
      isHindi: isHindi,
    );
  }

  void dispose() {
    _player.dispose();
    _fallbackTts.stop();
  }
}
