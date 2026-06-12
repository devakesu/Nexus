import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class SubInterest {
  final String name;
  const SubInterest(this.name);
}

class ParentInterest {
  final String name;
  final List<String> subInterests;
  const ParentInterest({required this.name, required this.subInterests});
}

class InterestCategory {
  final String name;
  final IconData icon;
  final List<ParentInterest> parents;
  const InterestCategory({
    required this.name,
    required this.icon,
    required this.parents,
  });
}

// Complete static hierarchy of hundreds of interests and sub-interests
const List<InterestCategory> interestsCategories = [
  InterestCategory(
    name: 'Tech & Science',
    icon: LucideIcons.cpu,
    parents: [
      ParentInterest(
        name: 'Coding',
        subInterests: [
          'Python',
          'Flutter & Dart',
          'Rust',
          'Web Development',
          'AI & Machine Learning',
          'Cybersecurity',
          'Game Development',
          'Cloud & DevOps',
          'Open Source Contribution',
          'Mobile Apps',
        ],
      ),
      ParentInterest(
        name: 'Science & Discovery',
        subInterests: [
          'Astrophysics & Space',
          'Quantum Physics',
          'Neuroscience',
          'Psychology',
          'Marine Biology',
          'Archaeology & History',
          'Genetics & Biotech',
          'Climate Science',
        ],
      ),
      ParentInterest(
        name: 'Gadgets & Hardware',
        subInterests: [
          'PC Building',
          'Virtual Reality (VR)',
          'Drones & Quadcopters',
          'IoT & Smart Home',
          'Mechanical Keyboards',
          '3D Printing',
          'Robotics',
        ],
      ),
      ParentInterest(
        name: 'Math & Logic',
        subInterests: [
          'Cryptography',
          'Data Analysis',
          'Game Theory',
          'Mathematical Puzzles',
          'Algorithms',
        ],
      ),
    ],
  ),
  InterestCategory(
    name: 'Entertainment & Media',
    icon: LucideIcons.film,
    parents: [
      ParentInterest(
        name: 'Watching TV & Series',
        subInterests: [
          'Horror Shows',
          'Sci-Fi & Fantasy',
          'Documentaries',
          'True Crime',
          'Sitcoms & Comedy',
          'K-Dramas',
          'Anime & Manga',
          'Reality TV',
          'Historical Drama',
          'Talk Shows',
        ],
      ),
      ParentInterest(
        name: 'Movies & Cinema',
        subInterests: [
          'Indie & Art House',
          'Hollywood Blockbusters',
          'Classic Films',
          'Psychological Thrillers',
          'Animation & Pixar',
          'Foreign Language Films',
          'Action & Adventure',
        ],
      ),
      ParentInterest(
        name: 'Gaming',
        subInterests: [
          'RPGs (Role-Playing)',
          'FPS (First-Person)',
          'RTS (Strategy)',
          'MMORPGs',
          'Cozy & Casual Games',
          'Competitive Esports',
          'Retro & Arcade',
          'Tabletop & D&D',
          'Modern Board Games',
        ],
      ),
      ParentInterest(
        name: 'Music & Sound',
        subInterests: [
          'Rock & Metal',
          'Pop & R&B',
          'Hip Hop & Rap',
          'Indie & Folk',
          'Classical & Jazz',
          'EDM & Synthwave',
          'Lo-Fi & Chillbeats',
          'Podcasts & Audiobooks',
          'Vinyl Records',
        ],
      ),
    ],
  ),
  InterestCategory(
    name: 'Sports & Outdoors',
    icon: LucideIcons.trophy,
    parents: [
      ParentInterest(
        name: 'Fitness & Training',
        subInterests: [
          'Weightlifting',
          'Powerlifting',
          'CrossFit',
          'Calisthenics',
          'Yoga & Pilates',
          'HIIT & Cardio',
          'Spinning & Cycling',
          'Gymnastics',
        ],
      ),
      ParentInterest(
        name: 'Team Sports',
        subInterests: [
          'Football (Soccer)',
          'Basketball',
          'Volleyball',
          'Baseball',
          'Cricket',
          'American Football',
          'Rugby',
          'Ice Hockey',
        ],
      ),
      ParentInterest(
        name: 'Individual Sports',
        subInterests: [
          'Tennis',
          'Badminton',
          'Table Tennis',
          'Golf',
          'Archery',
          'Fencing',
          'Billiards & Pool',
        ],
      ),
      ParentInterest(
        name: 'Water & Winter Sports',
        subInterests: [
          'Swimming & Diving',
          'Surfing & Bodyboarding',
          'Kayaking & Paddle',
          'Scuba Diving',
          'Skiing',
          'Snowboarding',
          'Ice Skating',
        ],
      ),
      ParentInterest(
        name: 'Outdoor Adventure',
        subInterests: [
          'Hiking & Trekking',
          'Rock Climbing',
          'Camping & Bushcraft',
          'Backpacking',
          'Mountaineering',
          'Trail Running',
          'Geocaching',
        ],
      ),
    ],
  ),
  InterestCategory(
    name: 'Creative & Arts',
    icon: LucideIcons.palette,
    parents: [
      ParentInterest(
        name: 'Visual Arts',
        subInterests: [
          'Watercolor Painting',
          'Oil & Acrylics',
          'Sketching & Charcoal',
          'Digital Illustration',
          'Calligraphy',
          'Pottery & Ceramics',
          'Origami & Papercraft',
        ],
      ),
      ParentInterest(
        name: 'Design & Styling',
        subInterests: [
          'UI/UX Design',
          'Graphic Design',
          'Fashion & Apparel',
          'Interior Design',
          '3D Modeling',
          'Architecture',
        ],
      ),
      ParentInterest(
        name: 'Photography & Video',
        subInterests: [
          'Landscape & Nature',
          'Portrait & Studio',
          'Street & Documentary',
          'Film & Analog',
          'Drone Videography',
          'Video Editing',
        ],
      ),
      ParentInterest(
        name: 'Performing Arts',
        subInterests: [
          'Dancing',
          'Acting & Theater',
          'Musical Instruments',
          'Singing & Vocals',
          'Stand-up & Improv',
        ],
      ),
      ParentInterest(
        name: 'Writing & Literature',
        subInterests: [
          'Creative Writing',
          'Poetry & Prose',
          'Blogging & Journalism',
          'Journaling',
        ],
      ),
    ],
  ),
  InterestCategory(
    name: 'Food & Drink',
    icon: LucideIcons.coffee,
    parents: [
      ParentInterest(
        name: 'Cooking & Culinary',
        subInterests: [
          'Baking & Pastry',
          'Sourdough Bread',
          'BBQ & Grilling',
          'Vegan & Vegetarian',
          'Fine Dining',
          'Fermentation',
          'Meal Prep & Nutrition',
        ],
      ),
      ParentInterest(
        name: 'Beverages',
        subInterests: [
          'Specialty Coffee',
          'Matcha & Green Tea',
          'Loose Leaf Tea',
          'Wine Tasting',
          'Craft Beer Brewing',
          'Mixology & Cocktails',
        ],
      ),
    ],
  ),
  InterestCategory(
    name: 'Lifestyle & Hobbies',
    icon: LucideIcons.sparkles,
    parents: [
      ParentInterest(
        name: 'Nature & Gardening',
        subInterests: [
          'Houseplants',
          'Bonsai Trees',
          'Vegetable Gardening',
          'Aquascaping',
          'Foraging & Herbalism',
        ],
      ),
      ParentInterest(
        name: 'Mind & Wellness',
        subInterests: [
          'Meditation',
          'Philosophy',
          'Astrology & Tarot',
          'Self-Improvement',
          'Volunteering',
        ],
      ),
      ParentInterest(
        name: 'Fashion & Collecting',
        subInterests: [
          'Vintage & Thrifting',
          'Sneaker Culture',
          'Streetwear',
          'Watch Collecting',
          'Book Collecting',
        ],
      ),
      ParentInterest(
        name: 'Pets & Animals',
        subInterests: [
          'Dogs & Dog Training',
          'Cats & Felines',
          'Reptiles',
          'Aquariums & Fish',
          'Bird Watching',
        ],
      ),
    ],
  ),
];

class InterestsOverlay extends StatefulWidget {
  final List<String> initialSelected;
  final ValueChanged<List<String>> onSave;

  const InterestsOverlay({
    required this.initialSelected,
    required this.onSave,
    super.key,
  });

  @override
  State<InterestsOverlay> createState() => _InterestsOverlayState();
}

class _InterestsOverlayState extends State<InterestsOverlay> {
  late List<String> _selectedInterests;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Track expanded state of parent interests
  final Map<String, bool> _expandedParents = {};

  @override
  void initState() {
    super.initState();
    _selectedInterests = List<String>.from(widget.initialSelected);
    // Initialize search controller listener
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  String _getEmojiForInterest(String interest) {
    switch (interest) {
      // Tech & Science
      case 'Python': return '🐍';
      case 'Flutter & Dart': return '💙';
      case 'Rust': return '🦀';
      case 'Web Development': return '🌐';
      case 'AI & Machine Learning': return '🤖';
      case 'Cybersecurity': return '🔒';
      case 'Game Development': return '🎮';
      case 'Cloud & DevOps': return '☁️';
      case 'Open Source Contribution': return '🐙';
      case 'Mobile Apps': return '📱';
      case 'Astrophysics & Space': return '🚀';
      case 'Quantum Physics': return '⚛️';
      case 'Neuroscience': return '🧠';
      case 'Psychology': return '💭';
      case 'Marine Biology': return '🐬';
      case 'Archaeology & History': return '🏛️';
      case 'Genetics & Biotech': return '🧬';
      case 'Climate Science': return '🌍';
      case 'PC Building': return '🖥️';
      case 'Virtual Reality (VR)': return '🕶️';
      case 'Drones & Quadcopters': return '🛸';
      case 'IoT & Smart Home': return '🏠';
      case 'Mechanical Keyboards': return '⌨️';
      case '3D Printing': return '🖨️';
      case 'Robotics': return '🤖';
      case 'Cryptography': return '🔐';
      case 'Data Analysis': return '📊';
      case 'Game Theory': return '🎲';
      case 'Mathematical Puzzles': return '🧩';
      case 'Algorithms': return '🧮';

      // Entertainment & Media
      case 'Horror Shows': return '👻';
      case 'Sci-Fi & Fantasy': return '🦄';
      case 'Documentaries': return '📽️';
      case 'True Crime': return '🕵️';
      case 'Sitcoms & Comedy': return '🎭';
      case 'K-Dramas': return '🇰🇷';
      case 'Anime & Manga': return '🌸';
      case 'Reality TV': return '📺';
      case 'Historical Drama': return '👑';
      case 'Talk Shows': return '🎙️';
      case 'Indie & Art House': return '🎨';
      case 'Hollywood Blockbusters': return '🍿';
      case 'Classic Films': return '🎞️';
      case 'Psychological Thrillers': return '🕵️‍♀️';
      case 'Animation & Pixar': return '🧸';
      case 'Foreign Language Films': return '🗣️';
      case 'Action & Adventure': return '🤠';
      case 'RPGs (Role-Playing)': return '🧙';
      case 'FPS (First-Person)': return '🔫';
      case 'RTS (Strategy)': return '♟️';
      case 'MMORPGs': return '🌐';
      case 'Cozy & Casual Games': return '☕';
      case 'Competitive Esports': return '🏆';
      case 'Retro & Arcade': return '👾';
      case 'Tabletop & D&D': return '🎲';
      case 'Modern Board Games': return '♟️';
      case 'Rock & Metal': return '🎸';
      case 'Pop & R&B': return '🎤';
      case 'Hip Hop & Rap': return '🎧';
      case 'Indie & Folk': return '🪕';
      case 'Classical & Jazz': return '🎷';
      case 'EDM & Synthwave': return '🎹';
      case 'Lo-Fi & Chillbeats': return '💤';
      case 'Podcasts & Audiobooks': return '🎙️';
      case 'Vinyl Records': return '📻';

      // Sports & Outdoors
      case 'Weightlifting': return '🏋️';
      case 'Powerlifting': return '💪';
      case 'CrossFit': return '🤸';
      case 'Calisthenics': return '🤸‍♀️';
      case 'Yoga & Pilates': return '🧘';
      case 'HIIT & Cardio': return '🏃';
      case 'Spinning & Cycling': return '🚴';
      case 'Gymnastics': return '🤸‍♂️';
      case 'Football (Soccer)': return '⚽';
      case 'Basketball': return '🏀';
      case 'Volleyball': return '🏐';
      case 'Baseball': return '⚾';
      case 'Cricket': return '🏏';
      case 'American Football': return '🏈';
      case 'Rugby': return '🏉';
      case 'Ice Hockey': return '🏒';
      case 'Tennis': return '🎾';
      case 'Badminton': return '🏸';
      case 'Table Tennis': return '🏓';
      case 'Golf': return '⛳';
      case 'Archery': return '🏹';
      case 'Fencing': return '🤺';
      case 'Billiards & Pool': return '🎱';
      case 'Swimming & Diving': return '🏊';
      case 'Surfing & Bodyboarding': return '🏄';
      case 'Kayaking & Paddle': return '🛶';
      case 'Scuba Diving': return '🤿';
      case 'Skiing': return '🎿';
      case 'Snowboarding': return '🏂';
      case 'Ice Skating': return '⛸️';
      case 'Hiking & Trekking': return '🥾';
      case 'Rock Climbing': return '🧗';
      case 'Camping & Bushcraft': return '🔥';
      case 'Backpacking': return '🎒';
      case 'Mountaineering': return '🏔️';
      case 'Trail Running': return '🏃‍♂️';
      case 'Geocaching': return '📍';

      // Creative & Arts
      case 'Watercolor Painting': return '🎨';
      case 'Oil & Acrylics': return '🖌️';
      case 'Sketching & Charcoal': return '✏️';
      case 'Digital Illustration': return '🖥️';
      case 'Calligraphy': return '✒️';
      case 'Pottery & Ceramics': return '🏺';
      case 'Origami & Papercraft': return '📄';
      case 'UI/UX Design': return '🎨';
      case 'Graphic Design': return '📐';
      case 'Fashion & Apparel': return '👕';
      case 'Interior Design': return '🛋️';
      case '3D Modeling': return '💻';
      case 'Architecture': return '🏛️';
      case 'Landscape & Nature': return '🌅';
      case 'Portrait & Studio': return '📸';
      case 'Street & Documentary': return '📷';
      case 'Film & Analog': return '🎞️';
      case 'Drone Videography': return '🛸';
      case 'Video Editing': return '🎬';
      case 'Dancing': return '💃';
      case 'Acting & Theater': return '🎭';
      case 'Musical Instruments': return '🎹';
      case 'Singing & Vocals': return '🎤';
      case 'Stand-up & Improv': return '🎙️';
      case 'Creative Writing': return '✍️';
      case 'Poetry & Prose': return '📜';
      case 'Blogging & Journalism': return '📰';
      case 'Journaling': return '📓';

      // Food & Drink
      case 'Baking & Pastry': return '🥐';
      case 'Sourdough Bread': return '🍞';
      case 'BBQ & Grilling': return '🍖';
      case 'Vegan & Vegetarian': return '🥗';
      case 'Fine Dining': return '🍽️';
      case 'Fermentation': return '🍶';
      case 'Meal Prep & Nutrition': return '🥦';
      case 'Specialty Coffee': return '☕';
      case 'Matcha & Green Tea': return '🍵';
      case 'Loose Leaf Tea': return '🍃';
      case 'Wine Tasting': return '🍷';
      case 'Craft Beer Brewing': return '🍺';
      case 'Mixology & Cocktails': return '🍹';

      // Interests - Lifestyle & Hobbies
      case 'Houseplants': return '🌿';
      case 'Bonsai Trees': return '🪴';
      case 'Vegetable Gardening': return '🥕';
      case 'Aquascaping': return '🐠';
      case 'Foraging & Herbalism': return '🍄';
      case 'Meditation': return '🧘';
      case 'Philosophy': return '📚';
      case 'Astrology & Tarot': return '🔮';
      case 'Self-Improvement': return '📈';
      case 'Volunteering': return '🤝';
      case 'Vintage & Thrifting': return '🧥';
      case 'Sneaker Culture': return '👟';
      case 'Streetwear': return '🧢';
      case 'Watch Collecting': return '⌚';
      case 'Book Collecting': return '📚';
      case 'Dogs & Dog Training': return '🦮';
      case 'Cats & Felines': return '🐈';
      case 'Reptiles': return '🦎';
      case 'Aquariums & Fish': return '🐠';
      case 'Bird Watching': return '🦤';

      default: return '';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleInterest(String parentName, String subInterestName) {
    final value = '$parentName: $subInterestName';
    setState(() {
      if (_selectedInterests.contains(value)) {
        _selectedInterests.remove(value);
      } else {
        _selectedInterests.add(value);
      }
    });
  }

  bool _isInterestSelected(String parentName, String subInterestName) {
    return _selectedInterests.contains('$parentName: $subInterestName');
  }

  @override
  Widget build(BuildContext context) {
    const pulsarPink = Color(0xFFFF7597);
    const deepPurple = Color(0xFF7C3AED);
    const bgDark = Color(0xFF0F131E);

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: Column(
          children: [
            // Gorgeous Header with Search
            _buildHeader(pulsarPink, deepPurple),

            // Main Body: Search Results or Categories Tree
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults(pulsarPink, deepPurple)
                  : _buildCategoriesTree(pulsarPink, deepPurple),
            ),

            // Bottom Actions Bar
            _buildBottomBar(pulsarPink, deepPurple),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Color pulsarPink, Color deepPurple) {
    return Container(
      padding: const EdgeInsets.only(top: 16, left: 20, right: 20, bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26).withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(LucideIcons.arrowLeft, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                'Affinity & Interests',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 48), // Spacer to balance back button
            ],
          ),
          const SizedBox(height: 16),
          // Futuristic Glass Search Box
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  LucideIcons.search,
                  color: Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Outfit',
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search hundreds of interests...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                    },
                    child: const Icon(
                      LucideIcons.x,
                      color: Colors.white70,
                      size: 16,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(Color pulsarPink, Color deepPurple) {
    // Find all sub-interests matching the search query
    final List<Map<String, String>> matches = [];
    for (final cat in interestsCategories) {
      for (final parent in cat.parents) {
        for (final sub in parent.subInterests) {
          if (sub.toLowerCase().contains(_searchQuery) ||
              parent.name.toLowerCase().contains(_searchQuery) ||
              cat.name.toLowerCase().contains(_searchQuery)) {
            matches.add({
              'category': cat.name,
              'parent': parent.name,
              'sub': sub,
            });
          }
        }
      }
    }

    if (matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              LucideIcons.searchCode,
              color: Colors.white24,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'No matches found for "$_searchQuery"',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 14,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: matches.length,
      itemBuilder: (context, index) {
        final match = matches[index];
        final isSelected = _isInterestSelected(match['parent']!, match['sub']!);

        return GestureDetector(
          onTap: () => _toggleInterest(match['parent']!, match['sub']!),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? deepPurple.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? pulsarPink.withValues(alpha: 0.8)
                    : Colors.white.withValues(alpha: 0.08),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (_getEmojiForInterest(match['sub']!).isNotEmpty) ...[
                            Text(
                              _getEmojiForInterest(match['sub']!),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            match['sub']!,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                              fontSize: 15,
                              fontWeight:
                                  isSelected ? FontWeight.bold : FontWeight.w500,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${match['category']} • ${match['parent']}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(
                    LucideIcons.check,
                    color: pulsarPink,
                    size: 18,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoriesTree(Color pulsarPink, Color deepPurple) {
    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: interestsCategories.length,
      itemBuilder: (context, index) {
        final category = interestsCategories[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.05),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Category Header
              Row(
                children: [
                  Icon(category.icon, color: pulsarPink, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    category.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                      fontFamily: 'Outfit',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Parent Interests list under this Category
              ...category.parents.map((parent) {
                final isExpanded = _expandedParents[parent.name] ?? false;

                // Count how many are selected in this parent interest group
                final int selectedCount = parent.subInterests
                    .where((sub) => _isInterestSelected(parent.name, sub))
                    .length;

                return Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _expandedParents[parent.name] = !isExpanded;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isExpanded
                              ? deepPurple.withValues(alpha: 0.1)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isExpanded
                                ? deepPurple.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  parent.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                                if (selectedCount > 0) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: pulsarPink.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color:
                                            pulsarPink.withValues(alpha: 0.4),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      '$selectedCount',
                                      style: TextStyle(
                                        color: pulsarPink,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Icon(
                              isExpanded
                                  ? LucideIcons.chevronUp
                                  : LucideIcons.chevronDown,
                              color: Colors.white60,
                              size: 16,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isExpanded)
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 8,
                          right: 8,
                          top: 8,
                          bottom: 12,
                        ),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: parent.subInterests.map((subInterest) {
                            final isSelected =
                                _isInterestSelected(parent.name, subInterest);
                            return FilterChip(
                              label: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_getEmojiForInterest(subInterest).isNotEmpty) ...[
                                    Text(
                                      _getEmojiForInterest(subInterest),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Text(
                                    subInterest,
                                    style: TextStyle(
                                      color:
                                          isSelected ? Colors.white : Colors.white70,
                                      fontSize: 12,
                                      fontFamily: 'Outfit',
                                    ),
                                  ),
                                ],
                              ),
                              selected: isSelected,
                              selectedColor: deepPurple.withValues(alpha: 0.3),
                              checkmarkColor: pulsarPink,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.03),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isSelected
                                      ? pulsarPink.withValues(alpha: 0.6)
                                      : Colors.white.withValues(alpha: 0.1),
                                  width: isSelected ? 1.2 : 0.8,
                                ),
                              ),
                              onSelected: (_) =>
                                  _toggleInterest(parent.name, subInterest),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar(Color pulsarPink, Color deepPurple) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B26).withValues(alpha: 0.8),
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_selectedInterests.length} Selected',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Affinities to map',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                ),
              ),
            ],
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 4,
              shadowColor: deepPurple.withValues(alpha: 0.4),
            ).copyWith(
              side: WidgetStateProperty.all(
                BorderSide(color: pulsarPink, width: 0.8),
              ),
            ),
            onPressed: () {
              widget.onSave(_selectedInterests);
              Navigator.pop(context);
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Save Alignments',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Outfit',
                  ),
                ),
                SizedBox(width: 8),
                Icon(LucideIcons.save, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
