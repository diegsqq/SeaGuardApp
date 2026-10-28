class CommunityModeration {
  static const Set<String> _blockedTerms = {
    'asshole',
    'bastard',
    'bitch',
    'bullshit',
    'cunt',
    'damn',
    'dick',
    'fuck',
    'fucking',
    'gago',
    'leche',
    'puta',
    'putang',
    'pussy',
    'shit',
    'tanga',
    'tarantado',
    'ulol',
  };

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('!', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('@', 'a')
        .replaceAll('5', 's')
        .replaceAll(r'$', 's')
        .replaceAll('7', 't');
  }

  static bool containsProfanity(String value) {
    final normalized = _normalize(value);
    final tokens = normalized
        .split(RegExp(r'[^a-z0-9]+'))
        .where((token) => token.trim().isNotEmpty);
    return tokens.any(_blockedTerms.contains);
  }

  static String messageFor(String target) {
    return 'Please remove inappropriate language before $target.';
  }
}
