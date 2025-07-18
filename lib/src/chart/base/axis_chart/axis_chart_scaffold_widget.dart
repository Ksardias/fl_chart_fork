import 'package:fl_chart/src/chart/base/axis_chart/axis_chart_data.dart';
import 'package:fl_chart/src/chart/base/axis_chart/scale_axis.dart';
import 'package:fl_chart/src/chart/base/axis_chart/side_titles/side_titles_widget.dart';
import 'package:fl_chart/src/chart/base/axis_chart/transformation_config.dart';
import 'package:fl_chart/src/chart/base/custom_interactive_viewer.dart';
import 'package:fl_chart/src/extensions/fl_titles_data_extension.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show clampDouble;

/// A builder to build a chart.
///
/// The [chartVirtualRect] is the virtual chart virtual rect to be used when
/// laying out the chart's content. It is transformed based on users'
/// interactions like scaling and panning.
typedef ChartBuilder =
    Widget Function(BuildContext context, Rect? chartVirtualRect);

/// A scaffold to show a scalable axis-based chart
///
/// It contains some placeholders to represent an axis-based chart.
///
/// It's something like the below graph:
/// |----------------------|
/// |      |  top  |       |
/// |------|-------|-------|
/// | left | chart | right |
/// |------|-------|-------|
/// |      | bottom|       |
/// |----------------------|
///
/// `left`, `top`, `right`, `bottom` are some place holders to show titles
/// provided by [AxisChartData.titlesData] around the chart
/// `chart` is a centered place holder to show a raw chart. The chart is
/// built using [chartBuilder].
class AxisChartScaffoldWidget extends StatefulWidget {
  const AxisChartScaffoldWidget({
    super.key,
    required this.chartBuilder,
    required this.data,
    this.transformationConfig = const FlTransformationConfig(),
  });

  /// The builder to build the chart.
  final ChartBuilder chartBuilder;

  /// The data to build the chart.
  final AxisChartData data;

  /// {@template fl_chart.AxisChartScaffoldWidget.transformationConfig}
  /// The transformation configuration of the chart.
  ///
  /// Used to configure scaling and panning of the chart.
  /// {@endtemplate}
  final FlTransformationConfig transformationConfig;

  @override
  State<AxisChartScaffoldWidget> createState() =>
      _AxisChartScaffoldWidgetState();
}

class _AxisChartScaffoldWidgetState extends State<AxisChartScaffoldWidget> {
  late TransformationController _transformationController;
  Matrix4? _lastNotifiedMatrix;

  final _chartKey = GlobalKey();
  Rect? _lastKnownViewRect;

  FlTransformationConfig get _transformationConfig =>
      widget.transformationConfig;

  bool get _canScaleHorizontally =>
      _transformationConfig.scaleAxis == FlScaleAxis.horizontal ||
      _transformationConfig.scaleAxis == FlScaleAxis.free;

  bool get _canScaleVertically =>
      _transformationConfig.scaleAxis == FlScaleAxis.vertical ||
      _transformationConfig.scaleAxis == FlScaleAxis.free;

  @override
  void initState() {
    super.initState();
    _transformationController =
        _transformationConfig.transformationController ??
        TransformationController();
    _transformationController.addListener(_transformationControllerListener);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _notifyViewportChange();
      }
    });
  }

  @override
  void dispose() {
    _transformationController.removeListener(_transformationControllerListener);
    if (_transformationConfig.transformationController == null) {
      // Only dispose if it was an internally created controller
      _transformationController.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(AxisChartScaffoldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldCtrl = oldWidget.transformationConfig.transformationController;
    final newCtrl = widget.transformationConfig.transformationController;

    if (oldCtrl != newCtrl) {
      _transformationController.removeListener(
        _transformationControllerListener,
      );
      if (newCtrl == null) {
        if (oldCtrl != null) {
        } else {
          _transformationController.dispose();
        }
        _transformationController = TransformationController();
      } else {
        if (oldCtrl == null) {
          _transformationController.dispose();
        }
        _transformationController = newCtrl;
      }
      _transformationController.addListener(_transformationControllerListener);
      _lastNotifiedMatrix = null;
    }

    if (oldWidget.data.minX != widget.data.minX ||
        oldWidget.data.maxX != widget.data.maxX ||
        oldWidget.transformationConfig.scaleAxis !=
            widget.transformationConfig.scaleAxis) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _notifyViewportChange();
        }
      });
    }
  }

  void _transformationControllerListener() {
    if (_lastNotifiedMatrix == _transformationController.value) {
      return;
    }
    _lastNotifiedMatrix = _transformationController.value;

    setState(() {});
    _notifyViewportChange();
  }

  void _notifyViewportChange() {
    // print('[AxisChartScaffoldWidget] _notifyViewportChange CALLED.');

    if (widget.transformationConfig.onViewportChanged == null) {
      // print(
        // '[AxisChartScaffoldWidget] EXIT: onViewportChanged callback is null.',
      // );
      return;
    }
    if (_lastKnownViewRect == null) {
      // print('[AxisChartScaffoldWidget] EXIT: _lastKnownViewRect is null.');
      return;
    }

    final viewRect = _lastKnownViewRect!;
    // print('[AxisChartScaffoldWidget] viewRect: $viewRect');

    final currentMatrix = _transformationController.value;
    // print('[AxisChartScaffoldWidget] Transformation Matrix:');
    // print('[AxisChartScaffoldWidget]   ${currentMatrix.row0}');
    // print('[AxisChartScaffoldWidget]   ${currentMatrix.row1}');
    // print('[AxisChartScaffoldWidget]   ${currentMatrix.row2}');
    // print('[AxisChartScaffoldWidget]   ${currentMatrix.row3}');

    final double scaleX =
        currentMatrix.getMaxScaleOnAxis(); // A way to get overall scale
    // Alternatively, if you know it's primarily a 2D scale and translation:
    // final double scaleX = currentMatrix.entry(0, 0);
    // final double scaleY = currentMatrix.entry(1, 1);
    final double translateX = currentMatrix.entry(0, 3);
    final double translateY = currentMatrix.entry(1, 3);

    // print('[AxisChartScaffoldWidget] Extracted Scale X (approx): $scaleX');
    // print('[AxisChartScaffoldWidget] Extracted Scale Y: $scaleY');
    // print('[AxisChartScaffoldWidget] Extracted Translation X: $translateX');
    // print('[AxisChartScaffoldWidget] Extracted Translation Y: $translateY');

    // _calculateAdjustedRect uses _transformationController.value, which is up-to-date
    // because _transformationControllerListener calls setState before _notifyViewportChange.
    final Rect? virtualRect = _calculateAdjustedRect(viewRect);
    if (virtualRect == null) {
      // print(
        // '[AxisChartScaffoldWidget] virtualRect is null (no effective transformation / scale is 1.0). Notifying with full data range.',
      // );
      if (widget.data.minX != null && widget.data.maxX != null) {
        widget.transformationConfig.onViewportChanged!(
          widget.data.minX!,
          widget.data.maxX!,
        );
      }
      return;
    }
    // print(
      // '[AxisChartScaffoldWidget] virtualRect (transformed viewRect): $virtualRect',
    // );

    final double dataMinX = widget.data.minX ?? 0;
    final double dataMaxX =
        widget.data.maxX ?? 1; // Default to 1 if null to avoid division by zero
    // print('[AxisChartScaffoldWidget] dataMinX: $dataMinX, dataMaxX: $dataMaxX');

    final double dataRangeX = dataMaxX - dataMinX;
    if (dataRangeX <= 0) {
      // print(
        // '[AxisChartScaffoldWidget] EXIT: dataRangeX is <= 0 ($dataRangeX). Cannot calculate viewport.',
      // );
      // Optionally notify with full range if sensible, or do nothing
      if (widget.data.minX != null && widget.data.maxX != null) {
        widget.transformationConfig.onViewportChanged!(
          widget.data.minX!,
          widget.data.maxX!,
        );
      }
      return;
    }
    // print('[AxisChartScaffoldWidget] dataRangeX: $dataRangeX');

    // The width of the content area if it were drawn without any scaling.
    // This should correspond to the viewRect's width when scale is 1.0.
    // When scaled, virtualRect.width represents the original content width
    // that is now *contained* within the viewRect.
    // However, our goal is to map the *current* viewRect boundaries (0 to viewRect.width)
    // back to the data coordinate system, considering the zoom/pan.

    // The virtualRect's left and right are in the *unscaled* content's coordinate space.
    // We need to find out what proportion of the *total unscaled content width that fits the data range*
    // these virtualRect boundaries represent.

    // If scale is 1, virtualRect is viewRect.
    // If we are zoomed in (scale > 1), virtualRect is smaller than viewRect.
    // The `currentContentWidth` used below should represent the width of the
    // chart's content *as if it were laid out to fit the current dataMinX to dataMaxX range,
    // without any interactive scaling applied by the TransformationController yet*.
    // This is essentially viewRect.width because the chart painter draws into that rect.
    final double currentContentWidth = viewRect.width;
    // print(
      // '[AxisChartScaffoldWidget] currentContentWidth (viewRect.width): $currentContentWidth',
    // );

    if (currentContentWidth == 0) {
      // print(
        // '[AxisChartScaffoldWidget] EXIT: currentContentWidth is 0. Cannot calculate viewport.',
      // );
      return;
    }

    // virtualRect.left is the x-coordinate in the chart's untransformed content space
    // that is currently aligned with the left edge of the viewport.
    // virtualRect.width is the total width of the chart's untransformed content
    // that is currently visible in the viewport.

    // The proportion of the data range that is to the left of the viewport's left edge
    // is (virtualRect.left / currentContentWidth).
    // The x-value at the left edge of the viewport is dataMinX + (this proportion) * dataRangeX.
    // This seems more direct.

    // Let's consider the transformation:
    // screen_x = content_x * scale + translate_x
    // content_x = (screen_x - translate_x) / scale
    // Here, screen_x = 0 (left edge of viewRect) and screen_x = viewRect.width (right edge)
    // content_x_left_edge = (0 - translateX) / scaleX
    // content_x_right_edge = (viewRect.width - translateX) / scaleX
    // These content_x values are relative to the chart's drawing origin (usually 0,0 of its paintable area)

    // The virtualRect.left IS (0 - translateX) / scaleX if viewRect starts at 0.
    // The virtualRect.right IS (viewRect.width - translateX) / scaleX if viewRect starts at 0.
    // So virtualRect.left and virtualRect.right are already the content coordinates we need.

    if (scaleX == 0) {
      print(
        '[AxisChartScaffoldWidget] EXIT: scaleX is 0. Cannot calculate viewport.',
      );
      if (widget.data.minX != null && widget.data.maxX != null) {
        widget.transformationConfig.onViewportChanged!(
          widget.data.minX!,
          widget.data.maxX!,
        );
      }
      return;
    }

    // Content X-coordinate (in the space of viewRect.width) at the left edge of the viewport
    final double contentXAtViewLeft = (0 - translateX) / scaleX;
    // Content X-coordinate (in the space of viewRect.width) at the right edge of the viewport
    final double contentXAtViewRight =
        (currentContentWidth - translateX) / scaleX;

    // Map these content coordinates to data coordinates
    final double calculatedVisibleMinX =
        dataMinX + (contentXAtViewLeft / currentContentWidth) * dataRangeX;
    final double calculatedVisibleMaxX =
        dataMinX + (contentXAtViewRight / currentContentWidth) * dataRangeX;

    // print(
      // '[AxisChartScaffoldWidget] Calculated raw visibleMinX: $calculatedVisibleMinX, visibleMaxX: $calculatedVisibleMaxX',
    // );

    // Pass the raw calculated values. The client can decide how to interpret them.
    widget.transformationConfig.onViewportChanged!(
      calculatedVisibleMinX,
      calculatedVisibleMaxX,
    );
  }

  // Applies the inverse transformation to the chart to get the zoomed
  // bounding box.
  //
  // The transformation matrix is inverted because the bounding box needs to
  // grow beyond the chart's boundaries when the chart is scaled in order
  // for its content to be laid out on the larger area. This leads to the
  // scaling effect.
  Rect? _calculateAdjustedRect(Rect rect) {
    final scale = _transformationController.value.getMaxScaleOnAxis();
    if (scale == 1.0) {
      return null;
    }
    final inverseMatrix = Matrix4.inverted(_transformationController.value);

    final chartVirtualQuad = CustomInteractiveViewer.transformViewport(
      inverseMatrix,
      rect,
    );

    final chartVirtualRect = CustomInteractiveViewer.axisAlignedBoundingBox(
      chartVirtualQuad,
    );

    return Rect.fromLTWH(
      _canScaleHorizontally ? chartVirtualRect.left : rect.left,
      _canScaleVertically ? chartVirtualRect.top : rect.top,
      _canScaleHorizontally ? chartVirtualRect.width : rect.width,
      _canScaleVertically ? chartVirtualRect.height : rect.height,
    );
  }

  bool get showLeftTitles {
    if (!widget.data.titlesData.show) {
      return false;
    }
    final showAxisTitles = widget.data.titlesData.leftTitles.showAxisTitles;
    final showSideTitles = widget.data.titlesData.leftTitles.showSideTitles;
    return showAxisTitles || showSideTitles;
  }

  bool get showRightTitles {
    if (!widget.data.titlesData.show) {
      return false;
    }
    final showAxisTitles = widget.data.titlesData.rightTitles.showAxisTitles;
    final showSideTitles = widget.data.titlesData.rightTitles.showSideTitles;
    return showAxisTitles || showSideTitles;
  }

  bool get showTopTitles {
    if (!widget.data.titlesData.show) {
      return false;
    }
    final showAxisTitles = widget.data.titlesData.topTitles.showAxisTitles;
    final showSideTitles = widget.data.titlesData.topTitles.showSideTitles;
    return showAxisTitles || showSideTitles;
  }

  bool get showBottomTitles {
    if (!widget.data.titlesData.show) {
      return false;
    }
    final showAxisTitles = widget.data.titlesData.bottomTitles.showAxisTitles;
    final showSideTitles = widget.data.titlesData.bottomTitles.showSideTitles;
    return showAxisTitles || showSideTitles;
  }

  List<Widget> _stackWidgets(BoxConstraints constraints) {
    final margin = widget.data.titlesData.allSidesPadding;
    final borderData =
        widget.data.borderData.isVisible()
            ? widget.data.borderData.border
            : null;

    final borderWidth =
        borderData == null ? 0 : borderData.dimensions.horizontal;
    final borderHeight =
        borderData == null ? 0 : borderData.dimensions.vertical;

    final rect = Rect.fromLTRB(
      0,
      0,
      constraints.maxWidth - margin.horizontal - borderWidth,
      constraints.maxHeight - margin.vertical - borderHeight,
    );
    _lastKnownViewRect = rect;

    final adjustedRect = _calculateAdjustedRect(rect);

    final virtualRect = switch (_transformationConfig.scaleAxis) {
      FlScaleAxis.none => null,
      FlScaleAxis() => adjustedRect,
    };

    final chart = KeyedSubtree(
      key: _chartKey,
      child: widget.chartBuilder(context, virtualRect),
    );

    final child = switch (_transformationConfig.scaleAxis) {
      FlScaleAxis.none => chart,
      FlScaleAxis() => CustomInteractiveViewer(
        transformationController: _transformationController,
        clipBehavior: Clip.none,
        trackpadScrollCausesScale:
            _transformationConfig.trackpadScrollCausesScale,
        maxScale: _transformationConfig.maxScale,
        minScale: _transformationConfig.minScale,
        panEnabled: _transformationConfig.panEnabled,
        scaleEnabled: _transformationConfig.scaleEnabled,
        child: SizedBox(width: rect.width, height: rect.height, child: chart),
      ),
    };

    final widgets = <Widget>[
      Container(
        margin: margin,
        decoration: BoxDecoration(border: borderData),
        child: child,
      ),
    ];

    int insertIndex(bool drawBelow) => drawBelow ? 0 : widgets.length;

    if (showLeftTitles) {
      widgets.insert(
        insertIndex(widget.data.titlesData.leftTitles.drawBelowEverything),
        SideTitlesWidget(
          side: AxisSide.left,
          axisChartData: widget.data,
          parentSize: constraints.biggest,
          chartVirtualRect: adjustedRect,
        ),
      );
    }

    if (showTopTitles) {
      widgets.insert(
        insertIndex(widget.data.titlesData.topTitles.drawBelowEverything),
        SideTitlesWidget(
          side: AxisSide.top,
          axisChartData: widget.data,
          parentSize: constraints.biggest,
          chartVirtualRect: adjustedRect,
        ),
      );
    }

    if (showRightTitles) {
      widgets.insert(
        insertIndex(widget.data.titlesData.rightTitles.drawBelowEverything),
        SideTitlesWidget(
          side: AxisSide.right,
          axisChartData: widget.data,
          parentSize: constraints.biggest,
          chartVirtualRect: adjustedRect,
        ),
      );
    }

    if (showBottomTitles) {
      widgets.insert(
        insertIndex(widget.data.titlesData.bottomTitles.drawBelowEverything),
        SideTitlesWidget(
          side: AxisSide.bottom,
          axisChartData: widget.data,
          parentSize: constraints.biggest,
          chartVirtualRect: adjustedRect,
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return RotatedBox(
          quarterTurns: widget.data.rotationQuarterTurns,
          child: Stack(children: _stackWidgets(constraints)),
        );
      },
    );
  }
}
