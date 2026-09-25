import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'palette.dart';

/// Google-pinpoint style map picker: the pin sits at the map centre — pan the
/// map until the pin points at the khata location, then SAVE. Returns
/// `LatLng?` (null if cancelled) via Navigator.pop.
///
/// Note: OpenStreetMap tiles need a network connection; the chosen
/// latitude/longitude is saved locally and keeps working offline.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen(
      {super.key, this.initial, this.title = 'Pin khata location'});

  final LatLng? initial;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _mapController = MapController();
  late LatLng _center;
  bool _moved = false;

  @override
  void initState() {
    super.initState();
    // Default: Pallipatti town (Kadapa district) — falls back to AP centre.
    _center = widget.initial ?? const LatLng(14.4681, 78.0167);
  }

  void _confirm() {
    Navigator.pop(context, _mapController.camera.center);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(onPressed: _confirm, child: const Text('SAVE')),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 15,
                onPositionChanged: (position, hasGesture) {
                  if (hasGesture) {
                    setState(() {
                      _center = position.center;
                      _moved = true;
                    });
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.shyberdev.jewellery_suite',
                ),
              ],
            ),
          ),
          // The pin always points at the exact centre of the map.
          IgnorePointer(
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: Icon(Icons.location_pin,
                    size: 46,
                    color: Colors.red.shade700,
                    shadows: const [
                      Shadow(
                          color: Colors.black45,
                          blurRadius: 8,
                          offset: Offset(0, 2)),
                    ]),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.white,
              elevation: 4,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: kGoldDark),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _moved
                            ? 'Pin set at ${_center.latitude.toStringAsFixed(5)}, ${_center.longitude.toStringAsFixed(5)}'
                            : 'Pan the map so the pin points at the khata location',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton(
                      onPressed: () async {
                        final pickedCenter = _mapController.camera.center;
                        setState(() {
                          _center = pickedCenter;
                          _moved = true;
                        });
                      },
                      child: const Text('Re-pin'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}