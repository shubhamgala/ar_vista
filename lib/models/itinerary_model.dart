// 📦 Data models for itinerary generation

enum FoodPreference { veg, nonVeg, both }
enum StayPreference { budget, midRange, luxury }
enum GroupType { solo, couple, family, friends }

int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  return int.tryParse('$v') ?? 0;
}

class ItineraryPreferences {
  final int days;
  final int totalBudget;
  final FoodPreference foodPreference;
  final List<String> interests;
  final StayPreference stayPreference;
  final DateTime startDate;
  final GroupType groupType;
  final bool hasChildren;
  final List<String> childAgeGroups;
  final bool hasSeniors;
  final int groupSize;

  const ItineraryPreferences({
    required this.days,
    required this.totalBudget,
    required this.foodPreference,
    required this.interests,
    required this.stayPreference,
    required this.startDate,
    this.groupType = GroupType.solo,
    this.hasChildren = false,
    this.childAgeGroups = const [],
    this.hasSeniors = false,
    this.groupSize = 1,
  });

  String get foodLabel {
    switch (foodPreference) {
      case FoodPreference.veg:    return 'Vegetarian only';
      case FoodPreference.nonVeg: return 'Non-Vegetarian';
      case FoodPreference.both:   return 'Both Veg & Non-Veg';
    }
  }

  String get stayLabel {
    switch (stayPreference) {
      case StayPreference.budget:   return 'Budget (₹500–₹1,500/night)';
      case StayPreference.midRange: return 'Mid-Range (₹2,000–₹6,000/night)';
      case StayPreference.luxury:   return 'Luxury (₹7,000+/night)';
    }
  }

  String get groupLabel {
    switch (groupType) {
      case GroupType.solo:    return 'Solo traveller';
      case GroupType.couple:  return 'Couple';
      case GroupType.family:  return 'Family';
      case GroupType.friends: return 'Friends group';
    }
  }

  String get groupSummary {
    final buf = StringBuffer(groupLabel);
    if (groupSize > 1) buf.write(' ($groupSize people)');
    if (hasChildren && childAgeGroups.isNotEmpty) {
      buf.write(' with children (${childAgeGroups.join(', ')})');
    }
    if (hasSeniors) buf.write(', including senior citizens');
    return buf.toString();
  }
}

/// 🎯 Rich time slot — one activity in the itinerary
class TimeSlot {
  final String time;
  final String activity;
  final String category;
  final int estimatedCost;
  final String notes;
  final String duration;
  final String description;
  final List<String> alternatives;
  final double? lat; // GPS coords if from a pinned place
  final double? lng;

  TimeSlot({
    required this.time,
    required this.activity,
    required this.category,
    required this.estimatedCost,
    required this.notes,
    this.duration = '',
    this.description = '',
    this.alternatives = const [],
    this.lat,
    this.lng,
  });

  /// Create a copy with one field changed (for editing)
  TimeSlot copyWith({
    String? time,
    String? activity,
    String? category,
    int? estimatedCost,
    String? notes,
    String? duration,
    String? description,
    List<String>? alternatives,
    double? lat,
    double? lng,
  }) {
    return TimeSlot(
      time: time ?? this.time,
      activity: activity ?? this.activity,
      category: category ?? this.category,
      estimatedCost: estimatedCost ?? this.estimatedCost,
      notes: notes ?? this.notes,
      duration: duration ?? this.duration,
      description: description ?? this.description,
      alternatives: alternatives ?? this.alternatives,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
    );
  }

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    final rawAlts = json['alternatives'] as List<dynamic>? ?? [];
    return TimeSlot(
      time: json['time'] ?? '',
      activity: json['activity'] ?? '',
      category: json['category'] ?? 'attraction',
      estimatedCost: _parseInt(json['cost']),
      notes: json['notes'] ?? '',
      duration: json['duration'] ?? '',
      description: json['description'] ?? '',
      alternatives: rawAlts.map((e) => e.toString()).toList(),
    );
  }

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse('$v') ?? 0;
  }
}

/// Mutable version of ItineraryDay so the screen can edit slots
class ItineraryDay {
  final String label;
  final List<TimeSlot> slots;
  final int totalDayCost;

  const ItineraryDay({
    required this.label,
    required this.slots,
    required this.totalDayCost,
  });

  ItineraryDay copyWithSlots(List<TimeSlot> newSlots) => ItineraryDay(
      label: label, slots: newSlots, totalDayCost: newSlots.fold(0, (s, e) => s + e.estimatedCost));

  factory ItineraryDay.fromJson(Map<String, dynamic> json) {
    final rawSlots = json['slots'] as List<dynamic>? ?? [];
    final slots = rawSlots
        .map((s) => TimeSlot.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    return ItineraryDay(
      label: json['label'] ?? 'Day',
      slots: slots,
      totalDayCost: TimeSlot._parseInt(json['totalCost']),
    );
  }
}

class GeneratedItinerary {
  final List<ItineraryDay> days;
  final int grandTotal;
  final String stayRecommendation;
  final String landmarkName;
  final ItineraryPreferences preferences;
  final double lat;  // landmark GPS — used by route map
  final double lng;

  const GeneratedItinerary({
    required this.days,
    required this.grandTotal,
    required this.stayRecommendation,
    required this.landmarkName,
    required this.preferences,
    this.lat = 0.0,
    this.lng = 0.0,
  });
}

/// Result from nearby places search (OSM)
class PlaceResult {
  final String name;
  final double lat;
  final double lng;
  final String category;
  final String? cuisine;
  final bool? isVeg;
  final String? openingHours;
  final String? phone;
  final String? website;

  const PlaceResult({
    required this.name,
    required this.lat,
    required this.lng,
    required this.category,
    this.cuisine,
    this.isVeg,
    this.openingHours,
    this.phone,
    this.website,
  });
}
