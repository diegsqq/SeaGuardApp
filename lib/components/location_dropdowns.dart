// lib/models/location_model.dart

class Barangay {
  final int id;
  final String name;

  Barangay({required this.id, required this.name});

  factory Barangay.fromJson(Map<String, dynamic> json) =>
      Barangay(id: json['id'], name: json['barangay_name']);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Barangay &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Municipality {
  final int id;
  final String name;
  final List<Barangay> barangays;

  Municipality({required this.id, required this.name, required this.barangays});

  factory Municipality.fromJson(Map<String, dynamic> json) => Municipality(
        id: json['id'],
        name: json['municipality_name'],
        barangays: (json['barangays'] as List<dynamic>)
            .map((e) => Barangay.fromJson(e))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Municipality &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Province {
  final int id;
  final String name;
  final List<Municipality> municipalities;

  Province({required this.id, required this.name, required this.municipalities});

  factory Province.fromJson(Map<String, dynamic> json) => Province(
        id: json['province_id'],
        name: json['province_name'],
        municipalities: (json['municipalities'] as List<dynamic>)
            .map((e) => Municipality.fromJson(e))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Province &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class Region {
  final int regionId;
  final String name;
  final String description;
  final List<Province> provinces;

  Region({
    required this.regionId,
    required this.name,
    required this.description,
    required this.provinces,
  });

  factory Region.fromJson(Map<String, dynamic> json) => Region(
        regionId: json['region_id'],
        name: json['region_name'],
        description: json['region_description'],
        provinces: (json['provinces'] as List<dynamic>)
            .map((e) => Province.fromJson(e))
            .toList(),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Region &&
          runtimeType == other.runtimeType &&
          regionId == other.regionId;

  @override
  int get hashCode => regionId.hashCode;
}
