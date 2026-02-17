import 'matter_graph_edge.dart';
import 'matter_graph_node.dart';

class MatterGraphData {
  const MatterGraphData({
    required this.nodes,
    required this.edges,
    required this.generatedAt,
  });

  final List<MatterGraphNode> nodes;
  final List<MatterGraphEdge> edges;
  final DateTime generatedAt;

  factory MatterGraphData.empty(DateTime generatedAt) {
    return MatterGraphData(
      nodes: const <MatterGraphNode>[],
      edges: const <MatterGraphEdge>[],
      generatedAt: generatedAt,
    );
  }
}
