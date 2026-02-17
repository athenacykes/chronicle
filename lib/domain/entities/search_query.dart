class SearchQuery {
  const SearchQuery({
    required this.text,
    this.tags = const <String>[],
    this.matterId,
    this.from,
    this.to,
  });

  final String text;
  final List<String> tags;
  final String? matterId;
  final DateTime? from;
  final DateTime? to;
}
