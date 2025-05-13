/// Callback argument for when the actual visible range of the chart changes.
class ActualRangeChangedArgs {
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;

  ActualRangeChangedArgs({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });
}

/// Signature for a callback that reports the visible chart range after zoom/pan.
typedef ChartActualRangeChangedCallback = void Function(ActualRangeChangedArgs args);
