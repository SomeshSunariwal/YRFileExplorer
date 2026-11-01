typedef Json = Map<String, dynamic>;
List<Json> jsonRows(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
