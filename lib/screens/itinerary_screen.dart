import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/itinerary_model.dart';

/// 🗓️ Full itinerary view — rich cards, expandable details, editable slots
class ItineraryScreen extends StatefulWidget {
  final GeneratedItinerary itinerary;
  const ItineraryScreen({super.key, required this.itinerary});

  @override
  State<ItineraryScreen> createState() => _ItineraryScreenState();
}

class _ItineraryScreenState extends State<ItineraryScreen> {
  late List<ItineraryDay> _days;
  final Set<String> _expandedSlots = {}; // key = "dayIdx_slotIdx"
  int _selectedDay = 0;

  @override
  void initState() {
    super.initState();
    _days = List.of(widget.itinerary.days);
    if (_days.isNotEmpty) _expandedSlots.add('0_0'); // open first slot
  }

  String _slotKey(int d, int s) => '${d}_$s';
  bool _isExpanded(int d, int s) => _expandedSlots.contains(_slotKey(d, s));

  void _toggleExpanded(int d, int s) => setState(() {
    final key = _slotKey(d, s);
    if (_expandedSlots.contains(key)) _expandedSlots.remove(key);
    else _expandedSlots.add(key);
  });

  // ─── Swap an alternative into a slot ────────────────────────────────
  void _swapAlternative(int dayIdx, int slotIdx, String newName) {
    setState(() {
      final day = _days[dayIdx];
      final old = day.slots[slotIdx];
      final newSlots = List<TimeSlot>.of(day.slots);
      final newAlts = List<String>.of(old.alternatives)
        ..remove(newName)
        ..add(old.activity);
      newSlots[slotIdx] = old.copyWith(activity: newName, alternatives: newAlts);
      _days[dayIdx] = day.copyWithSlots(newSlots);
    });
  }

  // ─── Manual edit bottom sheet ────────────────────────────────────────
  void _openEditSheet(int dayIdx, int slotIdx) {
    final slot = _days[dayIdx].slots[slotIdx];
    final nameCtrl = TextEditingController(text: slot.activity);
    final noteCtrl = TextEditingController(text: slot.notes);
    final costCtrl = TextEditingController(text: '${slot.estimatedCost}');
    final descCtrl = TextEditingController(text: slot.description);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 16),
            Row(children: [
              Icon(_slotIcon(slot.category), color: _slotColor(slot.category)),
              const SizedBox(width: 10),
              Text('Edit Slot', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            ]),
            const SizedBox(height: 16),
            _editField('Place / Activity', nameCtrl, Icons.place),
            const SizedBox(height: 10),
            _editField('Description', descCtrl, Icons.info_outline, maxLines: 3),
            const SizedBox(height: 10),
            _editField('Insider tip', noteCtrl, Icons.lightbulb_outline),
            const SizedBox(height: 10),
            _editField('Cost (₹)', costCtrl, Icons.currency_rupee,
                inputType: TextInputType.number),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _slotColor(slot.category),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                ),
                onPressed: () {
                  setState(() {
                    final day = _days[dayIdx];
                    final newSlots = List<TimeSlot>.of(day.slots);
                    newSlots[slotIdx] = slot.copyWith(
                      activity: nameCtrl.text.trim(),
                      notes: noteCtrl.text.trim(),
                      estimatedCost: int.tryParse(costCtrl.text) ?? slot.estimatedCost,
                      description: descCtrl.text.trim(),
                    );
                    _days[dayIdx] = day.copyWithSlots(newSlots);
                  });
                  Navigator.pop(context);
                },
                child: const Text('Save Changes',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final prefs = widget.itinerary.preferences;
    final grandTotal = _days.fold(0, (s, d) => s + d.totalDayCost);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: CustomScrollView(
        slivers: [
          // ── Route map ───────────────────────────────────────────────
          SliverToBoxAdapter(child: SizedBox(height: 220, child: _buildRouteMap())),

          // ── Trip info header strip ──────────────────────────────────
          SliverToBoxAdapter(child: _buildTripHeader()),

          // ── Day tabs ─────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: List.generate(_days.length, (i) {
                    final sel = _selectedDay == i;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedDay = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(right: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        decoration: BoxDecoration(
                          color: sel ? Colors.deepOrange.shade600 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: sel ? Colors.deepOrange.shade600 : Colors.grey.shade300),
                        ),
                        child: Text('Day ${i + 1}', style: TextStyle(
                          color: sel ? Colors.white : Colors.grey.shade700,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        )),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),

          // ── Stay card ────────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.purple.shade200),
              ),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: Colors.purple.shade100, shape: BoxShape.circle),
                    child: Icon(Icons.hotel, color: Colors.purple.shade700, size: 20)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Where to Stay',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          color: Colors.purple.shade800, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(widget.itinerary.stayRecommendation,
                      style: TextStyle(color: Colors.purple.shade700, fontSize: 12)),
                ])),
              ]),
            ),
          )),

          // ── Budget card ───────────────────────────────────────────────
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _buildBudgetCard(),
          )),

          // ── Day timeline slots ─────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  if (_selectedDay >= _days.length) return null;
                  final slots = _days[_selectedDay].slots;
                  if (i >= slots.length) return null;
                  return _buildSlotCard(_selectedDay, i, slots[i]);
                },
                childCount: _selectedDay < _days.length
                    ? _days[_selectedDay].slots.length
                    : 0,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ─── Route Map ───────────────────────────────────────────────────────
  Widget _buildRouteMap() {
    final landmarkLat = widget.itinerary.lat;
    final landmarkLng = widget.itinerary.lng;
    final hasCoords = landmarkLat != 0.0 || landmarkLng != 0.0;

    // Collect all slots that have pinned GPS coordinates
    final stops = _days
        .expand((d) => d.slots)
        .where((s) => s.lat != null && s.lng != null)
        .toList();

    // Build polyline: landmark → stops in order
    final routePoints = <LatLng>[
      if (hasCoords) LatLng(landmarkLat, landmarkLng),
      ...stops.map((s) => LatLng(s.lat!, s.lng!)),
    ];

    final center = hasCoords
        ? LatLng(landmarkLat, landmarkLng)
        : (stops.isNotEmpty
            ? LatLng(stops.first.lat!, stops.first.lng!)
            : const LatLng(18.9220, 72.8347)); // Mumbai fallback

    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: 14.5),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
        ),
        // Route polyline
        if (routePoints.length > 1)
          PolylineLayer(polylines: [
            Polyline(
              points: routePoints,
              color: Colors.deepOrange.shade600,
              strokeWidth: 3.5,
              pattern: StrokePattern.dashed(segments: const [12, 6]),
            ),
          ]),
        MarkerLayer(markers: [
          // 🌟 Landmark start marker
          if (hasCoords)
            Marker(
              point: LatLng(landmarkLat, landmarkLng),
              width: 48, height: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.amber.shade700,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                ),
                child: const Icon(Icons.star, color: Colors.white, size: 22),
              ),
            ),
          // 🔴 Stop markers
          ...stops.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value;
            return Marker(
              point: LatLng(s.lat!, s.lng!),
              width: 38, height: 38,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade600,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Center(
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13,
                          fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }),
        ]),
      ],
    );
  }

  // ─── Trip Info Header Strip ─────────────────────────────────────────
  Widget _buildTripHeader() {
    final prefs = widget.itinerary.preferences;
    final grandTotal = _days.fold(0, (s, d) => s + d.totalDayCost);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade500, Colors.deepOrange.shade800],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome, color: Colors.white70, size: 13),
            const SizedBox(width: 5),
            const Text('AI-Generated Trip',
                style: TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          Text(widget.itinerary.landmarkName.replaceAll('_', ' '),
              style: const TextStyle(
                  color: Colors.white, fontSize: 20,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _hChip(Icons.calendar_today,
                '${prefs.days} day${prefs.days > 1 ? 's' : ''}'),
            _hChip(Icons.people, prefs.groupSummary.split(' (').first),
            _hChip(Icons.currency_rupee, '₹$grandTotal total'),
            _hChip(
                prefs.foodPreference == FoodPreference.veg
                    ? Icons.eco
                    : Icons.restaurant,
                prefs.foodLabel),
          ]),
        ]),
      ),
    );
  }

  // ─── Rich Slot Card ─────────────────────────────────────────────────

  Widget _buildSlotCard(int dayIdx, int slotIdx, TimeSlot slot) {
    final expanded = _isExpanded(dayIdx, slotIdx);
    final color = _slotColor(slot.category);
    final icon = _slotIcon(slot.category);
    final key = ValueKey(_slotKey(dayIdx, slotIdx) + slot.activity);

    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06),
                blurRadius: 10, offset: const Offset(0, 4))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Slot header (always visible) ──────────────────────────
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              onTap: () => _toggleExpanded(dayIdx, slotIdx),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Time column
                  SizedBox(width: 64, child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(slot.time,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                              color: color)),
                      if (slot.duration.isNotEmpty)
                        Text(slot.duration,
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  )),

                  // Category icon
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.14), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),

                  // Name + category label
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(slot.activity,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          maxLines: 2),
                      const SizedBox(height: 2),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20)),
                          child: Text(_categoryLabel(slot.category),
                              style: TextStyle(fontSize: 10, color: color,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ],
                  )),

                  // Cost + expand arrow
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: slot.estimatedCost == 0
                            ? Colors.green.shade50 : color.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        slot.estimatedCost == 0 ? 'Free' : '₹${slot.estimatedCost}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12,
                          color: slot.estimatedCost == 0
                              ? Colors.green.shade700 : color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Colors.grey.shade400, size: 20),
                  ]),
                ]),
              ),
            ),
          ),

          // ── Expanded detail section ────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 250),
            crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Divider(color: Colors.grey.shade100, height: 16),

                // Description
                if (slot.description.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(slot.description,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade800,
                            height: 1.5)),
                  ),
                  const SizedBox(height: 10),
                ],

                // Insider tip
                if (slot.notes.isNotEmpty) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.lightbulb, color: Colors.amber.shade600, size: 16),
                    const SizedBox(width: 6),
                    Expanded(child: Text(slot.notes,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700,
                            fontStyle: FontStyle.italic))),
                  ]),
                  const SizedBox(height: 12),
                ],

                // Alternatives — food & stay slots
                if (slot.alternatives.isNotEmpty) ...[
                  const Text('🔀 Swap with another option:',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: slot.alternatives.map((alt) {
                    return GestureDetector(
                      onTap: () => _swapAlternative(dayIdx, slotIdx, alt),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: color.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                              color: color.withOpacity(0.08), blurRadius: 4)],
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.swap_horiz, size: 14, color: color),
                          const SizedBox(width: 5),
                          Text(alt, style: TextStyle(fontSize: 12,
                              color: color, fontWeight: FontWeight.w600),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    );
                  }).toList()),
                  const SizedBox(height: 10),
                ],

                // Edit button
                GestureDetector(
                  onTap: () => _openEditSheet(dayIdx, slotIdx),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 5),
                      Text('Edit this slot',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ]),
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ]),
      ),
    );
  }

  // ─── Budget breakdown ────────────────────────────────────────────────
  Widget _buildBudgetCard() {
    final totals = <String, int>{};
    for (final day in _days) {
      for (final s in day.slots) {
        totals[s.category] = (totals[s.category] ?? 0) + s.estimatedCost;
      }
    }
    final grandTotal = totals.values.fold(0, (a, b) => a + b);

    final cats = [
      {'k': 'attraction', 'label': 'Attractions', 'icon': Icons.photo_camera_back, 'color': Colors.blue},
      {'k': 'food', 'label': 'Food & Dining', 'icon': Icons.restaurant, 'color': Colors.orange},
      {'k': 'stay', 'label': 'Stay', 'icon': Icons.hotel, 'color': Colors.purple},
      {'k': 'travel', 'label': 'Travel', 'icon': Icons.directions_car, 'color': Colors.teal},
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.pie_chart, color: Colors.orange, size: 18),
          const SizedBox(width: 8),
          const Text('Budget Breakdown',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const Spacer(),
          Text('₹$grandTotal',
              style: TextStyle(color: Colors.orange.shade700,
                  fontWeight: FontWeight.bold, fontSize: 14)),
        ]),
        const SizedBox(height: 14),
        ...cats.map((c) {
          final amt = totals[c['k']] ?? 0;
          if (amt == 0) return const SizedBox.shrink();
          final pct = grandTotal > 0 ? amt / grandTotal : 0.0;
          final mc = c['color'] as MaterialColor;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(c['icon'] as IconData, size: 15, color: mc.shade600),
              const SizedBox(width: 7),
              SizedBox(width: 80, child: Text(c['label'] as String,
                  style: const TextStyle(fontSize: 12))),
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: pct.toDouble(), minHeight: 8,
                  backgroundColor: Colors.grey.shade100,
                  valueColor: AlwaysStoppedAnimation(mc.shade500),
                ),
              )),
              const SizedBox(width: 8),
              SizedBox(width: 52, child: Text('₹$amt',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600, color: mc.shade700))),
            ]),
          );
        }),
      ]),
    );
  }

  // ─── Bottom bar ──────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08),
            blurRadius: 12, offset: const Offset(0, -4))],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.deepOrange.shade700,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        icon: const Icon(Icons.share),
        label: const Text('Share Itinerary',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        onPressed: _share,
      ),
    );
  }

  Future<void> _share() async {
    final buf = StringBuffer();
    buf.writeln('🗺️ Trip: ${widget.itinerary.landmarkName.replaceAll("_", " ")}');
    buf.writeln('📅 ${widget.itinerary.preferences.days} days  |  '
        '₹${_days.fold(0, (s, d) => s + d.totalDayCost)} total');
    buf.writeln('🏠 ${widget.itinerary.stayRecommendation}\n');
    for (final day in _days) {
      buf.writeln('── ${day.label} ──');
      for (final s in day.slots) {
        buf.writeln('${s.time}  ${s.activity}  (${s.estimatedCost == 0 ? "Free" : "₹${s.estimatedCost}"})');
        if (s.description.isNotEmpty) buf.writeln('  ${s.description}');
        if (s.notes.isNotEmpty) buf.writeln('  Tip: ${s.notes}');
      }
      buf.writeln('Day total: ₹${day.totalDayCost}\n');
    }
    buf.writeln('Generated by AR Vista 🌟');

    final uri = Uri.parse('mailto:?subject=${Uri.encodeComponent("My Trip Itinerary")}'
        '&body=${Uri.encodeComponent(buf.toString())}');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ─── Helpers ─────────────────────────────────────────────────────────
  Color _slotColor(String cat) {
    switch (cat) {
      case 'attraction': return Colors.blue.shade600;
      case 'food':       return Colors.orange.shade600;
      case 'stay':       return Colors.purple.shade600;
      case 'travel':     return Colors.teal.shade600;
      default:           return Colors.grey.shade600;
    }
  }

  IconData _slotIcon(String cat) {
    switch (cat) {
      case 'attraction': return Icons.photo_camera_back;
      case 'food':       return Icons.restaurant;
      case 'stay':       return Icons.hotel;
      case 'travel':     return Icons.directions_car;
      default:           return Icons.circle;
    }
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'attraction': return 'Sightseeing';
      case 'food':       return 'Dining';
      case 'stay':       return 'Stay';
      case 'travel':     return 'Travel';
      default:           return cat;
    }
  }

  Widget _hChip(IconData icon, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: Colors.white, size: 12),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: Colors.white,
          fontSize: 11, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _editField(String label, TextEditingController ctrl, IconData icon,
      {int maxLines = 1, TextInputType inputType = TextInputType.text}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: inputType,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.grey.shade200)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
