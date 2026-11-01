import 'package:flutter/material.dart';

class FileClipboard extends ChangeNotifier {
  List<String> paths = [];
  bool move = false;
  void put(List<String> value, bool cut) {
    paths = List.of(value);
    move = cut;
    notifyListeners();
  }

  void clear() {
    paths = [];
    notifyListeners();
  }
}
