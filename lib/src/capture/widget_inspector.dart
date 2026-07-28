import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'capture_models.dart';

/// Hit-tests the Flutter render tree and builds a selector trail for the tapped widget.
class FlutterWidgetInspector {
  const FlutterWidgetInspector();

  FlutterWidgetHit? hitTestAt(
    Offset globalPosition, {
    BuildContext? routeContext,
    GlobalKey? boundaryKey,
    RenderObject? excludeSubtreeRoot,
  }) {
    final result = HitTestResult();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;

    WidgetsBinding.instance
        .hitTestInView(result, globalPosition, views.first.viewId);

    final boundaryObject = boundaryKey?.currentContext?.findRenderObject();
    final viewSize = views.first.physicalSize / views.first.devicePixelRatio;
    final candidates = <_HitCandidate>[];

    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderBox) continue;
      if (target is RenderView) continue;
      if (boundaryObject != null && !_isDescendantOf(target, boundaryObject)) {
        continue;
      }
      if (excludeSubtreeRoot != null &&
          _isDescendantOf(target, excludeSubtreeRoot)) {
        continue;
      }
      if (!_isInspectableBox(target, viewSize)) continue;

      final label = _widgetLabel(target);
      if (label.isEmpty) continue;

      final rect = _globalRect(target);
      if (rect == null || rect.width < 2 || rect.height < 2) continue;
      if (!rect.inflate(1).contains(globalPosition)) continue;

      candidates.add(
        _HitCandidate(
          box: target,
          label: label,
          rect: rect,
          score: _scoreCandidate(target, rect, viewSize),
        ),
      );
    }

    if (candidates.isEmpty) return null;

    candidates.sort((a, b) => a.score.compareTo(b.score));
    final best = candidates.first;
    final targetBox = best.box;

    final ancestorTrail = <String>[];
    for (final candidate in candidates.skip(1)) {
      if (!ancestorTrail.contains(candidate.label)) {
        ancestorTrail.add(candidate.label);
      }
      if (ancestorTrail.length >= 8) break;
    }

    final widgetType = _widgetType(targetBox);
    final widgetKey = _widgetKey(targetBox);
    final selector = _buildSelector(
      widgetType: widgetType,
      widgetKey: widgetKey,
      ancestors: ancestorTrail,
    );
    final semanticsLabel = _semanticsLabel(targetBox);
    final widgetSnippet = _widgetSnippet(targetBox, semanticsLabel);
    final routeName = _routeName(routeContext);

    return FlutterWidgetHit(
      widgetType: widgetType,
      widgetKey: widgetKey,
      selector: selector,
      semanticsLabel: semanticsLabel,
      widgetSnippet: widgetSnippet,
      routeName: routeName,
      globalRect: best.rect,
      ancestorTrail: ancestorTrail,
    );
  }

  /// Lower score = better target. Prefer compact, labeled, interactive widgets.
  double _scoreCandidate(RenderBox box, Rect rect, Size viewSize) {
    final area = rect.width * rect.height;
    final viewArea = (viewSize.width * viewSize.height).clamp(1.0, double.infinity);
    var score = area;

    // Heavily penalize near-fullscreen shells (Scaffold body, Overlay theater, etc.).
    final coverage = area / viewArea;
    if (coverage > 0.85) score += 1e9;
    if (coverage > 0.55) score += 1e7;

    final type = _widgetType(box);
    if (_isShellWidget(type)) score += 5e6;
    if (_isInteractiveWidget(type)) score -= 5000;
    if (_semanticsLabel(box).isNotEmpty) score -= 2500;
    if (_widgetKey(box) != null) score -= 1500;

    // Slight preference for widgets closer to typical control size.
    final ideal = 120.0 * 48.0;
    score += (area - ideal).abs() * 0.01;

    return score;
  }

  bool _isInspectableBox(RenderBox box, Size viewSize) {
    final size = box.size;
    if (size.width < 2 || size.height < 2) return false;
    final typeName = box.runtimeType.toString();
    if (_isNoiseRenderObject(typeName)) return false;

    final creator = _creatorWidget(box);
    if (creator != null) {
      final widgetType = creator.runtimeType.toString();
      if (_isNoiseWidget(widgetType)) return false;
      if (widgetType.contains('VibeBug') ||
          widgetType.contains('ModalBarrier')) {
        return false;
      }
    } else if (typeName.contains('VibeBug') ||
        typeName.contains('ModalBarrier') ||
        typeName.contains('SnapshotWidget')) {
      return false;
    }

    final area = size.width * size.height;
    final viewArea = viewSize.width * viewSize.height;
    if (viewArea > 0 && area / viewArea > 0.92) {
      // Keep only if it might be the only candidate; scoring will demote it.
      return true;
    }
    return true;
  }

  Rect? _globalRect(RenderBox box) {
    try {
      final offset = box.localToGlobal(Offset.zero);
      return offset & box.size;
    } catch (_) {
      return null;
    }
  }

  Widget? _creatorWidget(RenderBox box) {
    final creator = box.debugCreator;
    if (creator is DebugCreator) return creator.element.widget;
    return null;
  }

  String _widgetLabel(RenderBox box) {
    final creator = _creatorWidget(box);
    if (creator == null) {
      final type = box.runtimeType.toString();
      if (_isNoiseRenderObject(type)) return '';
      return type;
    }
    final type = creator.runtimeType.toString();
    if (_isNoiseWidget(type)) return '';
    final key = creator.key;
    if (key == null) return type;
    if (key is ValueKey) return '$type[key=${key.value}]';
    return '$type[key=$key]';
  }

  String _widgetType(RenderBox box) {
    final creator = _creatorWidget(box);
    if (creator != null) return creator.runtimeType.toString();
    return box.runtimeType.toString();
  }

  String? _widgetKey(RenderBox box) {
    final key = _creatorWidget(box)?.key;
    if (key == null) return null;
    if (key is ValueKey) return key.value?.toString();
    if (key is ObjectKey) return key.value?.toString();
    return key.toString();
  }

  String _buildSelector({
    required String widgetType,
    required String? widgetKey,
    required List<String> ancestors,
  }) {
    final keyPart =
        widgetKey == null || widgetKey.isEmpty ? '' : '[key=$widgetKey]';
    final chain = ancestors.isEmpty ? widgetType : ancestors.reversed.join('>');
    return 'flutter:$widgetType$keyPart>$chain';
  }

  String _semanticsLabel(RenderBox box) {
    final creator = _creatorWidget(box);
    if (creator is Semantics) {
      return creator.properties.label ?? creator.properties.value ?? '';
    }
    if (creator is Text) {
      if (creator.data != null && creator.data!.isNotEmpty) {
        return creator.data!;
      }
      if (creator.textSpan != null) {
        return creator.textSpan!.toPlainText();
      }
    }
    if (creator is Icon) {
      return creator.semanticLabel ?? '';
    }
    if (creator is Tooltip) {
      return creator.message ?? '';
    }
    return '';
  }

  String _widgetSnippet(RenderBox box, String semanticsLabel) {
    final buffer = StringBuffer()
      ..writeln('widget: ${_widgetType(box)}')
      ..writeln('renderObject: ${box.runtimeType}')
      ..writeln(
          'size: ${box.size.width.toStringAsFixed(1)} x ${box.size.height.toStringAsFixed(1)}');
    if (semanticsLabel.isNotEmpty) {
      buffer.writeln('semantics: $semanticsLabel');
    }
    final creator = box.debugCreator;
    if (creator != null && kDebugMode) {
      buffer.writeln('creator: $creator');
    }
    return buffer.toString().trim();
  }

  String _routeName(BuildContext? context) {
    if (context == null) return '';
    final route = ModalRoute.of(context);
    if (route == null) return '';
    return route.settings.name ?? route.runtimeType.toString();
  }

  bool _isNoiseWidget(String type) {
    return type.contains('Inherited') ||
        type.contains('Listener') ||
        type.contains('IgnorePointer') ||
        type.contains('AbsorbPointer') ||
        type.contains('Semantics') ||
        type.contains('Builder') ||
        type.contains('AnnotatedRegion') ||
        type.contains('TapRegion') ||
        type.contains('ExcludeSemantics') ||
        type.contains('BlockSemantics') ||
        type == '_Theater' ||
        type.contains('Overlay') ||
        type.contains('SnapshotWidget') ||
        type.contains('VibeBug');
  }

  bool _isNoiseRenderObject(String type) {
    return type.contains('AbsorbPointer') ||
        type.contains('IgnorePointer') ||
        type.contains('Semantics') ||
        type.contains('AnnotatedRegion') ||
        type.contains('Theater') ||
        type.contains('Overlay') ||
        type.contains('ModalBarrier') ||
        type.contains('SnapshotWidget') ||
        type.contains('VibeBug');
  }

  bool _isShellWidget(String type) {
    return type.contains('Scaffold') ||
        type.contains('MaterialApp') ||
        type.contains('CupertinoApp') ||
        type.contains('Navigator') ||
        type.contains('Theater') ||
        type.contains('Overlay') ||
        type == 'Material' ||
        type == 'DecoratedBox' ||
        type == 'ColoredBox';
  }

  bool _isInteractiveWidget(String type) {
    return type.contains('Button') ||
        type.contains('TextField') ||
        type.contains('TextFormField') ||
        type.contains('Checkbox') ||
        type.contains('Switch') ||
        type.contains('Slider') ||
        type.contains('InkWell') ||
        type.contains('GestureDetector') ||
        type.contains('ListTile') ||
        type.contains('IconButton') ||
        type.contains('Tab') ||
        type.contains('Chip');
  }

  bool _isDescendantOf(RenderObject node, RenderObject ancestor) {
    RenderObject? current = node;
    while (current != null) {
      if (current == ancestor) return true;
      current = current.parent;
    }
    return false;
  }
}

class _HitCandidate {
  const _HitCandidate({
    required this.box,
    required this.label,
    required this.rect,
    required this.score,
  });

  final RenderBox box;
  final String label;
  final Rect rect;
  final double score;
}
