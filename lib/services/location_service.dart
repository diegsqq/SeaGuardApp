import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/location_model.dart';

class LocationService {
  static Future<List<Region>> loadRegionsFromJsonAsset() async {
    final String jsonString = await rootBundle.loadString('assets/location_data.json');
    final List<dynamic> jsonList = json.decode(jsonString);

    return jsonList.map<Region>((e) => Region.fromJson(e)).toList();
  }
}
