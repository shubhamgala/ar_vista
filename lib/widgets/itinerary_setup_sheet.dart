import 'package:flutter/material.dart';
import '../models/itinerary_model.dart';
import '../services/nearby_places_service.dart';
import '../services/itinerary_service.dart';
import '../screens/itinerary_screen.dart';

/// 🗓️ 4-step bottom sheet: Group → When/Budget → Preferences → Generating
class ItinerarySetupSheet extends StatefulWidget {
  final String landmarkName;
  final double lat;
  final double lng;
  final List<PlaceResult> pinnedPlaces; // pre-selected from Nearby Places

  const ItinerarySetupSheet({
    super.key,
    required this.landmarkName,
    required this.lat,
    required this.lng,
    this.pinnedPlaces = const [],
  });

  @override
  State<ItinerarySetupSheet> createState() => _ItinerarySetupSheetState();
}

class _ItinerarySetupSheetState extends State<ItinerarySetupSheet> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _generating = false;
  String? _genError;

  // ─── Step 0: Group ────────────────────────────────────────
  GroupType _groupType = GroupType.solo;
  int _groupSize = 1;
  bool _hasChildren = false;
  final Set<String> _childAgeGroups = {};
  bool _hasSeniors = false;

  // ─── Step 1: When & Budget ───────────────────────────────
  int _days = 2;
  int _budget = 5000;
  DateTime _startDate = DateTime.now();

  // ─── Step 2: Preferences ─────────────────────────────────
  FoodPreference _foodPref = FoodPreference.veg;
  StayPreference _stayPref = StayPreference.midRange;
  final Set<String> _interests = {'Heritage'};

  static const _allInterests = [
    'Heritage', 'Beaches', 'Temples', 'Shopping',
    'Adventure', 'Food Trail', 'Nightlife', 'Nature', 'Museums',
  ];
  static const _budgetOptions = [1500, 4000, 12000, 25000];
  static const _budgetLabels = ['< ₹2k', '₹2k–5k', '₹5k–15k', '₹15k+'];

  final _placesService = NearbyPlacesService();
  final _itineraryService = ItineraryService();

  static const _stepTitles = [
    'Who\'s travelling?',
    'When & Budget',
    'Preferences',
    'Crafting trip…',
  ];

  void _go(int step) {
    _pageController.animateToPage(step,
        duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
    setState(() => _currentStep = step);
  }

  Future<void> _generate() async {
    _go(3);
    setState(() { _generating = true; _genError = null; });

    try {
      final prefs = ItineraryPreferences(
        days: _days,
        totalBudget: _budget,
        foodPreference: _foodPref,
        interests: _interests.toList(),
        stayPreference: _stayPref,
        startDate: _startDate,
        groupType: _groupType,
        hasChildren: _hasChildren,
        childAgeGroups: _childAgeGroups.toList(),
        hasSeniors: _hasSeniors,
        groupSize: _groupSize,
      );

      final results = await Future.wait([
        _placesService.fetchAttractions(lat: widget.lat, lng: widget.lng),
        _placesService.fetchRestaurants(lat: widget.lat, lng: widget.lng, foodPref: _foodPref),
        _placesService.fetchHotels(lat: widget.lat, lng: widget.lng),
      ]);

      final itinerary = await _itineraryService.generateItinerary(
        landmarkName: widget.landmarkName,
        prefs: prefs,
        nearbyAttractions: results[0],
        nearbyRestaurants: results[1],
        nearbyHotels: results[2],
        pinnedPlaces: widget.pinnedPlaces,
        landmarkLat: widget.lat,
        landmarkLng: widget.lng,
      );

      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => ItineraryScreen(itinerary: itinerary)));
    } catch (e) {
      setState(() { _genError = 'Could not generate itinerary. Please try again.'; _generating = false; });
    }
  }

  @override
  void dispose() { _pageController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.93,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, sc) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(children: [
          const SizedBox(height: 12),
          Container(width: 42, height: 4,
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.orange.shade600, Colors.deepOrange.shade700]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Plan My Itinerary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                Text(widget.landmarkName.replaceAll('_', ' '),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ])),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          const SizedBox(height: 12),

          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              ...List.generate(4, (i) => Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= _currentStep ? Colors.orange.shade600 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              )),
            ]),
          ),
          if (_currentStep < 3)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_stepTitles[_currentStep],
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          const SizedBox(height: 8),

          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep0(sc),
                _buildStep1(sc),
                _buildStep2(sc),
                _buildStep3(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ─── Step 0: Group Profile ────────────────────────────────────────────
  Widget _buildStep0(ScrollController sc) {
    return SingleChildScrollView(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('🧳 Who\'s travelling?'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _groupChip('🧍 Solo', GroupType.solo),
          _groupChip('💑 Couple', GroupType.couple),
          _groupChip('👨‍👩‍👧 Family', GroupType.family),
          _groupChip('👫 Friends', GroupType.friends),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('👥 Group size'),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _circleButton(Icons.remove, () { if (_groupSize > 1) setState(() => _groupSize--); }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text('$_groupSize', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          ),
          _circleButton(Icons.add, () { if (_groupSize < 20) setState(() => _groupSize++); }),
        ]),
        const SizedBox(height: 20),

        // Children section
        _sectionTitle('👶 Children in group?'),
        Row(children: [
          Expanded(child: _toggleCard('Yes, we have kids', Icons.child_care, _hasChildren,
              () => setState(() { _hasChildren = true; }))),
          const SizedBox(width: 8),
          Expanded(child: _toggleCard('No children', Icons.no_stroller, !_hasChildren,
              () => setState(() { _hasChildren = false; _childAgeGroups.clear(); }))),
        ]),

        if (_hasChildren) ...[
          const SizedBox(height: 14),
          _sectionTitle('🎈 Children age groups (select all that apply)'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ageChip('👶 Toddlers (0–3)', 'toddler'),
            _ageChip('🧒 Kids (4–10)', 'kids'),
            _ageChip('🧑 Teens (11–17)', 'teens'),
          ]),
        ],
        const SizedBox(height: 16),

        _sectionTitle('👴 Senior citizens?'),
        Row(children: [
          Expanded(child: _toggleCard('Yes, includes seniors', Icons.elderly, _hasSeniors,
              () => setState(() => _hasSeniors = true))),
          const SizedBox(width: 8),
          Expanded(child: _toggleCard('No seniors', Icons.directions_run, !_hasSeniors,
              () => setState(() => _hasSeniors = false))),
        ]),
        const SizedBox(height: 28),
        _nextButton('Next: When & Budget →', () => _go(1)),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ─── Step 1: When & Budget ───────────────────────────────────────────
  Widget _buildStep1(ScrollController sc) {
    return SingleChildScrollView(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('📅 Start date'),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _startDate,
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              builder: (ctx, child) => Theme(
                data: ThemeData.light().copyWith(
                    colorScheme: ColorScheme.light(primary: Colors.orange.shade600)),
                child: child!,
              ),
            );
            if (picked != null) setState(() => _startDate = picked);
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                border: Border.all(color: Colors.orange.shade300),
                borderRadius: BorderRadius.circular(16),
                color: Colors.orange.shade50),
            child: Row(children: [
              Icon(Icons.today, color: Colors.orange.shade700),
              const SizedBox(width: 12),
              Text('${_startDate.day}/${_startDate.month}/${_startDate.year}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
              const Spacer(),
              Icon(Icons.edit_calendar, color: Colors.orange.shade400),
            ]),
          ),
        ),
        const SizedBox(height: 20),

        _sectionTitle('🌙 Number of days'),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _circleButton(Icons.remove, () { if (_days > 1) setState(() => _days--); }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text('$_days', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          ),
          _circleButton(Icons.add, () { if (_days < 7) setState(() => _days++); }),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('💰 Total budget (for all ${_groupSize} people)'),
        Wrap(spacing: 8, runSpacing: 8, children: List.generate(_budgetOptions.length, (i) {
          final selected = _budget == _budgetOptions[i];
          return GestureDetector(
            onTap: () => setState(() => _budget = _budgetOptions[i]),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? Colors.orange.shade600 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: selected ? Colors.orange.shade600 : Colors.grey.shade300),
              ),
              child: Text(_budgetLabels[i],
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.grey.shade700,
                      fontWeight: FontWeight.w600)),
            ),
          );
        })),
        const SizedBox(height: 28),
        Row(children: [
          TextButton.icon(onPressed: () => _go(0), icon: const Icon(Icons.arrow_back), label: const Text('Back')),
          const Spacer(),
          Expanded(flex: 3, child: _nextButton('Next: Preferences →', () => _go(2))),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ─── Step 2: Preferences ─────────────────────────────────────────────
  Widget _buildStep2(ScrollController sc) {
    return SingleChildScrollView(
      controller: sc,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionTitle('🍽 Food preference'),
        Row(children: [
          _foodChip('🥗 Veg', FoodPreference.veg),
          const SizedBox(width: 8),
          _foodChip('🍗 Non-Veg', FoodPreference.nonVeg),
          const SizedBox(width: 8),
          _foodChip('🔀 Both', FoodPreference.both),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('🏠 Accommodation'),
        Column(children: [
          _stayOption('🏕 Budget', '₹500–₹1,500/night', StayPreference.budget),
          const SizedBox(height: 8),
          _stayOption('🏨 Mid-Range', '₹2,000–₹6,000/night', StayPreference.midRange),
          const SizedBox(height: 8),
          _stayOption('🌟 Luxury', '₹7,000+/night', StayPreference.luxury),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('🎯 Interests (pick any)'),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: _allInterests.map((interest) {
            final sel = _interests.contains(interest);
            return FilterChip(
              label: Text(interest),
              selected: sel,
              onSelected: (v) => setState(() => v ? _interests.add(interest) : _interests.remove(interest)),
              selectedColor: Colors.orange.shade100,
              checkmarkColor: Colors.orange.shade700,
              labelStyle: TextStyle(
                  color: sel ? Colors.orange.shade800 : Colors.grey.shade700,
                  fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
              side: BorderSide(color: sel ? Colors.orange.shade400 : Colors.grey.shade300),
            );
          }).toList(),
        ),

        // Summary card before generating
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Trip Summary', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
            const SizedBox(height: 8),
            _summaryRow('👥 Group', ItineraryPreferences(days: _days, totalBudget: _budget,
                foodPreference: _foodPref, interests: [], stayPreference: _stayPref,
                startDate: _startDate, groupType: _groupType, hasChildren: _hasChildren,
                childAgeGroups: _childAgeGroups.toList(), hasSeniors: _hasSeniors,
                groupSize: _groupSize).groupSummary),
            _summaryRow('📅 Duration', '$_days day${_days > 1 ? 's' : ''}'),
            _summaryRow('💰 Budget', '₹$_budget total'),
            _summaryRow('🍽 Food', _foodPref == FoodPreference.veg ? 'Veg' : _foodPref == FoodPreference.nonVeg ? 'Non-Veg' : 'Both'),
          ]),
        ),
        const SizedBox(height: 24),
        Row(children: [
          TextButton.icon(onPressed: () => _go(1), icon: const Icon(Icons.arrow_back), label: const Text('Back')),
          const Spacer(),
          Expanded(flex: 3, child: _nextButton('✨ Generate Itinerary', _generate)),
        ]),
        const SizedBox(height: 24),
      ]),
    );
  }

  // ─── Step 3: Generating ───────────────────────────────────────────────
  Widget _buildStep3() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_generating) ...[
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, color: Colors.white, size: 48),
            ),
            const SizedBox(height: 28),
            const Text('Crafting your perfect trip ✨',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Text('Finding specific restaurants, hotels\nand activities tailored for you…',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            const CircularProgressIndicator(color: Colors.orange),
          ] else if (_genError != null) ...[
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(_genError!, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _generate,
              icon: const Icon(Icons.refresh),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white),
            ),
          ],
        ]),
      ),
    );
  }

  // ─── Helper Widgets ───────────────────────────────────────────────────
  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
  );

  Widget _nextButton(String label, VoidCallback onTap) => SizedBox(
    width: double.infinity, height: 50,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange.shade600, foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
      ),
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    ),
  );

  Widget _circleButton(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.orange.shade50, shape: BoxShape.circle,
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Icon(icon, color: Colors.orange.shade700),
    ),
  );

  Widget _groupChip(String label, GroupType type) {
    final sel = _groupType == type;
    return GestureDetector(
      onTap: () => setState(() => _groupType = type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: sel ? Colors.orange.shade600 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: sel ? Colors.orange.shade600 : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(
            color: sel ? Colors.white : Colors.grey.shade700, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  Widget _ageChip(String label, String tag) {
    final sel = _childAgeGroups.contains(tag);
    return FilterChip(
      label: Text(label),
      selected: sel,
      onSelected: (v) => setState(() => v ? _childAgeGroups.add(tag) : _childAgeGroups.remove(tag)),
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade700,
      side: BorderSide(color: sel ? Colors.blue.shade400 : Colors.grey.shade300),
      labelStyle: TextStyle(color: sel ? Colors.blue.shade800 : Colors.grey.shade700,
          fontWeight: sel ? FontWeight.w600 : FontWeight.normal),
    );
  }

  Widget _toggleCard(String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.orange.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: selected ? Colors.orange.shade400 : Colors.grey.shade200,
              width: selected ? 2 : 1),
        ),
        child: Column(children: [
          Icon(icon, color: selected ? Colors.orange.shade600 : Colors.grey.shade400, size: 26),
          const SizedBox(height: 6),
          Text(label, textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? Colors.orange.shade800 : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _foodChip(String label, FoodPreference pref) {
    final sel = _foodPref == pref;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _foodPref = pref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: sel ? Colors.orange.shade600 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: sel ? Colors.orange.shade600 : Colors.grey.shade300),
          ),
          child: Text(label, style: TextStyle(
              color: sel ? Colors.white : Colors.grey.shade700,
              fontWeight: FontWeight.w600, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _stayOption(String title, String subtitle, StayPreference pref) {
    final sel = _stayPref == pref;
    return GestureDetector(
      onTap: () => setState(() => _stayPref = pref),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: sel ? Colors.orange.shade50 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: sel ? Colors.orange.shade400 : Colors.grey.shade200, width: sel ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold,
                color: sel ? Colors.orange.shade800 : Colors.grey.shade800)),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ])),
          if (sel) Icon(Icons.check_circle, color: Colors.orange.shade600),
        ]),
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
      Expanded(child: Text(value, style: TextStyle(fontSize: 12, color: Colors.orange.shade900))),
    ]),
  );
}
