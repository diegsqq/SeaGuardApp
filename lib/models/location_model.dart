class Region {
  final String name;
  final List<Province> provinces;

  Region({required this.name, required this.provinces});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Region && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;

  static fromJson(e) {}
}

class Province {
  final String name;
  final List<Municipality> municipalities;

  Province({required this.name, required this.municipalities});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Province && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class Municipality {
  final String name;
  final List<Barangay> barangays;

  Municipality({required this.name, required this.barangays});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Municipality && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}

class Barangay {
  final String name;

  Barangay({required this.name});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Barangay && runtimeType == other.runtimeType && name == other.name;

  @override
  int get hashCode => name.hashCode;
}
