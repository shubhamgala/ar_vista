import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/itinerary_model.dart';

/// 🗺️ Fetches nearby places using OpenStreetMap Overpass API (free, no key)
class NearbyPlacesService {
  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';

  // In-memory cache: key = "lat,lng,type"
  final Map<String, List<PlaceResult>> _cache = {};

  /// Fetch nearby tourist attractions within [radiusMeters]
  Future<List<PlaceResult>> fetchAttractions({
    required double lat,
    required double lng,
    int radiusMeters = 2500,
  }) async {
    final cacheKey = '$lat,$lng,attraction';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    const query = '''
[out:json][timeout:20];
(
  node["tourism"~"attraction|museum|artwork|viewpoint|theme_park"](around:RADIUS,LAT,LNG);
  way["tourism"~"attraction|museum|artwork|viewpoint|theme_park"](around:RADIUS,LAT,LNG);
  node["historic"~"monument|castle|ruins|memorial"](around:RADIUS,LAT,LNG);
);
out center 20;
''';
    return _fetchAndCache(
        cacheKey, query, lat, lng, radiusMeters, 'attraction');
  }

  /// Fetch nearby restaurants, optionally filtered by food type
  Future<List<PlaceResult>> fetchRestaurants({
    required double lat,
    required double lng,
    FoodPreference foodPref = FoodPreference.both,
    int radiusMeters = 2000,
  }) async {
    final cacheKey = '$lat,$lng,restaurant_${foodPref.name}';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    String vegFilter = '';
    if (foodPref == FoodPreference.veg) {
      vegFilter = '["diet:vegetarian"="yes"]';
    }

    final query = '''
[out:json][timeout:20];
(
  node["amenity"="restaurant"$vegFilter](around:RADIUS,LAT,LNG);
  node["amenity"="cafe"](around:RADIUS,LAT,LNG);
  node["amenity"="fast_food"](around:RADIUS,LAT,LNG);
);
out center 25;
''';
    return _fetchAndCache(
        cacheKey, query, lat, lng, radiusMeters, 'restaurant');
  }

  /// Fetch nearby hotels / lodging
  Future<List<PlaceResult>> fetchHotels({
    required double lat,
    required double lng,
    int radiusMeters = 3000,
  }) async {
    final cacheKey = '$lat,$lng,hotel';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey]!;

    const query = '''
[out:json][timeout:20];
(
  node["tourism"~"hotel|hostel|guest_house|motel|resort"](around:RADIUS,LAT,LNG);
  way["tourism"~"hotel|hostel|guest_house|motel|resort"](around:RADIUS,LAT,LNG);
);
out center 20;
''';
    return _fetchAndCache(cacheKey, query, lat, lng, radiusMeters, 'hotel');
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  Future<List<PlaceResult>> _fetchAndCache(
    String cacheKey,
    String queryTemplate,
    double lat,
    double lng,
    int radius,
    String category,
  ) async {
    final query = queryTemplate
        .replaceAll('LAT', lat.toStringAsFixed(6))
        .replaceAll('LNG', lng.toStringAsFixed(6))
        .replaceAll('RADIUS', radius.toString());

    try {
      final response = await http.post(
        Uri.parse(_overpassUrl),
        body: query,
      ).timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        print('⚠️ Overpass API error: ${response.statusCode}');
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List<dynamic>? ?? [];

      final results = <PlaceResult>[];
      for (final el in elements) {
        final tags = el['tags'] as Map<String, dynamic>? ?? {};
        final name = tags['name'] ?? tags['name:en'] ?? '';
        if (name.isEmpty) continue;

        double? elLat, elLng;
        if (el['type'] == 'node') {
          elLat = (el['lat'] as num?)?.toDouble();
          elLng = (el['lon'] as num?)?.toDouble();
        } else if (el['center'] != null) {
          elLat = (el['center']['lat'] as num?)?.toDouble();
          elLng = (el['center']['lon'] as num?)?.toDouble();
        }
        if (elLat == null || elLng == null) continue;

        // Veg detection heuristic based on tags
        bool? isVeg;
        final dietVeg = tags['diet:vegetarian'];
        final dietMeat = tags['diet:meat'];
        if (dietVeg == 'yes' || dietVeg == 'only') {
          isVeg = true;
        } else if (dietMeat == 'yes') {
          isVeg = false;
        }

        results.add(PlaceResult(
          name: name,
          lat: elLat,
          lng: elLng,
          category: category,
          cuisine: tags['cuisine'],
          isVeg: isVeg,
          openingHours: tags['opening_hours'],
          phone: tags['phone'] ?? tags['contact:phone'],
          website: tags['website'] ?? tags['contact:website'],
        ));
      }

      // Deduplicate by name
      final seen = <String>{};
      final unique = results
          .where((p) => seen.add(p.name.toLowerCase()))
          .toList();

      _cache[cacheKey] = unique;
      print('📍 ${category.toUpperCase()}: fetched ${unique.length} results');
      return unique;
    } catch (e) {
      print('⚠️ NearbyPlacesService error: $e');
      return [];
    }
  }

  void clearCache() => _cache.clear();
}
