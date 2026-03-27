class Sighting {
  final String id;
  final DateTime createdAt;
  final String originalPath;
  final String annotatedPath;

  const Sighting({
    required this.id,
    required this.createdAt,
    required this.originalPath,
    required this.annotatedPath,
  });

  // Only id + date persisted — paths are computed at runtime from current docs dir
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Sighting.fromJson(Map<String, dynamic> json, String docsPath) {
    final id = json['id'] as String;
    return Sighting(
      id: id,
      createdAt: DateTime.parse(json['createdAt'] as String),
      originalPath: '$docsPath/sightings/$id/original.jpg',
      annotatedPath: '$docsPath/sightings/$id/annotated.png',
    );
  }
}
