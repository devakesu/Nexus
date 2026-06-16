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

  static const List<String> languages = [
    'English',
    'Hindi',
    'Tamil',
    'Telugu',
    'Kannada',
    'Malayalam',
    'Bengali',
    'Marathi',
    'Punjabi',
    'Gujarati',
    'Urdu',
    'Spanish',
    'French',
    'German',
    'Arabic',
    'Mandarin Chinese',
    'Japanese',
    'Korean',
    'Russian',
    'Portuguese',
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
    'Human Rights',
    'Renewable Energy',
    'Arts & Culture Preservation',
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
