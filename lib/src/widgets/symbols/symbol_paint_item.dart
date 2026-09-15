part of 'symbol_overlay.dart';

class const _SymbolPaintItem({
  required final Object id,
  required final int layerIndex,
  required final int renderGroup,
  required final int componentOrder,
  required final int renderOrder,
  required final int ordinal,
  required final String symbolKey,
  required final bool visible,
  required final bool fadeIn,
  required final bool interactive,
  required final Widget child,
}) {
  static int compare(_SymbolPaintItem left, _SymbolPaintItem right) {
    var result = left.layerIndex.compareTo(right.layerIndex);
    if (result == 0) result = left.renderGroup.compareTo(right.renderGroup);
    if (result == 0) {
      result = left.componentOrder.compareTo(right.componentOrder);
    }
    if (result == 0) result = left.renderOrder.compareTo(right.renderOrder);

    return result == 0 ? left.ordinal.compareTo(right.ordinal) : result;
  }
}
