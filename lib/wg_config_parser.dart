Map<String, dynamic> parseWireguardConfig(String content) {
  final lines = content.split(RegExp(r'\r?\n'));
  final Map<String, dynamic> result = {'interfaces': <Map<String, String>>[], 'peers': <Map<String, String>>[]};

  Map<String, String>? currentInterface;
  Map<String, String>? currentPeer;
  String? currentSection;

  for (var raw in lines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      final sec = line.substring(1, line.length - 1).trim();
      currentSection = sec.toLowerCase();
      if (currentSection == 'interface') {
        currentInterface = <String, String>{};
        (result['interfaces'] as List).add(currentInterface);
        currentPeer = null;
      } else if (currentSection == 'peer') {
        currentPeer = <String, String>{};
        (result['peers'] as List).add(currentPeer);
        currentInterface = null;
      } else {
        // unknown/custom section -> skip but keep section name
        currentInterface = null;
        currentPeer = null;
      }
      continue;
    }

    final idx = line.indexOf('=');
    if (idx <= 0) continue;
    final key = line.substring(0, idx).trim();
    final value = line.substring(idx + 1).trim();

    if (currentSection == 'interface' && currentInterface != null) {
      currentInterface[key] = value;
    } else if (currentSection == 'peer' && currentPeer != null) {
      currentPeer[key] = value;
    } else {
      // top-level/global keys
      final global = result.putIfAbsent('global', () => <String, String>{}) as Map<String, String>;
      global[key] = value;
    }
  }

  // Basic validation: interface with PrivateKey and Address is considered valid
  var isValid = false;
  final interfaces = result['interfaces'] as List;
  if (interfaces.isNotEmpty) {
    final if0 = interfaces.first as Map<String, String>;
    if (if0.containsKey('PrivateKey') && if0.containsKey('Address')) {
      isValid = true;
    }
  }
  result['isValid'] = isValid;
  return result;
}
