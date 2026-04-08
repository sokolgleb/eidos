import 'dart:io';
import 'package:flutter/widgets.dart';

enum SyncStatus { local, uploading, synced, failed }

class Sighting {
  final String id;
  final DateTime createdAt;
  final String originalPath;
  final String annotatedPath;
  final String thumbnailPath;
  final String? originalUrl;
  final String? annotatedUrl;
  final String? thumbnailUrl;
  final SyncStatus syncStatus;
  final bool isFavorite;
  final bool isPublic;

  const Sighting({
    required this.id,
    required this.createdAt,
    required this.originalPath,
    required this.annotatedPath,
    this.thumbnailPath = '',
    this.originalUrl,
    this.annotatedUrl,
    this.thumbnailUrl,
    this.syncStatus = SyncStatus.local,
    this.isFavorite = false,
    this.isPublic = false,
  });

  Sighting copyWith({
    String? thumbnailPath,
    String? originalUrl,
    String? annotatedUrl,
    String? thumbnailUrl,
    SyncStatus? syncStatus,
    bool? isFavorite,
    bool? isPublic,
  }) => Sighting(
        id: id,
        createdAt: createdAt,
        originalPath: originalPath,
        annotatedPath: annotatedPath,
        thumbnailPath: thumbnailPath ?? this.thumbnailPath,
        originalUrl: originalUrl ?? this.originalUrl,
        annotatedUrl: annotatedUrl ?? this.annotatedUrl,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        syncStatus: syncStatus ?? this.syncStatus,
        isFavorite: isFavorite ?? this.isFavorite,
        isPublic: isPublic ?? this.isPublic,
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

  /// Returns an ImageProvider for the thumbnail — local file → network URL →
  /// falls back to annotatedProvider for backwards compatibility.
  ImageProvider get thumbnailProvider {
    if (thumbnailPath.isNotEmpty && File(thumbnailPath).existsSync()) {
      return FileImage(File(thumbnailPath));
    }
    if (thumbnailUrl != null && thumbnailUrl!.isNotEmpty) {
      return NetworkImage(thumbnailUrl!);
    }
    return annotatedProvider;
  }

  // Persisted fields — paths computed at runtime from docs dir; URLs stored too
  Map<String, dynamic> toJson() => {
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        if (originalUrl != null) 'originalUrl': originalUrl,
        if (annotatedUrl != null) 'annotatedUrl': annotatedUrl,
        if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
        'syncStatus': syncStatus.name,
        'isFavorite': isFavorite,
        'isPublic': isPublic,
      };

  factory Sighting.fromJson(Map<String, dynamic> json, String docsPath) {
    final id = json['id'] as String;
    return Sighting(
      id: id,
      createdAt: DateTime.parse(json['createdAt'] as String),
      originalPath: '$docsPath/sightings/$id/original.jpg',
      annotatedPath: '$docsPath/sightings/$id/annotated.png',
      thumbnailPath: '$docsPath/sightings/$id/thumbnail.jpg',
      originalUrl: json['originalUrl'] as String?,
      annotatedUrl: json['annotatedUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      syncStatus: SyncStatus.values.firstWhere(
        (s) => s.name == (json['syncStatus'] as String?),
        orElse: () => SyncStatus.local,
      ),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isPublic: json['isPublic'] as bool? ?? false,
    );
  }

  /// Build from a Supabase DB row (cloud sighting with no local files).
  factory Sighting.fromSupabase(Map<String, dynamic> row) {
    final thumbUrl = row['thumbnail_url'] as String?;
    return Sighting(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      originalPath: '',
      annotatedPath: '',
      originalUrl: row['original_url'] as String?,
      annotatedUrl: row['annotated_url'] as String?,
      thumbnailUrl: (thumbUrl != null && thumbUrl.isNotEmpty) ? thumbUrl : null,
      syncStatus: SyncStatus.synced,
      isFavorite: row['is_favorite'] as bool? ?? false,
      isPublic: row['is_public'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toSupabase(String userId) => {
        'id': id,
        'user_id': userId,
        'created_at': createdAt.toIso8601String(),
        'original_url': originalUrl ?? '',
        'annotated_url': annotatedUrl ?? '',
        'thumbnail_url': thumbnailUrl ?? '',
        'is_favorite': isFavorite,
        'is_public': isPublic,
      };
}
