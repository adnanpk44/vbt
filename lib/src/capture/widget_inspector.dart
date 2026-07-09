import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'capture_models.dart';

/// Hit-tests the Flutter render tree and builds a selector trail for the tapped widget.
class FlutterWidgetInspector {
  const FlutterWidgetInspector();

  FlutterWidgetHit? hitTestAt(Offset globalPosition, {BuildContext? routeContext}) {
    final result = HitTestResult();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;

    WidgetsBinding.instance.hitTestInView(result, globalPosition, views.first.viewId);

    RenderBox? targetBox;
    final ancestorTrail = <String>[];

    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderBox) continue;
      if (target is RenderView) continue;
      if (!_isInspectableBox(target)) continue;

      final label = _widgetLabel(target);
      if (label.isEmpty) continue;

      if (targetBox == null) {
        targetBox = target;
      } else if (!ancestorTrail.contains(label)) {
        ancestorTrail.add(label);
      }
    }

    if (targetBox == null) return null;

    final rect = _globalRect(targetBox);
    if (rect == null || rect.width < 2 || rect.height < 2) return null;

    final widgetType = _widgetType(targetBox);
    final widgetKey = _widgetKey(targetBox);
    final selector = _buildSelector(widgetType: widgetType, widgetKey: widgetKey, ancestors: ancestorTrail);
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
      globalRect: rect,
      ancestorTrail: ancestorTrail,
    );
  }

  bool _isInspectableBox(RenderBox box) {
    final size = box.size;
    if (size.width < 2 || size.height < 2) return false;
    final typeName = box.runtimeType.toString();
    if (typeName.contains('VibeBug') ||
        typeName.contains('ModalBarrier') ||
        typeName.contains('SnapshotWidget')) {
      return false;
    }
    final creator = _creatorWidget(box);
    if (creator != null) {
      final widgetType = creator.runtimeType.toString();
      if (widgetType.contains('VibeBug') || widgetType.contains('ModalBarrier')) {
        return false;
      }
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
    if (creator == null) return box.runtimeType.toString();
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
    final keyPart = widgetKey == null || widgetKey.isEmpty ? '' : '[key=$widgetKey]';
    final chain = ancestors.isEmpty ? widgetType : ancestors.reversed.join('>');
    return 'flutter:$widgetType$keyPart>$chain';
  }

  String _semanticsLabel(RenderBox box) {
    final creator = _creatorWidget(box);
    if (creator is Semantics) {
      return creator.properties.label ?? creator.properties.value ?? '';
    }
    if (creator is Text) {
      if (creator.data != null && creator.data!.isNotEmpty) return creator.data!;
      if (creator.textSpan != null) return creator.textSpan!.toPlainText();
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
      ..writeln('size: ${box.size.width.toStringAsFixed(1)} x ${box.size.height.toStringAsFixed(1)}');
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
        type.contains('Semantics') ||
        type.contains('Builder');
  }
}
