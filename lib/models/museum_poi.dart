import 'package:flutter/material.dart';

class MuseumPoi {
  final String id;
  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final String shortDescription;
  final String fullDescription;
  final double dx; // Normalized X coordinate on map (0.0 to 1.0)
  final double dy; // Normalized Y coordinate on map (0.0 to 1.0)
  final double rating;
  final String openHours;
  final String zone;
  final List<String> highlights;
  final String tag;

  const MuseumPoi({
    required this.id,
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    required this.shortDescription,
    required this.fullDescription,
    required this.dx,
    required this.dy,
    required this.rating,
    required this.openHours,
    required this.zone,
    required this.highlights,
    required this.tag,
  });

  static List<MuseumPoi> get samplePois => [
        MuseumPoi(
          id: 'hospital',
          name: 'Medical & First Aid Center',
          category: 'Health & Safety',
          icon: Icons.local_hospital_rounded,
          color: const Color(0xFFEF4444),
          shortDescription:
              'Fully equipped 24/7 medical station with certified emergency medical personnel.',
          fullDescription:
              'The Museum First Aid Center provides emergency medical care, quiet rest rooms, health monitoring, and immediate basic care. Qualified nursing staff are present during all operating hours. Automatic external defibrillators (AED) and sanitation supplies are available here.',
          dx: 0.28,
          dy: 0.24,
          rating: 4.9,
          openHours: '9:00 AM - 6:00 PM Daily',
          zone: 'West Wing - Level 1',
          highlights: [
            '24/7 Paramedic Staff',
            'Wheelchair & Stretcher Ready',
            'AED & Basic Care Kits',
            'Quiet Rest Area'
          ],
          tag: 'HOSPITAL',
        ),
        MuseumPoi(
          id: 'zoo',
          name: 'Wildlife Zoo & Habitat',
          category: 'Animals & Nature',
          icon: Icons.pets_rounded,
          color: const Color(0xFF10B981),
          shortDescription:
              'Interactive animal sanctuary showcasing exotic species, tropical birds, and live feeding sessions.',
          fullDescription:
              'Step into an immersive natural habitat featuring over 150 species of flora and fauna. Walk through the tropical rainforest aviary, observe nocturnal species in the twilight exhibit, and attend live educational feeding demonstrations hosted daily by expert zoologists.',
          dx: 0.72,
          dy: 0.20,
          rating: 4.8,
          openHours: '9:30 AM - 5:30 PM',
          zone: 'North Pavilion - Outdoor Area',
          highlights: [
            'Live Feeding Demos (11am & 3pm)',
            'Interactive Petting Area',
            'Butterfly Canopy Walk',
            'Guided Eco-Tours'
          ],
          tag: 'ZOO',
        ),
        MuseumPoi(
          id: 'dino',
          name: 'Dinosaur Hall & Fossil Lab',
          category: 'Prehistoric History',
          icon: Icons.cruelty_free_rounded,
          color: const Color(0xFFF59E0B),
          shortDescription:
              'Enormous T-Rex skeleton, interactive fossil dig pits, and animatronic jurassic creatures.',
          fullDescription:
              'Journey millions of years back in time! The Dinosaur Hall features world-renowned fossil discoveries, including a 40-foot Tyrannosaurus Rex skeleton, real dinosaur footprints, and a working paleontology laboratory where visitors can watch scientists uncover ancient fossils.',
          dx: 0.35,
          dy: 0.48,
          rating: 4.95,
          openHours: '9:00 AM - 6:00 PM',
          zone: 'Central Hall - Ground Floor',
          highlights: [
            'Real T-Rex Skeleton Exhibit',
            'Fossil Dig Sandbox for Kids',
            '3D Animatronic Show',
            'Paleontology Lab View'
          ],
          tag: 'FOSSILS',
        ),
        MuseumPoi(
          id: 'science',
          name: 'Science & Robotics Lab',
          category: 'Technology & Physics',
          icon: Icons.science_rounded,
          color: const Color(0xFF3B82F6),
          shortDescription:
              'Hands-on physics experiments, humanoid robotics demonstrations, and virtual space travel.',
          fullDescription:
              'Experience the power of modern innovation and space exploration! Engage with hands-on physics simulators, witness humanoid robots perform complex tasks, test energy experiments, and sit inside a realistic Apollo moon mission flight simulator.',
          dx: 0.76,
          dy: 0.52,
          rating: 4.85,
          openHours: '10:00 AM - 6:00 PM',
          zone: 'East Wing - Level 2',
          highlights: [
            'Interactive Robot Demos',
            'VR Space Flight Simulator',
            'Physics Experiment Stations',
            '3D Printing Workshops'
          ],
          tag: 'SCIENCE',
        ),
        MuseumPoi(
          id: 'art',
          name: 'Fine Art & Sculpture Gallery',
          category: 'Culture & Art',
          icon: Icons.palette_rounded,
          color: const Color(0xFF8B5CF6),
          shortDescription:
              'Masterpieces from Renaissance masters alongside contemporary digital art installations.',
          fullDescription:
              'Housing over 500 classical and contemporary works, the Fine Art Gallery displays rare oil paintings, marble statues, and immersive 360-degree digital projection rooms that bring historic artworks to life through modern technology.',
          dx: 0.22,
          dy: 0.72,
          rating: 4.75,
          openHours: '9:00 AM - 6:00 PM',
          zone: 'South Wing - Level 1',
          highlights: [
            'Renaissance Masterpieces',
            '360° Light & Sound Immersion',
            'Sculpture Courtyard',
            'Curated Audio Guide'
          ],
          tag: 'ART',
        ),
        MuseumPoi(
          id: 'cafe',
          name: 'Garden Cafeteria & Lounge',
          category: 'Dining & Food',
          icon: Icons.restaurant_rounded,
          color: const Color(0xFFEC4899),
          shortDescription:
              'Artisanal coffee, gourmet sandwiches, fresh pastries, and comfortable courtyard seating.',
          fullDescription:
              'Recharge your energy at the Garden Cafeteria! Serving freshly brewed specialty espresso, organic salads, chef-curated hot meals, and a delicious selection of pastries. Free high-speed Wi-Fi and mobile device charging hubs are available at every table.',
          dx: 0.68,
          dy: 0.76,
          rating: 4.6,
          openHours: '8:30 AM - 5:30 PM',
          zone: 'Courtyard Terrace',
          highlights: [
            'Fresh Artisanal Coffee & Pastries',
            'Vegan & Gluten-Free Options',
            'High-Speed Wi-Fi & Power Hubs',
            'Scenic Terrace View'
          ],
          tag: 'CAFE',
        ),
        MuseumPoi(
          id: 'giftshop',
          name: 'Museum Gift Shop & Store',
          category: 'Souvenirs & Books',
          icon: Icons.shopping_bag_rounded,
          color: const Color(0xFF06B6D4),
          shortDescription:
              'Official museum souvenirs, educational science kits, art prints, and custom apparel.',
          fullDescription:
              'Take a piece of history home with you! The Gift Shop features custom museum merchandise, rare books, art prints, replica fossils, gemstone jewelry, and educational science kits perfect for young explorers.',
          dx: 0.48,
          dy: 0.88,
          rating: 4.7,
          openHours: '9:00 AM - 6:30 PM',
          zone: 'Main Entrance Lobby',
          highlights: [
            'Official Replica Artifacts',
            'Science & History Books',
            'Kids STEM Toy Kits',
            'Custom Apparel & Mugs'
          ],
          tag: 'GIFTS',
        ),
      ];
}
