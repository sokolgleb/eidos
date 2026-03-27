import 'dart:io';
import 'package:flutter/widgets.dart';

enum SyncStatus { local, uploading, synced, failed }

class Sighting {
  final String id;
  final DateTime createdAt;
  final String originalPath;
  final String annotatedPath;
  final String? originalUrl;
  final String? annotatedUrl;
  final SyncStatus syncStatus;

  const Sighting({
    required this.id,
    required this.createdAt,
    required this.originalPath,
    required this.annotatedPath,
    this.originalUrl,
    this.annotatedUrl,
    this.syncStatus = SyncStatus.local,
  });

  Sighting copyWith({
    String? originalUrl,
    String? annotatedUrl,
    SyncStatus? syncStatus,
  }) => Sighting(
        id: id,
        createdAt: createdAt,
        originalPath: originalPath,
        annotatedPath: annotatedPath,
        originalUrl: originalUrl ?? this.originalUrl,
        annotatedUrl: annotatedUrl ?? this.annotatedUrl,
        syncStatus: syncStatus ?? this.syncStatus,
      );

  /// Returns an ImageProvider for the original image — local file if available,
  /// falling back to the remote URL.
  ImageProvider get originalProvider {
    if (originalPath.isNotEmpty && File(originalPath).existsSync()) {
      return FileImage(File(originalPath));
    }
    if (originalUrl != null) return NetworkImage(originalUrl!);
    return FileImage(File(originalPath)); // will show error state
  }

  /// Returns an ImageProvider for the annotated image — local file if available,
  /// falling back to the remote URL.
  ImageProvider get annotatedProvider {
    if (annotatedPath.isNotEmpty && File(annotatedPath).existsSync()) {
      return FileImage(File(annotatedPath));
    }
    if (annotatedUrl != null) return NetworkImage(annotatedUrl!);
    return FileImage(File(annotatedPath));
  }

  // Persisted fields — paths computed at runtime from docs dir; URLs stored too
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        if (originalUrl != null) 'originalUrl': originalUrl,
        if (annotatedUrl != null) 'annotatedUrl': annotatedUrl,
        'syncStatus': syncStatus.name,
      };

  factory Sighting.fromJson(Map<String, dynamic> json, String docsPath) {
    final id = json['id'] as String;
    return Sighting(
      id: id,
      createdAt: DateTime.parse(json['createdAt'] as String),
      originalPath: '$docsPath/sightings/$id/original.jpg',
      annotatedPath: '$docsPath/sightings/$id/annotated.png',
      originalUrl: json['originalUrl'] as String?,
      annotatedUrl: json['annotatedUrl'] as String?,
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == (json['syncStatus'] as String?),
        orElse: () => SyncStatus.local,
      ),
    );
  }

  /// Build from a Supabase DB row (cloud sighting with no local files).
  factory Sighting.fromSupabase(Map<String, dynamic> row) {
    return Sighting(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      originalPath: '',
      annotatedPath: '',
      originalUrl: row['original_url'] as String?,
      annotatedUrl: row['annotated_url'] as String?,
      syncStatus: SyncStatus.synced,
    );
  }

  Map<String, dynamic> toSupabase(String userId) => {
        'id': id,
        'user_id': userId,
        'created_at': createdAt.toIso8601String(),
        'original_url': originalUrl ?? '',
        'annotated_url': annotatedUrl ?? '',
        'is_public': false,
      };
}
