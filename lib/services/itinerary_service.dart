import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/itinerary_model.dart';

class ItineraryService {
  final String _geminiApiKey = "AIzaSyAHZv4pyItl8ua9O4ZgpXoZB_CRL7y65UA";
  static const String _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  Future<GeneratedItinerary> generateItinerary({
    required String landmarkName,
    required ItineraryPreferences prefs,
    required List<PlaceResult> nearbyAttractions,
    required List<PlaceResult> nearbyRestaurants,
    required List<PlaceResult> nearbyHotels,
    List<PlaceResult> pinnedPlaces = const [],
    double landmarkLat = 0.0,
    double landmarkLng = 0.0,
  }) async {
    // Build rich restaurant catalogue sorted by veg preference
    final preferredRestaurants = nearbyRestaurants.where((p) {
      if (prefs.foodPreference == FoodPreference.veg) return p.isVeg != false;
      if (prefs.foodPreference == FoodPreference.nonVeg) return p.isVeg != true;
      return true;
    }).take(15).toList();

    final restaurantCatalogue = preferredRestaurants.map((p) {
      final tags = <String>[];
      if (p.isVeg == true) tags.add('🟢Veg');
      if (p.isVeg == false) tags.add('🔴Non-Veg');
      if (p.cuisine != null) tags.add(p.cuisine!);
      if (p.openingHours != null) tags.add(p.openingHours!);
      return '• ${p.name} [${tags.join(', ')}]';
    }).join('\n');

    final attractionCatalogue = nearbyAttractions.take(12)
        .map((p) => '• ${p.name}')
        .join('\n');

    final hotelCatalogue = nearbyHotels.take(8)
        .map((p) => '• ${p.name} (${_priceRange(prefs.stayPreference)})')
        .join('\n');

    // Pinned places the user explicitly selected from Nearby Places
    final pinnedSection = pinnedPlaces.isNotEmpty
        ? '\n=== MUST-INCLUDE STOPS (user personally selected these) ===\n'
            '${pinnedPlaces.map((p) => "• ${p.name} (${p.category})").join("\n")}\n'
            'You MUST include ALL of the above in the itinerary at appropriate time slots.'
        : '';

    // Build group/child context
    final groupCtx = _buildGroupContext(prefs);

    final prompt = '''You are an elite Indian travel planner creating a HYPER-DETAILED, SPECIFIC itinerary.

=== TRIP ===
BASE LANDMARK: $landmarkName
DAYS: ${prefs.days} (starting ${_fmtDate(prefs.startDate)})
TOTAL BUDGET: ₹${prefs.totalBudget} for ${prefs.groupSize} people
FOOD: ${prefs.foodLabel}
INTERESTS: ${prefs.interests.isEmpty ? 'General sightseeing' : prefs.interests.join(', ')}
ACCOMMODATION: ${prefs.stayLabel}$pinnedSection

=== GROUP ===
$groupCtx

=== SPECIFIC RESTAURANTS NEARBY — use ONLY these names ===
${restaurantCatalogue.isNotEmpty ? restaurantCatalogue : '• Local restaurants near $landmarkName'}

=== TOURIST SPOTS NEARBY — use ONLY these names ===
${attractionCatalogue.isNotEmpty ? attractionCatalogue : '• Tourist spots near $landmarkName'}

=== HOTELS NEARBY — pick ONE as primary recommendation ===
${hotelCatalogue.isNotEmpty ? hotelCatalogue : '• Hotels near $landmarkName'}

=== RULES (STRICTLY FOLLOW) ===
1. NEVER write "a local restaurant", "a nearby cafe", "generic hotel" — always a SPECIFIC name from above
2. For every food slot, pick the BEST matching restaurant from the list AND list 2-3 ALTERNATIVE restaurants from the list in "alternatives" array
3. For every attraction slot, describe EXACTLY what to do/see there (not just the name)
4. "description" field: 2-3 sentences — what makes this place special, what to experience, what to order (for food), famous highlights, kid/senior friendliness if relevant
5. "notes" field: 1 insider pro tip (e.g. best table, must-order dish, gate to enter from, photography spot, cash vs card)
6. "duration": realistic time including queue/travel (e.g. "1.5 hours", "45 min")
7. "alternatives": for food/stay slots list 2-3 other names from the catalogue; for attractions leave empty []
8. Budget ₹${prefs.totalBudget} is for ALL ${prefs.groupSize} people — multiply per-head costs
9. Return ONLY valid JSON, no text outside it, no markdown

=== JSON FORMAT ===
{
  "days": [
    {
      "label": "Day 1 — Tuesday, 11 Mar",
      "slots": [
        {
          "time": "8:30 AM",
          "activity": "Exact Place Name",
          "category": "attraction",
          "cost": 0,
          "duration": "2 hours",
          "description": "2-3 sentences: what makes this special, what to do/see/eat here, famous highlights",
          "notes": "💡 One killer insider tip",
          "alternatives": []
        },
        {
          "time": "1:00 PM",
          "activity": "Restaurant Name from list",
          "category": "food",
          "cost": 800,
          "duration": "1 hour",
          "description": "What this place is known for, signature dishes, ambience, suitability for group",
          "notes": "💡 Must-try dish or ordering tip",
          "alternatives": ["Alternative Restaurant 1", "Alternative Restaurant 2"]
        }
      ],
      "totalCost": 2400
    }
  ],
  "grandTotal": 6200,
  "stayRecommendation": "Hotel Name from list (₹X/night) — why it's perfect: proximity, amenities, child/senior friendly details"
}

Categories: attraction | food | stay | travel
Generate complete ${prefs.days}-day itinerary now:''';

    try {
      final response = await http
          .post(
            Uri.parse('$_geminiUrl?key=$_geminiApiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [{'role': 'user', 'parts': [{'text': prompt}]}],
              'generationConfig': {
                'temperature': 0.3,
                'maxOutputTokens': 8192,
                'topP': 0.85,
              }
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final raw = data['candidates']?[0]?['content']?['parts']?[0]?['text'] ?? '';
        print('🗓️ Gemini raw length: ${raw.length}');
        return _parse(raw, landmarkName, prefs, preferredRestaurants, nearbyHotels,
            pinnedPlaces, landmarkLat, landmarkLng);
      } else {
        print('⚠️ Gemini ${response.statusCode}');
        return _fallback(landmarkName, prefs, preferredRestaurants, nearbyHotels, landmarkLat, landmarkLng);
      }
    } catch (e) {
      print('⚠️ ItineraryService: $e');
      return _fallback(landmarkName, prefs, preferredRestaurants, nearbyHotels, landmarkLat, landmarkLng);
    }
  }

  GeneratedItinerary _parse(
    String raw,
    String landmark,
    ItineraryPreferences prefs,
    List<PlaceResult> restaurants,
    List<PlaceResult> hotels,
    List<PlaceResult> pinned,
    double lat,
    double lng,
  ) {
    try {
      String json = raw.trim()
          .replaceAll(RegExp(r'```json|```'), '')
          .trim();
      final s = json.indexOf('{');
      final e = json.lastIndexOf('}');
      if (s < 0 || e < 0) throw const FormatException('No JSON');
      json = json.substring(s, e + 1);

      final parsed = jsonDecode(json) as Map<String, dynamic>;
      final days = (parsed['days'] as List<dynamic>? ?? [])
          .map((d) => ItineraryDay.fromJson(Map<String, dynamic>.from(d)))
          .toList();

      // Attach lat/lng to slots that match a pinned place
      final enrichedDays = days.map((day) {
        final enrichedSlots = day.slots.map((slot) {
          final match = pinned.cast<PlaceResult?>().firstWhere(
            (p) => p!.name.toLowerCase() == slot.activity.toLowerCase(),
            orElse: () => null,
          );
          return match != null ? slot.copyWith(lat: match.lat, lng: match.lng) : slot;
        }).toList();
        return day.copyWithSlots(enrichedSlots);
      }).toList();

      return GeneratedItinerary(
        days: enrichedDays,
        grandTotal: _toInt(parsed['grandTotal']) == 0
            ? prefs.totalBudget
            : _toInt(parsed['grandTotal']),
        stayRecommendation: parsed['stayRecommendation'] ??
            (hotels.isNotEmpty
                ? '${hotels.first.name} — nearest quality stay'
                : 'Accommodation per ${prefs.stayLabel}'),
        landmarkName: landmark,
        preferences: prefs,
        lat: lat,
        lng: lng,
      );
    } catch (e) {
      print('⚠️ Parse error: $e');
      return _fallback(landmark, prefs, restaurants, hotels, lat, lng);
    }
  }

  GeneratedItinerary _fallback(
    String landmark,
    ItineraryPreferences prefs,
    List<PlaceResult> restaurants,
    List<PlaceResult> hotels,
    double lat,
    double lng,
  ) {
    final r1 = restaurants.isNotEmpty ? restaurants[0].name : 'a restaurant near $landmark';
    final r2 = restaurants.length > 1 ? restaurants[1].name : r1;
    final r3 = restaurants.length > 2 ? restaurants[2].name : r1;
    final hotel = hotels.isNotEmpty ? hotels[0].name : 'a hotel near $landmark';
    final alts = restaurants.skip(1).take(3).map((p) => p.name).toList();

    return GeneratedItinerary(
      days: List.generate(prefs.days, (i) => ItineraryDay(
        label: 'Day ${i + 1}',
        slots: [
          TimeSlot(time: '9:00 AM', activity: landmark, category: 'attraction',
            estimatedCost: 0, duration: '2 hours',
            description: 'Start your day at $landmark — the highlight of your trip. Explore at your own pace and soak in the history and atmosphere.',
            notes: '💡 Visit early morning before crowds arrive.',
            alternatives: []),
          TimeSlot(time: '12:30 PM', activity: r1, category: 'food',
            estimatedCost: 400 * prefs.groupSize, duration: '1 hour',
            description: 'A popular local eatery near $landmark. Great choice for a satisfying midday meal.',
            notes: '💡 Try the daily specials — usually freshest and best value.',
            alternatives: alts),
          TimeSlot(time: '3:00 PM', activity: 'Explore surroundings', category: 'attraction',
            estimatedCost: 150, duration: '2 hours',
            description: 'Walk through the streets and markets around $landmark. Discover local shops, street art, and hidden spots.',
            notes: '💡 Great for photography — golden hour light starts around 4:30 PM.',
            alternatives: []),
          TimeSlot(time: '6:00 PM', activity: 'Check-in at $hotel', category: 'stay',
            estimatedCost: prefs.totalBudget ~/ (prefs.days * 4), duration: '30 min',
            description: 'Your home base for the trip. Freshen up and rest before dinner.',
            notes: '💡 Request a room on higher floors for better views.',
            alternatives: hotels.skip(1).take(2).map((p) => p.name).toList()),
          TimeSlot(time: '8:00 PM', activity: r2, category: 'food',
            estimatedCost: 500 * prefs.groupSize, duration: '1.5 hours',
            description: 'Wind down the day with a relaxed dinner. $r2 is known for its evening ambience and local specialties.',
            notes: '💡 Book a table in advance on weekends.',
            alternatives: [r3, ...(alts.where((a) => a != r2).take(1))]),
        ],
        totalDayCost: prefs.totalBudget ~/ prefs.days,
      )),
      grandTotal: prefs.totalBudget,
      stayRecommendation: '$hotel — convenient location near $landmark, easy access to all day\'s activities',
      landmarkName: landmark,
      preferences: prefs,
      lat: lat,
      lng: lng,
    );
  }

  String _buildGroupContext(ItineraryPreferences p) {
    final lines = <String>['GROUP: ${p.groupSummary}'];
    if (p.hasChildren) {
      for (final g in p.childAgeGroups) {
        switch (g) {
          case 'toddler': lines.add('→ Toddlers: gardens, boat rides, open spaces; no long walks'); break;
          case 'kids':    lines.add('→ Kids (4–10): interactive museums, parks, child-friendly restaurants'); break;
          case 'teens':   lines.add('→ Teens: street food, photography, adventure spots, malls'); break;
        }
      }
    }
    if (p.hasSeniors) lines.add('→ Seniors: slow pace, afternoon rest 2–4 PM, accessible venues, dinner by 8 PM');
    return lines.join('\n');
  }

  String _priceRange(StayPreference p) {
    switch (p) {
      case StayPreference.budget:   return '₹500–₹1,500/night';
      case StayPreference.midRange: return '₹2,000–₹6,000/night';
      case StayPreference.luxury:   return '₹7,000+/night';
    }
  }

  String _fmtDate(DateTime dt) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    const d = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${d[dt.weekday - 1]}, ${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}
