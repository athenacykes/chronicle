import 'category.dart';
import 'matter.dart';

class MatterCategorySection {
  const MatterCategorySection({required this.category, required this.matters});

  final Category category;
  final List<Matter> matters;
}

class MatterSections {
  const MatterSections({
    required this.pinned,
    required this.categorySections,
    required this.uncategorized,
  });

  final List<Matter> pinned;
  final List<MatterCategorySection> categorySections;
  final List<Matter> uncategorized;
}
