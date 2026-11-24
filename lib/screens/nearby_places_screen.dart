import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/nearby_places_service.dart';
import '../models/itinerary_model.dart';
import '../widgets/itinerary_setup_sheet.dart';

class NearbyPlacesScreen extends StatefulWidget {
  final String landmarkName;
  final double lat;
  final double lng;

  const NearbyPlacesScreen({
    super.key,
    required this.landmarkName,
    required this.lat,
    required this.lng,
  });

  @override
  State<NearbyPlacesScreen> createState() => _NearbyPlacesScreenState();
}

class _NearbyPlacesScreenState extends State<NearbyPlacesScreen>
    with SingleTickerProviderStateMixin {
  final NearbyPlacesService _placesService = NearbyPlacesService();
  final MapController _mapController = MapController();
  late TabController _tabController;

  List<PlaceResult> _attractions = [];
  List<PlaceResult> _vegRestaurants = [];
  List<PlaceResult> _nonVegRestaurants = [];
  List<PlaceResult> _hotels = [];
  bool _loading = true;
  String? _error;
  PlaceResult? _selectedPlace;
  bool _showList = true;
  final Set<PlaceResult> _selectedForItinerary = {}; // 📌 user-pinned places

  static const _tabs = ['🏛 Spots', '🥗 Veg', '🍗 Non-Veg', '🏨 Hotels'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() => _selectedPlace = null));
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _placesService.fetchAttractions(lat: widget.lat, lng: widget.lng),
        _placesService.fetchRestaurants(lat: widget.lat, lng: widget.lng, foodPref: FoodPreference.veg),
        _placesService.fetchRestaurants(lat: widget.lat, lng: widget.lng, foodPref: FoodPreference.nonVeg),
        _placesService.fetchHotels(lat: widget.lat, lng: widget.lng),
      ]);
      setState(() {
        _attractions = results[0];
        _vegRestaurants = results[1];
        _nonVegRestaurants = results[2];
        _hotels = results[3];
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Could not load places. Check internet.'; _loading = false; });
    }
  }

  List<PlaceResult> get _currentPlaces {
    switch (_tabController.index) {
      case 0: return _attractions;
      case 1: return _vegRestaurants;
      case 2: return _nonVegRestaurants;
      case 3: return _hotels;
      default: return _attractions;
    }
  }

  Color get _tabColor {
    switch (_tabController.index) {
      case 0: return Colors.blue.shade700;
      case 1: return Colors.green.shade700;
      case 2: return Colors.deepOrange.shade700;
      case 3: return Colors.purple.shade700;
      default: return Colors.blue.shade700;
    }
  }

  Color _markerColor(PlaceResult p) {
    if (p.category == 'hotel') return Colors.purple.shade700;
    if (p.category == 'restaurant') {
      return p.isVeg == true ? Colors.green.shade700 : Colors.deepOrange.shade700;
    }
    return Colors.blue.shade700;
  }

  Future<void> _openDirections(PlaceResult place) async {
    final url = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${place.lat},${place.lng}&travelmode=driving');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      // fallback: geo: URI
      final geo = Uri.parse('geo:${place.lat},${place.lng}?q=${Uri.encodeComponent(place.name)}');
      if (await canLaunchUrl(geo)) await launchUrl(geo);
    }
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: _tabColor,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Explore Nearby', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          Text(widget.landmarkName.replaceAll('_', ' '),
              style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        actions: [
          // Toggle map/list view
          IconButton(
            icon: Icon(_showList ? Icons.map : Icons.list),
            tooltip: _showList ? 'Map View' : 'List View',
            onPressed: () => setState(() => _showList = !_showList),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAll),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : Column(children: [
                  // Map — fixed height
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.38,
                    child: _buildMap(),
                  ),

                  // Count + view toggle bar
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _tabColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('${_currentPlaces.length} places found',
                            style: TextStyle(color: _tabColor, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                      const Spacer(),
                      Text(_showList ? 'Swipe list below' : 'Tap markers on map',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
                    ]),
                  ),

                  // Scrollable place list
                  Expanded(
                    child: _currentPlaces.isEmpty
                        ? _buildEmptyState()
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                            itemCount: _currentPlaces.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _buildPlaceListTile(_currentPlaces[i]),
                          ),
                  ),
                ]),

      // Plan Itinerary FAB — with pinned counter badge above it
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Pinned count badge
          if (_selectedForItinerary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.green.shade700,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 6)
                  ],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.bookmark, color: Colors.white, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    '${_selectedForItinerary.length} place${_selectedForItinerary.length > 1 ? 's' : ''} added to trip',
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ]),
              ),
            ),

          FloatingActionButton.extended(
            backgroundColor: _tabColor,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Plan Itinerary', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => ItinerarySetupSheet(
                  landmarkName: widget.landmarkName,
                  lat: widget.lat,
                  lng: widget.lng,
                  pinnedPlaces: _selectedForItinerary.toList(),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildMap() {
    final landmarkLatLng = LatLng(widget.lat, widget.lng);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: landmarkLatLng,
        initialZoom: 15.0,
        onTap: (_, __) => setState(() => _selectedPlace = null),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
        ),
        CircleLayer(circles: [
          CircleMarker(
            point: landmarkLatLng, radius: 80, useRadiusInMeter: true,
            color: _tabColor.withOpacity(0.12),
            borderColor: _tabColor, borderStrokeWidth: 2,
          ),
        ]),
        MarkerLayer(markers: [
          // Landmark star
          Marker(
            point: landmarkLatLng, width: 44, height: 44,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.amber.shade700, shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 6)],
              ),
              child: const Icon(Icons.star, color: Colors.white, size: 22),
            ),
          ),
          // Place markers
          ..._currentPlaces.map((place) {
            final isSelected = _selectedPlace == place;
            final color = _markerColor(place);
            return Marker(
              point: LatLng(place.lat, place.lng),
              width: isSelected ? 52 : 40,
              height: isSelected ? 52 : 40,
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedPlace = place);
                  _mapController.move(LatLng(place.lat, place.lng), 15.5);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : color,
                    shape: BoxShape.circle,
                    border: Border.all(color: isSelected ? color : Colors.white, width: isSelected ? 3 : 2),
                    boxShadow: [const BoxShadow(color: Colors.black38, blurRadius: 5)],
                  ),
                  child: Icon(_categoryIcon(place.category),
                      color: isSelected ? color : Colors.white,
                      size: isSelected ? 26 : 20),
                ),
              ),
            );
          }),
        ]),
      ],
    );
  }

  /// Full list tile for each place — no tapping individual markers needed
  Widget _buildPlaceListTile(PlaceResult place) {
    final color = _markerColor(place);
    final isSelected = _selectedPlace == place;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: isSelected ? 2 : 0),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 8, offset: const Offset(0, 3))
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() => _selectedPlace = place);
            _mapController.move(LatLng(place.lat, place.lng), 16);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Icon
              Container(
                width: 46, height: 46,
                decoration: BoxDecoration(
                    color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                child: Icon(_categoryIcon(place.category), color: color, size: 24),
              ),
              const SizedBox(width: 12),

              // Info
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(place.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  if (place.isVeg == true) ...[
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Veg', style: TextStyle(color: Colors.green.shade700,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                  ] else if (place.isVeg == false) ...[
                    Container(width: 10, height: 10,
                        decoration: BoxDecoration(color: Colors.red.shade600, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text('Non-Veg', style: TextStyle(color: Colors.red.shade700,
                        fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                  ],
                  if (place.cuisine != null)
                    Text(place.cuisine!.toUpperCase(),
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 10,
                            letterSpacing: 0.4)),
                ]),
                if (place.openingHours != null)
                  Text('🕐 ${place.openingHours}',
                      style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),

              // Bookmark + Directions buttons
              const SizedBox(width: 8),
              // Bookmark toggle
              GestureDetector(
                onTap: () => setState(() {
                  if (_selectedForItinerary.contains(place)) {
                    _selectedForItinerary.remove(place);
                  } else {
                    _selectedForItinerary.add(place);
                  }
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  decoration: BoxDecoration(
                    color: _selectedForItinerary.contains(place)
                        ? Colors.green.shade700
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _selectedForItinerary.contains(place)
                          ? Colors.green.shade700
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Icon(
                    _selectedForItinerary.contains(place)
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: _selectedForItinerary.contains(place)
                        ? Colors.white
                        : Colors.grey.shade500,
                    size: 18,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Directions
              GestureDetector(
                onTap: () => _openDirections(place),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.directions, color: Colors.white, size: 16),
                    const SizedBox(width: 4),
                    const Text('Go', style: TextStyle(color: Colors.white,
                        fontWeight: FontWeight.bold, fontSize: 12)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.search_off, size: 52, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text('No places found nearby', style: TextStyle(color: Colors.grey.shade500)),
    ]),
  );

  Widget _buildLoading() => const Center(child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      CircularProgressIndicator(color: Colors.orange),
      SizedBox(height: 16),
      Text('Finding places nearby…', style: TextStyle(color: Colors.grey)),
    ],
  ));

  Widget _buildError() => Center(
    child: Padding(padding: const EdgeInsets.all(32), child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off, size: 60, color: Colors.grey),
        const SizedBox(height: 16),
        Text(_error!, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        ElevatedButton.icon(onPressed: _loadAll,
            icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ],
    )),
  );

  IconData _categoryIcon(String category) {
    switch (category) {
      case 'attraction': return Icons.photo_camera_back;
      case 'restaurant': return Icons.restaurant;
      case 'hotel':      return Icons.hotel;
      default:           return Icons.place;
    }
  }
}
