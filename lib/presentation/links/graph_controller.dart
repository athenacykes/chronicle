import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_providers.dart';
import '../../domain/entities/matter_graph_data.dart';
import '../../domain/entities/matter_graph_edge.dart';
import '../../domain/entities/matter_graph_node.dart';
import '../../domain/usecases/links/build_matter_graph.dart';
import '../matters/matters_controller.dart';

const graphNodeLimit = 300;

final graphControllerProvider =
    AsyncNotifierProvider<GraphController, GraphViewState>(GraphController.new);

class GraphController extends AsyncNotifier<GraphViewState> {
  @override
  Future<GraphViewState> build() async {
    final matterId = ref.watch(selectedMatterIdProvider);
    if (matterId == null || matterId.isEmpty) {
      return GraphViewState.empty(DateTime.now().toUtc());
    }

    return _load(matterId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    final matterId = ref.read(selectedMatterIdProvider);
    if (matterId == null || matterId.isEmpty) {
      state = AsyncData(GraphViewState.empty(DateTime.now().toUtc()));
      return;
    }
    state = AsyncData(await _load(matterId));
  }

  Future<GraphViewState> _load(String matterId) async {
    final useCase = BuildMatterGraph(
      ref.read(noteRepositoryProvider),
      ref.read(linkRepositoryProvider),
    );
    final data = await useCase.call(matterId: matterId);

    final sortedNodes = <MatterGraphNode>[...data.nodes]
      ..sort((a, b) {
        final updated = b.updatedAt.compareTo(a.updatedAt);
        if (updated != 0) {
          return updated;
        }
        return a.noteId.compareTo(b.noteId);
      });

    final cappedNodes = sortedNodes.take(graphNodeLimit).toList();
    final includedIds = cappedNodes.map((node) => node.noteId).toSet();

    final cappedEdges =
        data.edges
            .where(
              (edge) =>
                  includedIds.contains(edge.sourceNoteId) &&
                  includedIds.contains(edge.targetNoteId),
            )
            .toList()
          ..sort((a, b) {
            final created = b.createdAt.compareTo(a.createdAt);
            if (created != 0) {
              return created;
            }
            return a.linkId.compareTo(b.linkId);
          });

    return GraphViewState(
      graph: MatterGraphData(
        nodes: cappedNodes,
        edges: <MatterGraphEdge>[...cappedEdges],
        generatedAt: data.generatedAt,
      ),
      totalNodeCount: sortedNodes.length,
    );
  }
}

class GraphViewState {
  const GraphViewState({required this.graph, required this.totalNodeCount});

  final MatterGraphData graph;
  final int totalNodeCount;

  bool get isTruncated => totalNodeCount > graph.nodes.length;

  int get truncatedNodeCount {
    if (!isTruncated) {
      return 0;
    }
    return totalNodeCount - graph.nodes.length;
  }

  factory GraphViewState.empty(DateTime now) {
    return GraphViewState(graph: MatterGraphData.empty(now), totalNodeCount: 0);
  }
}
