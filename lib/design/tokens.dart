import 'package:flutter/material.dart';

abstract final class PlasmaColors {
  static const background = Color(0xFF070D1B);
  static const backgroundSoft = Color(0xFF0F1C34);
  static const board = Color(0xFF13223E);
  static const empty = Color(0xFF203454);
  static const gridStroke = Color(0xFF2A446B);
  static const text = Color(0xFFF6FAFF);
  static const secondary = Color(0xFF9CBCD9);
  static const cyan = Color(0xFF2DE2E6);
  static const blue = Color(0xFF4D90FF);
  static const violet = Color(0xFF9560FF);
  static const pink = Color(0xFFFF5DA8);
  static const lime = Color(0xFFA2F36B);
  static const warning = Color(0xFFFF657A);

  static Color block(int colorIndex) => switch (colorIndex) {
        1 => cyan,
        2 => blue,
        3 => violet,
        4 => pink,
        _ => lime,
      };
}
