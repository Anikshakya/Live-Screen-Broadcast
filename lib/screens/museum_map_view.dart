import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/museum_poi.dart';

class MuseumMapView extends StatefulWidget {
  final List<MuseumPoi> pois;

  const MuseumMapView({
    super.key,
    required this.pois,
  });

  @override
  State<MuseumMapView> createState() => _MuseumMapViewState();
}

class _MuseumMapViewState extends State<MuseumMapView> with TickerProviderStateMixin {
  MuseumPoi? _selectedPoi;
  bool _showSidePanel = false;

  // Zoom & Pan Controller
  final TransformationController _transformationController = TransformationController();
  AnimationController? _zoomAnimationController;
  Animation<Matrix4>? _zoomAnimation;

  // Side Panel Animation Controller
  late AnimationController _panelAnimationController;
  late Animation<Offset> _panelSlideAnimation;

  @override
  void initState() {
    super.initState();
    _panelAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _panelSlideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _panelAnimationController,
      curve: Curves.easeOutCubic,
    ));

    // Listen to matrix changes to rebuild top-level callout overlay in sync with zoom/pan
    _transformationController.addListener(_onTransformationChanged);
  }

  void _onTransformationChanged() {
    if (_selectedPoi != null && mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _transformationController.removeListener(_onTransformationChanged);
    _zoomAnimationController?.dispose();
    _panelAnimationController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _selectPoi(MuseumPoi poi, Size viewportSize, double mapWidth, double mapHeight) {
    setState(() {
      _selectedPoi = poi;
      _showSidePanel = false;
    });
    _panelAnimationController.reverse();
    _zoomToPoi(poi, viewportSize, mapWidth, mapHeight);
  }

  void _zoomToPoi(MuseumPoi poi, Size viewportSize, double mapWidth, double mapHeight) {
    if (viewportSize.width == 0 || viewportSize.height == 0) return;

    final pinX = poi.dx * mapWidth;
    final pinY = poi.dy * mapHeight;

    // Responsive target scale factor
    final double targetScale = viewportSize.width < 500 ? 1.8 : 1.5;

    // Calculate translation to position (pinX, pinY) near center of viewport
    double translateX = (viewportSize.width / 2) - (pinX * targetScale);
    double translateY = (viewportSize.height / 2) - (pinY * targetScale);

    // Bound clamping so map does not float into void
    final minTx = viewportSize.width - (mapWidth * targetScale);
    final minTy = viewportSize.height - (mapHeight * targetScale);

    if (translateX > 0) translateX = 0;
    if (translateX < minTx) translateX = minTx;
    if (translateY > 0) translateY = 0;
    if (translateY < minTy) translateY = minTy;

    final endMatrix = Matrix4.identity()
      ..translate(translateX, translateY, 0.0)
      ..scale(targetScale, targetScale, 1.0);

    _animateMatrixTo(endMatrix);
  }

  void _resetZoom() {
    setState(() {
      _selectedPoi = null;
      _showSidePanel = false;
    });
    _panelAnimationController.reverse();
    _animateMatrixTo(Matrix4.identity());
  }

  void _animateMatrixTo(Matrix4 targetMatrix) {
    final Matrix4 startMatrix = _transformationController.value;
    _zoomAnimationController?.dispose();

    _zoomAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _zoomAnimation = Matrix4Tween(
      begin: startMatrix,
      end: targetMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimationController!,
      curve: Curves.easeOutCubic,
    ));

    _zoomAnimation!.addListener(() {
      _transformationController.value = _zoomAnimation!.value;
    });

    _zoomAnimationController!.forward();
  }

  void _openSidePanel() {
    setState(() {
      _showSidePanel = true;
    });
    _panelAnimationController.forward();
  }

  void _closeSidePanel() {
    _panelAnimationController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showSidePanel = false;
        });
      }
    });
  }

  void _dismissPoi() {
    _closeSidePanel();
    setState(() {
      _selectedPoi = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);

        // Responsive Map Dimensions: Entire map fits in viewport by default
        const double imageAspectRatio = 675 / 1200; // Aspect ratio of museum_map.jpg
        double mapWidth = viewportSize.width;
        double mapHeight = mapWidth / imageAspectRatio;

        if (mapHeight > viewportSize.height) {
          mapHeight = viewportSize.height;
          mapWidth = mapHeight * imageAspectRatio;
        }

        return Stack(
          children: [
            // Center the zoomable map canvas
            Center(
              child: SizedBox(
                width: mapWidth,
                height: mapHeight,
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1.0,
                  maxScale: 4.0,
                  clipBehavior: Clip.none,
                  boundaryMargin: const EdgeInsets.all(300),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Base Map Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/museum_map.jpg',
                          width: mapWidth,
                          height: mapHeight,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildFallbackMap(mapWidth, mapHeight);
                          },
                        ),
                      ),

                      // Hotspot Pins on Map
                      ...widget.pois.map((poi) {
                        final isSelected = _selectedPoi?.id == poi.id;
                        final pinX = poi.dx * mapWidth;
                        final pinY = poi.dy * mapHeight;

                        return Positioned(
                          left: pinX - 20,
                          top: pinY - 40,
                          child: GestureDetector(
                            onTap: () => _selectPoi(poi, viewportSize, mapWidth, mapHeight),
                            child: _buildPinMarker(poi, isSelected),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),
            ),

            // Top Horizontal Places Chips Row (Google Maps Style)
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildTopPlacesChipsBar(viewportSize, mapWidth, mapHeight),
            ),

            // Unclipped Responsive Overlay Info Window
            if (_selectedPoi != null && !_showSidePanel)
              _buildResponsiveOverlayInfoWindow(_selectedPoi!, viewportSize, mapWidth, mapHeight),

            // Zoom Floating Action Buttons
            Positioned(
              right: 14,
              bottom: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zoom_reset',
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.tealAccent,
                    onPressed: _resetZoom,
                    tooltip: 'Reset Map View',
                    child: const Icon(Icons.center_focus_strong_rounded, size: 20),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoom_in',
                    backgroundColor: const Color(0xFF1E293B),
                    foregroundColor: Colors.white,
                    onPressed: () {
                      final currentScale = _transformationController.value.getMaxScaleOnAxis();
                      final endMatrix = _transformationController.value.clone()..scale(1.4, 1.4, 1.0);
                      if (currentScale < 3.8) _animateMatrixTo(endMatrix);
                    },
                    tooltip: 'Zoom In',
                    child: const Icon(Icons.add, size: 20),
                  ),
                ],
              ),
            ),

            // Responsive Right-Side Column / Drawer (Google Maps Style)
            SlideTransition(
              position: _panelSlideAnimation,
              child: _selectedPoi != null
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        width: viewportSize.width > 600 ? 380 : viewportSize.width * 0.88,
                        height: double.infinity,
                        color: const Color(0xFF0F172A),
                        child: _buildRightSideDetailColumn(_selectedPoi!, viewportSize),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  // Horizontal Quick Places Selector Bar at Top
  Widget _buildTopPlacesChipsBar(Size viewportSize, double mapWidth, double mapHeight) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            // "View All" Reset Chip
            ActionChip(
              avatar: Icon(
                Icons.explore_rounded,
                size: 16,
                color: _selectedPoi == null ? Colors.tealAccent : Colors.white70,
              ),
              label: Text(
                'All Places',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _selectedPoi == null ? Colors.tealAccent : Colors.white,
                ),
              ),
              backgroundColor:
                  _selectedPoi == null ? Colors.teal.withValues(alpha: 0.3) : const Color(0xFF1E293B),
              side: BorderSide(
                color: _selectedPoi == null ? Colors.teal : const Color(0xFF334155),
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              onPressed: _resetZoom,
            ),
            const SizedBox(width: 8),

            // Places Chips
            ...widget.pois.map((poi) {
              final isSelected = _selectedPoi?.id == poi.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ActionChip(
                  avatar: Icon(
                    poi.icon,
                    size: 16,
                    color: isSelected ? Colors.white : poi.color,
                  ),
                  label: Text(
                    poi.tag,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  backgroundColor:
                      isSelected ? poi.color : const Color(0xFF1E293B),
                  side: BorderSide(
                    color: isSelected ? Colors.white : poi.color.withValues(alpha: 0.5),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onPressed: () => _selectPoi(poi, viewportSize, mapWidth, mapHeight),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // Unclipped Responsive Overlay Info Window anchored to current screen position of pin
  Widget _buildResponsiveOverlayInfoWindow(
    MuseumPoi poi,
    Size viewportSize,
    double mapWidth,
    double mapHeight,
  ) {
    final Matrix4 matrix = _transformationController.value;
    final double scale = matrix.getMaxScaleOnAxis();
    final double tx = matrix.storage[12];
    final double ty = matrix.storage[13];

    // Compute center offset of map if centered
    final double mapLeftOffset = (viewportSize.width - mapWidth) / 2;
    final double mapTopOffset = (viewportSize.height - mapHeight) / 2;

    final double pinX = poi.dx * mapWidth;
    final double pinY = poi.dy * mapHeight;

    // Screen coordinates of the pin on top-level Stack
    final double screenPinX = (pinX * scale) + tx + (mapLeftOffset * scale);
    final double screenPinY = (pinY * scale) + ty + (mapTopOffset * scale);

    // Responsive sizing parameters
    final bool isSmallPhone = viewportSize.width < 420;
    final double cardWidth = math.min(viewportSize.width * 0.86, 320.0);
    final double maxCardHeight = viewportSize.height * 0.38;

    // Center card horizontally over pin, clamped within safe margins
    double left = screenPinX - (cardWidth / 2);
    if (left < 14) left = 14;
    if (left + cardWidth > viewportSize.width - 14) {
      left = viewportSize.width - cardWidth - 14;
    }

    // Determine vertical placement above or below pin
    bool placeAbove = screenPinY - 180 > 70;
    double top = placeAbove ? (screenPinY - 180) : (screenPinY + 28);

    // Clamp top position inside viewport
    if (top < 70) top = 70;
    if (top > viewportSize.height - 170) top = viewportSize.height - 170;

    return Positioned(
      left: left,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: cardWidth,
          child: Container(
            constraints: BoxConstraints(maxHeight: maxCardHeight),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: poi.color, width: 2),
              boxShadow: [
                BoxShadow(
                  color: poi.color.withValues(alpha: 0.35),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
                const BoxShadow(
                  color: Colors.black54,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                )
              ],
            ),
            padding: EdgeInsets.all(isSmallPhone ? 10.0 : 14.0),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row: Category tag, Icon & Close
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: poi.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(poi.icon, size: 12, color: poi.color),
                            const SizedBox(width: 4),
                            Text(
                              poi.category.toUpperCase(),
                              style: TextStyle(
                                fontSize: isSmallPhone ? 9 : 10,
                                fontWeight: FontWeight.bold,
                                color: poi.color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _dismissPoi,
                        child: const Icon(Icons.close_rounded, size: 18, color: Colors.white60),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Title of Place
                  Text(
                    poi.name,
                    style: TextStyle(
                      fontSize: isSmallPhone ? 13 : 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // Short Description Text
                  Text(
                    poi.shortDescription,
                    style: TextStyle(
                      fontSize: isSmallPhone ? 10.5 : 12,
                      color: Colors.white70,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Rating & Read More Action Button
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                          const SizedBox(width: 3),
                          Text(
                            '${poi.rating}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              fontSize: isSmallPhone ? 11 : 12,
                            ),
                          ),
                        ],
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: poi.color,
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallPhone ? 10 : 14,
                            vertical: isSmallPhone ? 4 : 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: _openSidePanel,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Read More',
                              style: TextStyle(
                                fontSize: isSmallPhone ? 10 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.arrow_forward_rounded, size: 13),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPinMarker(MuseumPoi poi, bool isSelected) {
    return AnimatedScale(
      scale: isSelected ? 1.25 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isSelected ? poi.color : const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.white : poi.color,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? poi.color : Colors.black).withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                )
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  poi.icon,
                  size: 14,
                  color: isSelected ? Colors.white : poi.color,
                ),
                const SizedBox(width: 4),
                Text(
                  poi.tag,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          CustomPaint(
            size: const Size(12, 8),
            painter: _TrianglePainter(
              color: isSelected ? poi.color : const Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRightSideDetailColumn(MuseumPoi poi, Size viewportSize) {
    final bool isSmallPhone = viewportSize.width < 400;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Close Button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0xFF1E293B),
                border: Border(bottom: BorderSide(color: Color(0xFF334155))),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: poi.color.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(poi.icon, size: 18, color: poi.color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      poi.name,
                      style: TextStyle(
                        fontSize: isSmallPhone ? 13 : 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    onPressed: _closeSidePanel,
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    tooltip: 'Close details',
                  ),
                ],
              ),
            ),

            // Detailed Content Scrollable Column
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isSmallPhone ? 14 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Banner Card
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(isSmallPhone ? 14 : 18),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            poi.color.withValues(alpha: 0.35),
                            const Color(0xFF1E293B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: poi.color.withValues(alpha: 0.4)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: poi.color,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  poi.category,
                                  style: TextStyle(
                                    fontSize: isSmallPhone ? 10 : 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${poi.rating}',
                                style: TextStyle(
                                  fontSize: isSmallPhone ? 12 : 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            poi.name,
                            style: TextStyle(
                              fontSize: isSmallPhone ? 16 : 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.location_on_rounded, size: 13, color: Colors.white60),
                              const SizedBox(width: 4),
                              Text(
                                poi.zone,
                                style: TextStyle(
                                  fontSize: isSmallPhone ? 11 : 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Hours & Quick Info
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time_filled_rounded, color: Colors.tealAccent, size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Operating Hours',
                                style: TextStyle(fontSize: 10, color: Colors.white38),
                              ),
                              Text(
                                poi.openHours,
                                style: TextStyle(
                                  fontSize: isSmallPhone ? 11.5 : 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Detailed Description Header
                    const Text(
                      'Overview',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      poi.fullDescription,
                      style: TextStyle(
                        fontSize: isSmallPhone ? 12 : 13.5,
                        color: Colors.white70,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Key Highlights List
                    const Text(
                      'Key Highlights',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...poi.highlights.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 6.0),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded, size: 16, color: poi.color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                item,
                                style: TextStyle(
                                  fontSize: isSmallPhone ? 11.5 : 12.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons Row (Google Maps style)
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: poi.color,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Navigating to ${poi.name}...'),
                                  backgroundColor: const Color(0xFF1E293B),
                                ),
                              );
                            },
                            icon: const Icon(Icons.directions_rounded, size: 16),
                            label: Text(
                              'Directions',
                              style: TextStyle(fontSize: isSmallPhone ? 11 : 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.tealAccent,
                            side: const BorderSide(color: Colors.teal),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Saved ${poi.name} to favorites!'),
                                backgroundColor: const Color(0xFF1E293B),
                              ),
                            );
                          },
                          child: const Icon(Icons.bookmark_add_rounded, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackMap(double width, double height) {
    return Container(
      width: width,
      height: height,
      color: const Color(0xFF1E293B),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.map_rounded, size: 64, color: Colors.teal),
            SizedBox(height: 12),
            Text(
              'Museum Floor Map',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) => oldDelegate.color != color;
}
