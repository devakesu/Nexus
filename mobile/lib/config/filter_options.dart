import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class ParentInterest {
  const ParentInterest({required this.name, required this.subInterests});
  final String name;
  final List<String> subInterests;
}

class InterestCategory {
  const InterestCategory({
    required this.name,
    required this.icon,
    required this.parents,
  });
  final String name;
  final IconData icon;
  final List<ParentInterest> parents;
}

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

abstract final class FilterOptions {
  static const List<String> drinking = [
    'Never',
    'Occasionally',
    'Socially',
    'Regularly',
  ];

  static const List<String> smoking = [
    'Never',
    'Occasionally',
    'Socially',
    'Regularly',
  ];

  static const List<String> childrenPlans = [
    'Want kids',
    "Don't want kids",
    'Undecided',
    'Not specified',
  ];

  static const List<String> religiousBeliefs = [
    'Atheist',
    'Agnostic',
    'Spiritual',
    'Christian',
    'Muslim',
    'Jewish',
    'Hindu',
    'Buddhist',
    'Sikh',
    'Jain',
    'Other',
    'Not specified',
  ];

  static const List<String> genderOptions = [
    'Man',
    'Woman',
    'Non-binary',
    'Genderqueer',
    'Genderfluid',
    'Agender',
    'Transgender Man',
    'Transgender Woman',
    'Gender Non-Conforming',
    'Pangender',
    'Androgynous',
    'Neutrois',
    'Third Gender',
    'Intersex',
    'Bigender',
    'Two-Spirit',
    'Demiboy',
    'Demigirl',
    'Queer',
    'Questioning',
    'Prefer not to say',
  ];

  static const List<String> sexualityOptions = [
    'Straight',
    'Gay',
    'Lesbian',
    'Bisexual',
    'Pansexual',
    'Asexual',
    'Aromantic',
    'Greysexual',
    'Polysexual',
    'Omnisexual',
    'Fluid',
    'Skoliosexual',
    'Demisexual',
    'Queer',
    'Questioning',
    'Prefer not to say',
  ];

  static const List<String> pronounOptions = [
    'he/him',
    'she/her',
    'they/them',
    'he/they',
    'she/they',
    'it/its',
    'any/all',
    'xe/xem',
    'fae/faer',
    'Prefer not to say',
  ];

  static const List<String> languages = [
    'English',
    'Spanish',
    'Mandarin Chinese',
    'Hindi',
    'Arabic',
    'Portuguese',
    'Bengali',
    'Russian',
    'Japanese',
    'Punjabi',
    'German',
    'Javanese',
    'Wu Chinese',
    'Malay',
    'Telugu',
    'Vietnamese',
    'Korean',
    'French',
    'Marathi',
    'Tamil',
    'Cantonese',
    'Turkish',
    'Urdu',
    'Italian',
    'Thai',
    'Persian',
    'Polish',
    'Kannada',
    'Ukrainian',
    'Filipino',
    'Gujarati',
    'Romanian',
    'Greek',
    'Czech',
    'Swedish',
    'Dutch',
    'Hungarian',
    'Zulu',
    'Hebrew',
    'Finnish',
    'Norwegian',
    'Danish',
    'Swahili',
    'Malayalam',
    'Amharic',
    'Yoruba',
    'Oromo',
    'Igbo',
    'Burmese',
    'Azerbaijani',
    'Maithili',
    'Uzbek',
    'Sindhi',
    'Pashto',
    'Kurdish',
    'Sinhala',
    'Somali',
    'Tagalog',
    'Nepali',
    'Khmer',
    'Lao',
    'Assamese',
    'Malagasy',
    'Slovak',
    'Bulgarian',
    'Croatian',
    'Serbian',
    'Lithuanian',
    'Latvian',
    'Estonian',
    'Slovenian',
    'Irish',
    'Welsh',
    'Icelandic',
    'Catalan',
    'Basque',
    'Galician',
    'Textile',
  ];

  /// Dating tab — maps to `dating_for` TEXT[] column codes.
  static const List<Map<String, String>> datingForOptions = [
    {'code': 'short', 'label': 'Short-term'},
    {'code': 'long', 'label': 'Long-term'},
    {'code': 'casual', 'label': 'Casual Dating'},
    {'code': 'fling', 'label': 'Fling'},
    {'code': 'hookups', 'label': 'Hookups'},
    {'code': 'fwb', 'label': 'Friends w/ Benefits'},
    {'code': 'monogamous', 'label': 'Monogamous'},
    {'code': 'polyamorous', 'label': 'Polyamorous'},
    {'code': 'open_rel', 'label': 'Open Relationship'},
    {'code': 'marriage', 'label': 'Marriage-minded'},
    {'code': 'platonic', 'label': 'Platonic'},
    {'code': 'unsure', 'label': 'Figuring it out'},
  ];

  /// Professional tab — maps to encrypted `looking_for` list field.
  static const List<Map<String, String>> lookingForOptions = [
    {'code': 'networking', 'label': 'Networking'},
    {'code': 'mentorship', 'label': 'Mentorship'},
    {'code': 'cofounder', 'label': 'Co-founder'},
    {'code': 'freelance', 'label': 'Freelance'},
    {'code': 'internship', 'label': 'Internship'},
    {'code': 'long', 'label': 'Long-term role'},
    {'code': 'short', 'label': 'Short-term project'},
  ];

  /// Dating tab — show who filter (maps to candidate search_bucket values).
  static const List<Map<String, String>> searchBuckets = [
    {'code': 'M', 'label': 'Men'},
    {'code': 'F', 'label': 'Women'},
    {'code': 'NB', 'label': 'Non-binary'},
  ];

  static const List<String> partnerValues = [
    'Authenticity',
    'Empathy',
    'Ambition',
    'Loyalty',
    'Honesty',
    'Kindness',
    'Growth Mindset',
    'Creativity',
    'Emotional Maturity',
    'Humor & Wit',
    'Respect',
    'Adventure',
    'Communication',
    'Curiosity',
    'Compassion',
    'Family-oriented',
    'Financial Stability',
    'Independence',
    'Open-mindedness',
    'Self-awareness',
    'Trustworthiness',
  ];

  static const List<String> causesSupported = [
    'Climate Action',
    'Tech Ethics',
    'Mental Health',
    'LGBTQ+ Rights',
    'Education Access',
    'Animal Protection',
    'Disaster Relief',
    'Poverty Alleviation',
    'Gender Equality',
    'Scientific Research',
    'Mental Health Advocacy',
    'Human Rights',
    'Clean Water & Sanitation',
    'Renewable Energy',
    'Economic Development',
    'Arts & Culture Preservation',
  ];

  static const List<String> pets = [
    'Dog',
    'Cat',
    'Fish',
    'Bird',
    'Rabbit',
    'Hamster',
    'Guinea Pig',
    'Ferret',
    'Reptile',
    'Amphibian',
    'Horse',
    'Chicken',
    'Sugar Glider',
    'Chinchilla',
    'Hedgehog',
    'No Pets',
  ];

  static const List<String> techSkills = [
    'AI/ML',
    'Web Dev',
    'Mobile Dev',
    'Backend',
    'Cloud/DevOps',
    'Data Science',
    'Cybersecurity',
    'Blockchain',
    'Game Dev',
    'UI/UX',
    'Embedded Systems',
    'Open Source',
  ];

  /// Flat sub-interest values for filtering.
  /// Must match values stored as dict values inside the sub_interests field.
  static const List<String> subInterests = [
    'Photography',
    'Hiking',
    'Gaming',
    'Cooking',
    'Reading',
    'Fitness',
    'Travel',
    'Music',
    'Art',
    'Dance',
    'Theatre',
    'Yoga',
    'Cycling',
    'Swimming',
    'Running',
    'Football',
    'Cricket',
    'Chess',
    'Coding',
    'Startups',
    'Finance',
    'Writing',
    'Podcasting',
    'Films',
    'Anime',
    'Fashion',
    'Sustainability',
    'Volunteering',
  ];
}
