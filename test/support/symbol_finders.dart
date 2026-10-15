import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/widgets/symbols/default_symbol_builders.dart';

/// Finds the default point label blocks whose text is [text].
Finder symbolTextBlock(String text) => find.byWidgetPredicate(
  (widget) => widget is SymbolTextBlock && widget.span.toPlainText() == text,
);

/// The default point label block whose text is [text].
SymbolTextBlock symbolTextBlockOf(WidgetTester tester, String text) =>
    tester.widget<SymbolTextBlock>(symbolTextBlock(text));

/// The root style of the default point label block whose text is [text].
TextStyle? symbolTextStyle(WidgetTester tester, String text) =>
    (symbolTextBlockOf(tester, text).span as TextSpan).style;

/// The render object of the default point label block whose text is [text].
RenderSymbolTextBlock symbolTextRender(WidgetTester tester, String text) =>
    tester.renderObject<RenderSymbolTextBlock>(symbolTextBlock(text));
