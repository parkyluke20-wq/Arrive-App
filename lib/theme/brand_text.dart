import 'package:flutter/material.dart';

class BrandText {
  static const String primaryFont = 'Arial';

  static const TextStyle title = TextStyle(
    fontFamily: primaryFont,
    fontSize: 32,
    fontWeight: FontWeight.w600,
    color: Colors.black,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: primaryFont,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );

  static const TextStyle label = TextStyle(
    fontFamily: primaryFont,
    fontSize: 16,
    color: Colors.black,
  );
}