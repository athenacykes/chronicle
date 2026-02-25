import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/matter_graph_data.dart';
import '../../../domain/entities/matter_graph_edge.dart';
import '../../../domain/entities/matter_graph_node.dart';
import '../../../l10n/localization.dart';

class ChronicleGraphNodePreviewCard extends StatelessWidget {
  const ChronicleGraphNodePreviewCard({
    super.key,
    required this.node,
    required this.onPreview,
  });

  final MatterGraphNode node;
  final Future<void> Function() onPreview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isMacOSNativeUI = _isMacOSNativeUI(context);
    final label = node.title.trim().isEmpty ? l10n.untitledLabel : node.title;
    return Container(
      width: 220,
      decoration: isMacOSNativeUI
          ? _macosPanelDecoration(context)
          : BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GestureDetector(
                onTap: () async {
                  await onPreview();
                },
                child: CircleAvatar(
                  radius: 14,
                  child: Text(label.substring(0, 1).toUpperCase()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('yyyy-MM-dd').format(node.updatedAt.toLocal()),
            style: isMacOSNativeUI
                ? MacosTheme.of(context).typography.caption1
                : Theme.of(context).textTheme.bodySmall,
          ),
          const Spacer(),
          Align(
            alignment: Alignment.centerRight,
            child: isMacOSNativeUI
                ? PushButton(
                    controlSize: ControlSize.regular,
                    onPressed: () async {
                      await onPreview();
                    },
                    child: const Text('Preview'),
                  )
                : OutlinedButton(
                    onPressed: () async {
                      await onPreview();
                    },
                    child: const Text('Preview'),
                  ),
          ),
        ],
      ),
    );
  }
}

class ChronicleGraphCanvas extends StatelessWidget {
  const ChronicleGraphCanvas({
    super.key,
    required this.graph,
    required this.selectedNoteId,
    required this.onTapNode,
    required this.createDragPayload,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final MatterGraphData graph;
  final String? selectedNoteId;
  final Future<void> Function(String noteId) onTapNode;
  final Object Function(MatterGraphNode node) createDragPayload;
  final void Function(Object payload) onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final layout = _deterministicGraphLayout(graph);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.25,
        maxScale: 3.0,
        boundaryMargin: const EdgeInsets.all(220),
        child: SizedBox(
          width: layout.canvasSize.width,
          height: layout.canvasSize.height,
          child: Stack(
            children: <Widget>[
              CustomPaint(
                size: layout.canvasSize,
                painter: _GraphEdgesPainter(
                  edges: graph.edges,
                  positions: layout.positions,
                  selectedNoteId: selectedNoteId,
                  edgeColor: theme.colorScheme.outlineVariant,
                ),
              ),
              ...graph.nodes.map((node) {
                final offset = layout.positions[node.noteId];
                if (offset == null) {
                  return const SizedBox.shrink();
                }

                final isSelected = node.noteId == selectedNoteId;
                final nodeColor = isSelected
                    ? theme.colorScheme.primary
                    : node.isInSelectedMatter
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.secondaryContainer;
                final textColor = isSelected
                    ? theme.colorScheme.onPrimary
                    : node.isInSelectedMatter
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSecondaryContainer;
                final radius = isSelected
                    ? 24.0
                    : node.isPinned
                    ? 20.0
                    : 17.0;

                final nodeWidget = Tooltip(
                  message: node.title.isEmpty
                      ? context.l10n.untitledLabel
                      : node.title,
                  child: InkWell(
                    onTap: () async => onTapNode(node.noteId),
                    borderRadius: BorderRadius.circular(radius),
                    child: Container(
                      width: radius * 2,
                      height: radius * 2,
                      decoration: BoxDecoration(
                        color: nodeColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.outline,
                          width: node.isInSelectedMatter ? 1.2 : 0.8,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        _nodeLabel(node),
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                );

                final payload = createDragPayload(node);

                return Positioned(
                  left: offset.dx - radius,
                  top: offset.dy - radius,
                  child: LongPressDraggable<Object>(
                    key: ValueKey<String>('note_drag_graph_${node.noteId}'),
                    data: payload,
                    delay: const Duration(milliseconds: 180),
                    onDragStarted: () {
                      onDragStarted(payload);
                    },
                    onDraggableCanceled: (velocity, offset) {
                      onDragEnded();
                    },
                    onDragCompleted: () {
                      onDragEnded();
                    },
                    onDragEnd: (_) {
                      onDragEnded();
                    },
                    feedback: Material(
                      type: MaterialType.transparency,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 280),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(188),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          node.title.trim().isEmpty
                              ? context.l10n.untitledLabel
                              : node.title.trim(),
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    childWhenDragging: Opacity(
                      opacity: 0.35,
                      child: nodeWidget,
                    ),
                    child: nodeWidget,
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _nodeLabel(MatterGraphNode node) {
    final title = node.title.trim();
    if (title.isEmpty) {
      return '?';
    }
    return title.substring(0, 1).toUpperCase();
  }
}

class _GraphEdgesPainter extends CustomPainter {
  const _GraphEdgesPainter({
    required this.edges,
    required this.positions,
    required this.selectedNoteId,
    required this.edgeColor,
  });

  final List<MatterGraphEdge> edges;
  final Map<String, Offset> positions;
  final String? selectedNoteId;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final basePaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final selectedPaint = Paint()
      ..color = edgeColor.withValues(alpha: 0.85)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    for (final edge in edges) {
      final source = positions[edge.sourceNoteId];
      final target = positions[edge.targetNoteId];
      if (source == null || target == null) {
        continue;
      }

      final selected =
          selectedNoteId != null &&
          (edge.sourceNoteId == selectedNoteId ||
              edge.targetNoteId == selectedNoteId);
      canvas.drawLine(source, target, selected ? selectedPaint : basePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GraphEdgesPainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.selectedNoteId != selectedNoteId ||
        oldDelegate.edgeColor != edgeColor;
  }
}

_GraphLayout _deterministicGraphLayout(MatterGraphData graph) {
  const canvas = Size(1600, 1100);
  final center = Offset(canvas.width / 2, canvas.height / 2);
  final primary = graph.nodes.where((node) => node.isInSelectedMatter).toList();
  final external = graph.nodes
      .where((node) => !node.isInSelectedMatter)
      .toList();

  final positions = <String, Offset>{};
  final primaryNodes = primary.isEmpty ? graph.nodes : primary;
  final externalNodes = primary.isEmpty ? const <MatterGraphNode>[] : external;

  _assignCircular(
    positions: positions,
    nodes: primaryNodes,
    center: center,
    radius: primaryNodes.length <= 1 ? 0 : 280,
    phaseOffset: 0,
  );
  _assignCircular(
    positions: positions,
    nodes: externalNodes,
    center: center,
    radius: 470,
    phaseOffset: math.pi / 6,
  );

  return _GraphLayout(canvasSize: canvas, positions: positions);
}

void _assignCircular({
  required Map<String, Offset> positions,
  required List<MatterGraphNode> nodes,
  required Offset center,
  required double radius,
  required double phaseOffset,
}) {
  if (nodes.isEmpty) {
    return;
  }
  if (nodes.length == 1 || radius == 0) {
    positions[nodes.first.noteId] = center;
    return;
  }

  for (var i = 0; i < nodes.length; i++) {
    final angle = (2 * math.pi * (i / nodes.length)) + phaseOffset;
    final dx = center.dx + (math.cos(angle) * radius);
    final dy = center.dy + (math.sin(angle) * radius);
    positions[nodes[i].noteId] = Offset(dx, dy);
  }
}

class _GraphLayout {
  const _GraphLayout({required this.canvasSize, required this.positions});

  final Size canvasSize;
  final Map<String, Offset> positions;
}

bool _isMacOSNativeUI(BuildContext context) {
  return MacosTheme.maybeOf(context) != null;
}

BoxDecoration _macosPanelDecoration(BuildContext context) {
  final brightness = MacosTheme.brightnessOf(context);
  return BoxDecoration(
    color: brightness.resolve(const Color(0xFFFDFDFD), const Color(0xFF202327)),
    border: Border.all(color: MacosTheme.of(context).dividerColor),
    borderRadius: BorderRadius.circular(8),
  );
}
