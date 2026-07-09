String getEmojiForTag(String tag) {
  final cleanTag = tag.contains(': ') ? tag.split(': ')[1] : tag;
  switch (cleanTag) {
    // Genders
    case 'Man':
      return '👨';
    case 'Woman':
      return '👩';
    case 'Non-binary':
      return '⚧️';
    case 'Genderqueer':
      return '💜';
    case 'Genderfluid':
      return '💧';
    case 'Agender':
      return '⚪';
    case 'Transgender Man':
      return '🏳️‍⚧️';
    case 'Transgender Woman':
      return '🏳️‍⚧️';
    case 'Gender Non-Conforming':
      return '🦄';
    case 'Pangender':
      return '🌀';
    case 'Androgynous':
      return '👤';
    case 'Neutrois':
      return '⚪';
    case 'Third Gender':
      return '🔱';
    case 'Intersex':
      return '🟡';
    case 'Bigender':
      return '👥';
    case 'Two-Spirit':
      return '🪶';
    case 'Demiboy':
      return '👦';
    case 'Demigirl':
      return '👧';
    case 'Queer':
      return '🌈';
    case 'Questioning':
      return '❓';
    case 'Prefer not to say':
      return '🤫';

    // Sexualities
    case 'Straight':
      return '👫';
    case 'Gay':
      return '👨‍❤️‍👨';
    case 'Lesbian':
      return '👩‍❤️‍👩';
    case 'Bisexual':
      return '💖';
    case 'Pansexual':
      return '💗';
    case 'Asexual':
      return '🖤';
    case 'Aromantic':
      return '💚';
    case 'Greysexual':
      return '🩶';
    case 'Polysexual':
      return '💛';
    case 'Omnisexual':
      return '🪐';
    case 'Fluid':
      return '🌊';
    case 'Skoliosexual':
      return '🌀';
    case 'Demisexual':
      return '💜';

    // Languages
    case 'English':
      return '🇬🇧';
    case 'Spanish':
      return '🇪🇸';
    case 'Mandarin Chinese':
      return '🇨🇳';
    case 'Hindi':
      return '🇮🇳';
    case 'Arabic':
      return '🇸🇦';
    case 'Portuguese':
      return '🇵🇹';
    case 'Bengali':
      return '🇧🇩';
    case 'Russian':
      return '🇷🇺';
    case 'Japanese':
      return '🇯🇵';
    case 'Punjabi':
      return '🇮🇳';
    case 'German':
      return '🇩🇪';
    case 'Javanese':
      return '🇮🇩';
    case 'Wu Chinese':
      return '🇨🇳';
    case 'Malay':
      return '🇲🇾';
    case 'Telugu':
      return '🇮🇳';
    case 'Vietnamese':
      return '🇻🇳';
    case 'Korean':
      return '🇰🇷';
    case 'French':
      return '🇫🇷';
    case 'Marathi':
      return '🇮🇳';
    case 'Tamil':
      return '🇮🇳';
    case 'Cantonese':
      return '🇭🇰';
    case 'Turkish':
      return '🇹🇷';
    case 'Urdu':
      return '🇵🇰';
    case 'Italian':
      return '🇮🇹';
    case 'Thai':
      return '🇹🇭';
    case 'Persian':
      return '🇮🇷';
    case 'Polish':
      return '🇵🇱';
    case 'Kannada':
      return '🇮🇳';
    case 'Ukrainian':
      return '🇺🇦';
    case 'Filipino':
      return '🇵🇭';
    case 'Gujarati':
      return '🇮🇳';
    case 'Romanian':
      return '🇷🇴';
    case 'Greek':
      return '🇬🇷';
    case 'Czech':
      return '🇨🇿';
    case 'Swedish':
      return '🇸🇪';
    case 'Dutch':
      return '🇳🇱';
    case 'Hungarian':
      return '🇭🇺';
    case 'Zulu':
      return '🇿🇦';
    case 'Hebrew':
      return '🇮🇱';
    case 'Finnish':
      return '🇫🇮';
    case 'Norwegian':
      return '🇳🇴';
    case 'Danish':
      return '🇩🇰';
    case 'Swahili':
      return '🇰🇪';
    case 'Malayalam':
      return '🇮🇳';
    case 'Amharic':
      return '🇪🇹';
    case 'Yoruba':
      return '🇳🇬';
    case 'Oromo':
      return '🇪🇹';
    case 'Igbo':
      return '🇳🇬';
    case 'Burmese':
      return '🇲🇲';
    case 'Azerbaijani':
      return '🇦🇿';
    case 'Maithili':
      return '🇮🇳';
    case 'Uzbek':
      return '🇺🇿';
    case 'Sindhi':
      return '🇵🇰';
    case 'Pashto':
      return '🇦🇫';
    case 'Kurdish':
      return '☀️';
    case 'Sinhala':
      return '🇱🇰';
    case 'Somali':
      return '🇸🇴';
    case 'Tagalog':
      return '🇵🇭';
    case 'Nepali':
      return '🇳🇵';
    case 'Khmer':
      return '🇰🇭';
    case 'Lao':
      return '🇱🇦';
    case 'Assamese':
      return '🇮🇳';
    case 'Malagasy':
      return '🇲🇬';
    case 'Slovak':
      return '🇸🇰';
    case 'Bulgarian':
      return '🇧🇬';
    case 'Croatian':
      return '🇭🇷';
    case 'Serbian':
      return '🇷🇸';
    case 'Lithuanian':
      return '🇱🇹';
    case 'Latvian':
      return '🇱🇻';
    case 'Estonian':
      return '🇪🇪';
    case 'Slovenian':
      return '🇸🇮';
    case 'Irish':
      return '🇮🇪';
    case 'Welsh':
      return '🏴󠁧󠁢󠁷󠁬󠁳󠁿';
    case 'Icelandic':
      return '🇮🇸';
    case 'Catalan':
      return '🇪🇸';
    case 'Basque':
      return '🇪🇸';
    case 'Galician':
      return '🇪🇸';

    // Causes Supported
    case 'Climate Action':
      return '🌲';
    case 'Tech Ethics':
      return '⚖️';
    case 'Mental Health':
      return '🧠';
    case 'LGBTQ+ Rights':
      return '🌈';
    case 'Education Access':
      return '📚';
    case 'Animal Protection':
      return '🐾';
    case 'Disaster Relief':
      return '🚨';
    case 'Poverty Alleviation':
      return '🤝';
    case 'Gender Equality':
      return '⚧️';
    case 'Scientific Research':
      return '🔬';
    case 'Mental Health Advocacy':
      return '💬';
    case 'Human Rights':
      return '✊';
    case 'Clean Water & Sanitation':
      return '💧';
    case 'Renewable Energy':
      return '⚡';
    case 'Economic Development':
      return '📈';
    case 'Arts & Culture Preservation':
      return '🏛️';

    // Pets
    case 'Dog':
      return '🐶';
    case 'Cat':
      return '🐱';
    case 'Fish':
      return '🐟';
    case 'Bird':
      return '🐦';
    case 'Rabbit':
      return '🐰';
    case 'Hamster':
      return '🐹';
    case 'Reptile':
      return '🦎';
    case 'Amphibian':
      return '🐸';
    case 'Horse':
      return '🐴';
    case 'Chicken':
      return '🐔';
    case 'Sugar Glider':
      return '🐿️';
    case 'Chinchilla':
      return '🐭';
    case 'Hedgehog':
      return '🦔';
    case 'No Pets':
      return '🚫';

    // Interests - Tech & Science
    case 'Python':
      return '🐍';
    case 'Flutter & Dart':
      return '💙';
    case 'Rust':
      return '🦀';
    case 'Web Development':
      return '🌐';
    case 'AI & Machine Learning':
      return '🤖';
    case 'Cybersecurity':
      return '🔒';
    case 'Game Development':
      return '🎮';
    case 'Cloud & DevOps':
      return '☁️';
    case 'Open Source Contribution':
      return '🐙';
    case 'Mobile Apps':
      return '📱';
    case 'Astrophysics & Space':
      return '🚀';
    case 'Quantum Physics':
      return '⚛️';
    case 'Neuroscience':
      return '🧠';
    case 'Psychology':
      return '💭';
    case 'Marine Biology':
      return '🐬';
    case 'Archaeology & History':
      return '🏛️';
    case 'Genetics & Biotech':
      return '🧬';
    case 'Climate Science':
      return '🌍';
    case 'PC Building':
      return '🖥️';
    case 'Virtual Reality (VR)':
      return '🕶️';
    case 'Drones & Quadcopters':
      return '🛸';
    case 'IoT & Smart Home':
      return '🏠';
    case 'Mechanical Keyboards':
      return '⌨️';
    case '3D Printing':
      return '🖨️';
    case 'Robotics':
      return '🤖';
    case 'Cryptography':
      return '🔐';
    case 'Data Analysis':
      return '📊';
    case 'Game Theory':
      return '🎲';
    case 'Mathematical Puzzles':
      return '🧩';
    case 'Algorithms':
      return '🧮';

    // Interests - Entertainment & Media
    case 'Horror Shows':
      return '👻';
    case 'Sci-Fi & Fantasy':
      return '🦄';
    case 'Documentaries':
      return '📽️';
    case 'True Crime':
      return '🕵️';
    case 'Sitcoms & Comedy':
      return '🎭';
    case 'K-Dramas':
      return '🇰🇷';
    case 'Anime & Manga':
      return '🌸';
    case 'Reality TV':
      return '📺';
    case 'Historical Drama':
      return '👑';
    case 'Talk Shows':
      return '🎙️';
    case 'Indie & Art House':
      return '🎨';
    case 'Hollywood Blockbusters':
      return '🍿';
    case 'Classic Films':
      return '🎞️';
    case 'Psychological Thrillers':
      return '🕵️‍♀️';
    case 'Animation & Pixar':
      return '🧸';
    case 'Foreign Language Films':
      return '🗣️';
    case 'Action & Adventure':
      return '🤠';
    case 'RPGs (Role-Playing)':
      return '🧙';
    case 'FPS (First-Person)':
      return '🔫';
    case 'RTS (Strategy)':
      return '♟️';
    case 'MMORPGs':
      return '🌐';
    case 'Cozy & Casual Games':
      return '☕';
    case 'Competitive Esports':
      return '🏆';
    case 'Retro & Arcade':
      return '👾';
    case 'Tabletop & D&D':
      return '🎲';
    case 'Modern Board Games':
      return '♟️';
    case 'Rock & Metal':
      return '🎸';
    case 'Pop & R&B':
      return '🎤';
    case 'Hip Hop & Rap':
      return '🎧';
    case 'Indie & Folk':
      return '🪕';
    case 'Classical & Jazz':
      return '🎷';
    case 'EDM & Synthwave':
      return '🎹';
    case 'Lo-Fi & Chillbeats':
      return '💤';
    case 'Podcasts & Audiobooks':
      return '🎙️';
    case 'Vinyl Records':
      return '📻';

    // Interests - Sports & Outdoors
    case 'Weightlifting':
      return '🏋️';
    case 'Powerlifting':
      return '💪';
    case 'CrossFit':
      return '🤸';
    case 'Calisthenics':
      return '🤸‍♀️';
    case 'Yoga & Pilates':
      return '🧘';
    case 'HIIT & Cardio':
      return '🏃';
    case 'Spinning & Cycling':
      return '🚴';
    case 'Gymnastics':
      return '🤸‍♂️';
    case 'Football (Soccer)':
      return '⚽';
    case 'Basketball':
      return '🏀';
    case 'Volleyball':
      return '🏐';
    case 'Baseball':
      return '⚾';
    case 'Cricket':
      return '🏏';
    case 'American Football':
      return '🏈';
    case 'Rugby':
      return '🏉';
    case 'Ice Hockey':
      return '🏒';
    case 'Tennis':
      return '🎾';
    case 'Badminton':
      return '🏸';
    case 'Table Tennis':
      return '🏓';
    case 'Golf':
      return '⛳';
    case 'Archery':
      return '🏹';
    case 'Fencing':
      return '🤺';
    case 'Billiards & Pool':
      return '🎱';
    case 'Swimming & Diving':
      return '🏊';
    case 'Surfing & Bodyboarding':
      return '🏄';
    case 'Kayaking & Paddle':
      return '🛶';
    case 'Scuba Diving':
      return '🤿';
    case 'Skiing':
      return '🎿';
    case 'Snowboarding':
      return '🏂';
    case 'Ice Skating':
      return '⛸️';
    case 'Hiking & Trekking':
      return '🥾';
    case 'Rock Climbing':
      return '🧗';
    case 'Camping & Bushcraft':
      return '🔥';
    case 'Backpacking':
      return '🎒';
    case 'Mountaineering':
      return '🏔️';
    case 'Trail Running':
      return '🏃‍♂️';
    case 'Geocaching':
      return '📍';

    // Interests - Creative & Arts
    case 'Watercolor Painting':
      return '🎨';
    case 'Oil & Acrylics':
      return '🖌️';
    case 'Sketching & Charcoal':
      return '✏️';
    case 'Digital Illustration':
      return '🖥️';
    case 'Calligraphy':
      return '✒️';
    case 'Pottery & Ceramics':
      return '🏺';
    case 'Origami & Papercraft':
      return '📄';
    case 'UI/UX Design':
      return '🎨';
    case 'Graphic Design':
      return '📐';
    case 'Fashion & Apparel':
      return '👕';
    case 'Interior Design':
      return '🛋️';
    case '3D Modeling':
      return '💻';
    case 'Architecture':
      return '🏛️';
    case 'Landscape & Nature':
      return '🌅';
    case 'Portrait & Studio':
      return '📸';
    case 'Street & Documentary':
      return '📷';
    case 'Film & Analog':
      return '🎞️';
    case 'Drone Videography':
      return '🛸';
    case 'Video Editing':
      return '🎬';
    case 'Dancing':
      return '💃';
    case 'Acting & Theater':
      return '🎭';
    case 'Musical Instruments':
      return '🎹';
    case 'Singing & Vocals':
      return '🎤';
    case 'Stand-up & Improv':
      return '🎙️';
    case 'Creative Writing':
      return '✍️';
    case 'Poetry & Prose':
      return '📜';
    case 'Blogging & Journalism':
      return '📰';
    case 'Journaling':
      return '📓';

    // Interests - Food & Drink
    case 'Baking & Pastry':
      return '🥐';
    case 'Sourdough Bread':
      return '🍞';
    case 'BBQ & Grilling':
      return '🍖';
    case 'Vegan & Vegetarian':
      return '🥗';
    case 'Fine Dining':
      return '🍽️';
    case 'Fermentation':
      return '🍶';
    case 'Meal Prep & Nutrition':
      return '🥦';
    case 'Specialty Coffee':
      return '☕';
    case 'Matcha & Green Tea':
      return '🍵';
    case 'Loose Leaf Tea':
      return '🍃';
    case 'Wine Tasting':
      return '🍷';
    case 'Craft Beer Brewing':
      return '🍺';
    case 'Mixology & Cocktails':
      return '🍹';

    // Interests - Lifestyle & Hobbies
    case 'Houseplants':
      return '🌿';
    case 'Bonsai Trees':
      return '🪴';
    case 'Vegetable Gardening':
      return '🥕';
    case 'Aquascaping':
      return '🐠';
    case 'Foraging & Herbalism':
      return '🍄';
    case 'Meditation':
      return '🧘';
    case 'Philosophy':
      return '📚';
    case 'Astrology & Tarot':
      return '🔮';
    case 'Self-Improvement':
      return '📈';
    case 'Volunteering':
      return '🤝';
    case 'Vintage & Thrifting':
      return '🧥';
    case 'Sneaker Culture':
      return '👟';
    case 'Streetwear':
      return '🧢';
    case 'Watch Collecting':
      return '⌚';
    case 'Book Collecting':
      return '📚';
    case 'Dogs & Dog Training':
      return '🦮';
    case 'Cats & Felines':
      return '🐈';
    case 'Reptiles':
      return '🦎';
    case 'Aquariums & Fish':
      return '🐠';
    case 'Bird Watching':
      return '🦤';

    default:
      return '';
  }
}
