/// Búsqueda local sin distinguir mayúsculas ni tildes (panama ↔ panamá).
String normalizeForSearch(String input) {
  final lower = input.trim().toLowerCase();
  if (lower.isEmpty) return '';
  const map = <String, String>{
    'á': 'a',
    'à': 'a',
    'ä': 'a',
    'â': 'a',
    'ã': 'a',
    'é': 'e',
    'è': 'e',
    'ë': 'e',
    'ê': 'e',
    'í': 'i',
    'ì': 'i',
    'ï': 'i',
    'î': 'i',
    'ó': 'o',
    'ò': 'o',
    'ö': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ù': 'u',
    'ü': 'u',
    'û': 'u',
    'ñ': 'n',
    'ç': 'c',
  };
  final out = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    out.write(map[ch] ?? ch);
  }
  return out.toString();
}

bool searchTextContains(String? haystack, String query) {
  final q = normalizeForSearch(query);
  if (q.isEmpty) return true;
  if (haystack == null || haystack.trim().isEmpty) return false;
  return normalizeForSearch(haystack).contains(q);
}

bool searchTextMatchesAnyField(String query, List<String?> fields) {
  for (final f in fields) {
    if (searchTextContains(f, query)) return true;
  }
  return false;
}
