import 'package:code_forge/code_forge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Code-action titles are UI text that happens to carry code fragments, not
  // editor content, so the label drops the editor's mono family and reads in
  // the UI font like VS Code's action list. The hover and signature popups
  // keep the editor family for their prose, and fenced blocks and inline code
  // keep it from the popup's own textStyle.
  group('popup prose style', () {
    const base = TextStyle(
      fontSize: 14,
      height: 1.4,
      fontWeight: FontWeight.w500,
      fontFamily: 'JetBrainsMono',
      color: Colors.white,
    );

    test('drops the editor family and keeps everything else', () {
      final prose = overlayProseTextStyle(base);
      expect(prose.fontFamily, isNull);
      expect(prose.fontSize, 14);
      expect(prose.height, 1.4);
      expect(prose.fontWeight, FontWeight.w500);
      expect(prose.color, Colors.white);
    });

    test('leaves a family-less base without a family', () {
      // copyWith(fontFamily: null) keeps the old family, which is why the
      // prose style rebuilds instead of deriving, so a base that is already
      // in the UI font stays exactly that.
      final prose = overlayProseTextStyle(const TextStyle(fontSize: 14));
      expect(prose.fontFamily, isNull);
      expect(prose.fontSize, 14);
    });
  });
}
