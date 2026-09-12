part of 'symbol_overlay.dart';

class _SymbolBatch extends MultiChildRenderObjectWidget {
  _SymbolBatch({
    required List<_SymbolPaintItem> paintItems,
    required this.positions,
    required this.fades,
    required this.screenSize,
  }) : entries = [
         for (final item in paintItems)
           _DefaultSymbolBatchEntry(item.id, interactive: item.interactive),
       ],
       positionRevision = positions.revision,
       super(
         children: [
           for (final item in paintItems)
             RepaintBoundary(
               key: ValueKey(item.id),
               child: item.interactive
                   ? IgnorePointer(ignoring: !item.visible, child: item.child)
                   : item.child,
             ),
         ],
       );

  final List<_DefaultSymbolBatchEntry> entries;
  final _SymbolPositionStore positions;
  final _BatchedSymbolFadeController fades;
  final Size screenSize;
  final int positionRevision;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSymbolBatch(
    entries: entries,
    positions: positions,
    fades: fades,
    screenSize: screenSize,
    positionRevision: positionRevision,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSymbolBatch renderObject,
  ) {
    renderObject
      ..entries = entries
      ..positions = positions
      ..fades = fades
      ..screenSize = screenSize
      ..positionRevision = positionRevision;
  }
}

class const _DefaultSymbolBatchEntry(
  final Object id, {
  required final bool interactive,
});

class _DefaultSymbolBatchParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSymbolBatch({
  required var List<_DefaultSymbolBatchEntry> _entries,
  required var _SymbolPositionStore _positions,
  required var _BatchedSymbolFadeController _fades,
  required var Size _screenSize,
  required var int _positionRevision,
}) extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _DefaultSymbolBatchParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _DefaultSymbolBatchParentData
        > {
  static const _hiddenPosition = Offset(-100000, -100000);
  var _hasLayout = false;

  set entries(List<_DefaultSymbolBatchEntry> value) {
    final needsLayout = !_sameEntryOrder(_entries, value);
    _entries = value;
    if (needsLayout) {
      markNeedsLayout();
    } else {
      markNeedsPaint();
      markNeedsSemanticsUpdate();
    }
  }

  set positions(_SymbolPositionStore value) {
    if (identical(_positions, value)) return;
    if (attached) _positions.removeListener(_handlePositionChange);
    _positions = value;
    if (attached) _positions.addListener(_handlePositionChange);
    _handlePositionChange();
  }

  set fades(_BatchedSymbolFadeController value) {
    if (identical(_fades, value)) return;
    if (attached) _fades.removeListener(_handleFadeChange);
    _fades = value;
    if (attached) _fades.addListener(_handleFadeChange);
    markNeedsPaint();
  }

  set screenSize(Size value) {
    if (_screenSize == value) return;
    _screenSize = value;
    markNeedsLayout();
  }

  set positionRevision(int value) {
    if (_positionRevision == value) return;
    _positionRevision = value;
    _handlePositionChange();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _DefaultSymbolBatchParentData) {
      child.parentData = _DefaultSymbolBatchParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _positions.addListener(_handlePositionChange);
    _fades.addListener(_handleFadeChange);
  }

  @override
  void detach() {
    _positions.removeListener(_handlePositionChange);
    _fades.removeListener(_handleFadeChange);
    super.detach();
  }

  @override
  void markNeedsLayout() {
    _hasLayout = false;
    super.markNeedsLayout();
  }

  void _handlePositionChange() {
    if (!_hasLayout) {
      markNeedsLayout();

      return;
    }
    _updateChildOffsets();
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  void _handleFadeChange() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_screenSize);

  @override
  void performLayout() {
    size = constraints.constrain(_screenSize);
    final childConstraints = BoxConstraints.loose(size);
    var child = firstChild;
    while (child != null) {
      child.layout(childConstraints, parentUsesSize: true);
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      child = parentData.nextSibling;
    }
    _hasLayout = true;
    _updateChildOffsets();
  }

  void _updateChildOffsets() {
    var child = firstChild;
    var index = 0;
    while (child != null) {
      assert(index < _entries.length);
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      final anchor = index < _entries.length
          ? _positions.anchor(_entries[index].id) ?? _hiddenPosition
          : _hiddenPosition;
      parentData.offset =
          anchor - Offset(child.size.width / 2, child.size.height / 2);
      child = parentData.nextSibling;
      index++;
    }
    assert(index == _entries.length);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    var index = 0;
    while (child != null) {
      final currentChild = child;
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      final entry = _entries[index];
      final childOffset = offset + parentData.offset;
      final alpha = (_fades.opacityFor(entry.id).clamp(0.0, 1.0) * 255).round();
      if (alpha == 255) {
        context.paintChild(currentChild, childOffset);
      } else if (alpha > 0) {
        context.pushOpacity(
          childOffset,
          alpha,
          (innerContext, innerOffset) =>
              innerContext.paintChild(currentChild, innerOffset),
        );
      }
      child = parentData.nextSibling;
      index++;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    var index = _entries.length - 1;
    while (child != null) {
      final currentChild = child;
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      final entry = _entries[index];
      if (entry.interactive && _fades.isVisible(entry.id)) {
        final hit = result.addWithPaintOffset(
          offset: parentData.offset,
          position: position,
          hitTest: (result, transformed) =>
              currentChild.hitTest(result, position: transformed),
        );
        if (hit) return true;
      }
      child = parentData.previousSibling;
      index--;
    }

    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final parentData = child.parentData! as _DefaultSymbolBatchParentData;
    transform.multiply(
      Matrix4.translationValues(parentData.offset.dx, parentData.offset.dy, 0),
    );
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    var index = 0;
    while (child != null) {
      final parentData = child.parentData! as _DefaultSymbolBatchParentData;
      if (_fades.opacityFor(_entries[index].id) > 0) visitor(child);
      child = parentData.nextSibling;
      index++;
    }
  }
}

bool _sameEntryOrder(
  List<_DefaultSymbolBatchEntry> left,
  List<_DefaultSymbolBatchEntry> right,
) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index].id != right[index].id) return false;
  }

  return true;
}
