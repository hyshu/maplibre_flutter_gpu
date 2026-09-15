part of 'symbol_overlay.dart';

class _SymbolPositionStore extends ChangeNotifier {
  Map<String, MapSymbol> _symbols = const {};
  Map<Object, Offset> _anchors = const {};
  SymbolPositionList? _livePositions;
  int _revision = 0;

  int get revision => _revision;

  void update(List<MapSymbol> symbols) {
    _revision++;
    if (symbols is SymbolPositionList) {
      _livePositions = symbols;
      _symbols = const {};
      _anchors = const {};

      return;
    }
    _livePositions = null;
    _symbols = {for (final symbol in symbols) symbol.key: symbol};
    _anchors = {
      for (final symbol in symbols) (symbol.key, true): ?symbol.iconPos,
      for (final symbol in symbols) (symbol.key, false): ?symbol.textPos,
    };
  }

  void notifyPositionChange() => notifyListeners();

  Offset? anchor(Object id) {
    final component = id as (String, bool);

    return anchorFor(component.$1, icon: component.$2);
  }

  Offset? anchorFor(String key, {required bool icon}) {
    final livePositions = _livePositions;
    if (livePositions != null) {
      return livePositions.anchorFor(key, icon: icon);
    }

    return _anchors[(key, icon)];
  }

  MapSymbol positioned(MapSymbol symbol) {
    final livePositions = _livePositions;
    if (livePositions != null) return livePositions.positioned(symbol);
    final positioned = _symbols[symbol.key];
    if (positioned == null) return symbol;

    return .new(
      key: symbol.key,
      data: symbol.data,
      textPos: positioned.textPos,
      iconPos: positioned.iconPos,
      icon: symbol.icon,
      spriteAtlas: symbol.spriteAtlas,
      visible: symbol.visible,
      fadeIn: symbol.fadeIn,
    );
  }
}

class const _PositionedSymbolBuilder({
  required final MapSymbol symbol,
  required final _SymbolPositionStore positions,
  required final SymbolWidgetBuilder builder,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: positions,
    builder: (context, _) =>
        builder(context, positions.positioned(symbol)) ??
        const SizedBox.shrink(),
  );
}
