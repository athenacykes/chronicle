import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../../domain/entities/note.dart';
import '../../../domain/entities/note_search_hit.dart';
import '../../../domain/entities/notebook_folder.dart';
import '../../../domain/entities/phase.dart';
import '../../../domain/entities/search_query.dart';
import '../../../domain/repositories/matter_repository.dart';
import '../../../domain/repositories/notebook_repository.dart';
import '../../../domain/repositories/search_repository.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../l10n/localization.dart';
import 'chronicle_macos_fixed_dialog.dart';

class ChronicleLinkNoteDialogResult {
  const ChronicleLinkNoteDialogResult({
    required this.targetNoteIds,
    required this.context,
  });

  final List<String> targetNoteIds;
  final String context;
}

class ChronicleLinkNoteDialog extends StatefulWidget {
  const ChronicleLinkNoteDialog({
    super.key,
    required this.sourceNote,
    required this.searchRepository,
    required this.matterRepository,
    required this.notebookRepository,
    required this.useMacOSNativeUI,
  });

  final Note sourceNote;
  final SearchRepository searchRepository;
  final MatterRepository matterRepository;
  final NotebookRepository notebookRepository;
  final bool useMacOSNativeUI;

  @override
  State<ChronicleLinkNoteDialog> createState() =>
      _ChronicleLinkNoteDialogState();
}

class _ChronicleLinkNoteDialogState extends State<ChronicleLinkNoteDialog> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _contextController = TextEditingController();
  final Set<String> _selectedNoteIds = <String>{};
  List<NoteSearchHit> _searchResults = <NoteSearchHit>[];
  bool _isSearching = false;
  String? _sourceNoteLocation;
  Timer? _debounceTimer;

  static const int _minSearchLength = 2;
  static const int _maxResults = 50;

  @override
  void initState() {
    super.initState();
    _loadSourceNoteLocation();
  }

  Future<void> _loadSourceNoteLocation() async {
    final location = await _getNoteLocation(widget.sourceNote);
    if (mounted) {
      setState(() {
        _sourceNoteLocation = location;
      });
    }
  }

  Future<String> _getNoteLocation(Note note) async {
    final l10n = context.l10n;
    if (note.matterId == null || note.phaseId == null) {
      // Notebook note - try to get folder name
      try {
        final folders = await widget.notebookRepository.listFolders();
        final folder = folders.firstWhere(
          (f) => f.id == note.notebookFolderId,
          orElse: () => NotebookFolder(
            id: '',
            name: '',
            parentId: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        if (folder.name.isNotEmpty) {
          return '${l10n.notebookLabel} / ${folder.name}';
        }
      } catch (_) {
        // Fall through to default
      }
      return l10n.notebookLabel;
    }

    // Matter note - get matter and phase names
    try {
      final matter = await widget.matterRepository.getMatterById(note.matterId!);
      if (matter != null) {
        final phase = matter.phases.firstWhere(
          (p) => p.id == note.phaseId,
          orElse: () => Phase(id: '', matterId: '', name: '', order: 0),
        );
        if (phase.name.isNotEmpty) {
          return '${matter.title} - ${phase.name}';
        }
        return matter.title;
      }
    } catch (_) {
      // Fall through to default
    }
    return note.matterId!;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _contextController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(value);
    });
  }

  Future<void> _performSearch(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < _minSearchLength) {
      setState(() {
        _searchResults = <NoteSearchHit>[];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await widget.searchRepository.search(
        SearchQuery(text: trimmedQuery),
      );

      // Filter out the source note and limit results
      final filteredResults = results
          .where((hit) => hit.note.id != widget.sourceNote.id)
          .take(_maxResults)
          .toList();

      if (mounted) {
        setState(() {
          _searchResults = filteredResults;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = <NoteSearchHit>[];
          _isSearching = false;
        });
      }
    }
  }

  void _toggleSelection(String noteId) {
    setState(() {
      if (_selectedNoteIds.contains(noteId)) {
        _selectedNoteIds.remove(noteId);
      } else {
        _selectedNoteIds.add(noteId);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedNoteIds.clear();
    });
  }

  String _formatSnippet(String snippet, String searchQuery) {
    // Limit to approximately 5 lines of text
    final lines = snippet.split('\n');
    if (lines.length > 5) {
      return '${lines.take(5).join('\n')}...';
    }
    if (snippet.length > 300) {
      return '${snippet.substring(0, 300)}...';
    }
    return snippet;
  }

  // Build highlighted text widget with search term
  Widget _buildHighlightedText(String text, String searchQuery, TextStyle? style) {
    if (searchQuery.trim().length < _minSearchLength) {
      return Text(text, style: style, maxLines: 5, overflow: TextOverflow.ellipsis);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = searchQuery.toLowerCase().trim();
    final matches = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        if (start < text.length) {
          matches.add(TextSpan(text: text.substring(start)));
        }
        break;
      }

      if (index > start) {
        matches.add(TextSpan(text: text.substring(start, index)));
      }

      matches.add(TextSpan(
        text: text.substring(index, index + lowerQuery.length),
        style: style?.copyWith(
          backgroundColor: Colors.yellow.withValues(alpha: 0.4),
          fontWeight: FontWeight.w600,
        ),
      ));

      start = index + lowerQuery.length;
    }

    return RichText(
      maxLines: 5,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: style,
        children: matches,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final useMacOSNativeUI = widget.useMacOSNativeUI;
    final hasSelection = _selectedNoteIds.isNotEmpty;

    final content = SizedBox(
      width: 900,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Source note info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: useMacOSNativeUI
                  ? MacosTheme.of(context).dividerColor.withValues(alpha: 0.2)
                  : Theme.of(context).dividerColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.link,
                  size: 16,
                  color: useMacOSNativeUI
                      ? MacosTheme.of(context).typography.body.color
                      : Theme.of(context).textTheme.bodyMedium?.color,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.linkSourceRow(''),
                        style: (useMacOSNativeUI
                                ? MacosTheme.of(context).typography.caption1
                                : Theme.of(context).textTheme.bodySmall)
                            ?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.sourceNote.title.trim().isEmpty
                            ? l10n.untitledLabel
                            : widget.sourceNote.title.trim(),
                        style: useMacOSNativeUI
                            ? MacosTheme.of(context).typography.body
                            : Theme.of(context).textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_sourceNoteLocation != null)
                        Text(
                          _sourceNoteLocation!,
                          style: (useMacOSNativeUI
                                  ? MacosTheme.of(context).typography.caption1
                                  : Theme.of(context).textTheme.bodySmall)
                              ?.copyWith(
                                color: useMacOSNativeUI
                                    ? MacosColors.systemGrayColor
                                    : Colors.grey,
                              ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Search field
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _searchController,
                  placeholder: l10n.linkNoteSearchHint,
                  onChanged: _onSearchChanged,
                  prefix: const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: MacosIcon(CupertinoIcons.search, size: 16),
                  ),
                )
              : TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.linkNoteSearchHint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: _onSearchChanged,
                ),
          const SizedBox(height: 12),

          // Search results - 3 column grid layout
          SizedBox(
            height: 360,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: useMacOSNativeUI
                      ? MacosTheme.of(context).dividerColor
                      : Theme.of(context).dividerColor,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: _buildResultsGrid(useMacOSNativeUI, l10n),
            ),
          ),

          // Selection summary
          if (hasSelection) ...[
            const SizedBox(height: 12),
            _buildSelectionSummary(useMacOSNativeUI, l10n),
          ],

          const SizedBox(height: 12),

          // Context field
          useMacOSNativeUI
              ? MacosTextField(
                  controller: _contextController,
                  placeholder: l10n.contextOptionalLabel,
                  minLines: 2,
                  maxLines: 4,
                )
              : TextField(
                  controller: _contextController,
                  decoration: InputDecoration(
                    labelText: l10n.contextOptionalLabel,
                    hintText: l10n.linkContextHint,
                    border: const OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
        ],
      ),
    );

    void onCreateLink() {
      if (_selectedNoteIds.isEmpty) return;
      Navigator.of(context).pop(
        ChronicleLinkNoteDialogResult(
          targetNoteIds: _selectedNoteIds.toList(),
          context: _contextController.text.trim(),
        ),
      );
    }

    final actionButtonLabel = _selectedNoteIds.length == 1
        ? l10n.linkNoteSingleAction
        : l10n.linkNotesAction(_selectedNoteIds.length);

    if (useMacOSNativeUI) {
      return ChronicleMacosFixedDialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                l10n.linkNoteDialogTitle,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              content,
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  PushButton(
                    controlSize: ControlSize.large,
                    secondary: true,
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.cancelAction),
                  ),
                  const SizedBox(width: 12),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: hasSelection ? onCreateLink : null,
                    child: Text(actionButtonLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.linkNoteDialogTitle),
      content: content,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancelAction),
        ),
        FilledButton(
          onPressed: hasSelection ? onCreateLink : null,
          child: Text(actionButtonLabel),
        ),
      ],
    );
  }

  Widget _buildResultsGrid(bool useMacOSNativeUI, AppLocalizations l10n) {
    if (_isSearching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_searchController.text.trim().length < _minSearchLength) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.linkNoteSearchHint,
            style: TextStyle(
              color: useMacOSNativeUI
                  ? MacosColors.systemGrayColor
                  : Colors.grey,
            ),
          ),
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.linkNoteNoResultsMessage),
        ),
      );
    }

    // 3-column grid layout with shorter cards
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 2.4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final hit = _searchResults[index];
        final note = hit.note;
        final isSelected = _selectedNoteIds.contains(note.id);

        if (useMacOSNativeUI) {
          return _MacosSearchResultCard(
            note: note,
            snippet: _formatSnippet(hit.snippet, _searchController.text),
            searchQuery: _searchController.text,
            isSelected: isSelected,
            onToggle: () => _toggleSelection(note.id),
            getLocation: _getNoteLocation,
            buildHighlightedText: _buildHighlightedText,
          );
        }

        return _MaterialSearchResultCard(
          note: note,
          snippet: _formatSnippet(hit.snippet, _searchController.text),
          searchQuery: _searchController.text,
          isSelected: isSelected,
          onToggle: () => _toggleSelection(note.id),
          getLocation: _getNoteLocation,
          buildHighlightedText: _buildHighlightedText,
        );
      },
    );
  }

  Widget _buildSelectionSummary(bool useMacOSNativeUI, AppLocalizations l10n) {
    final count = _selectedNoteIds.length;
    final label = l10n.linkNoteSelectedCountLabel(count);

    if (useMacOSNativeUI) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: MacosTheme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: MacosTheme.of(context).primaryColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            MacosIcon(
              CupertinoIcons.checkmark_circle_fill,
              size: 18,
              color: MacosTheme.of(context).primaryColor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: MacosTheme.of(context).typography.body,
              ),
            ),
            MacosIconButton(
              icon: const MacosIcon(CupertinoIcons.xmark_circle, size: 18),
              onPressed: _clearSelection,
              semanticLabel: l10n.clearSelectionAction,
            ),
          ],
        ),
      );
    }

    return Chip(
      avatar: const Icon(Icons.check_circle, size: 18),
      label: Text(label),
      deleteIcon: const Icon(Icons.close, size: 18),
      onDeleted: _clearSelection,
    );
  }
}

class _MacosSearchResultCard extends StatefulWidget {
  const _MacosSearchResultCard({
    required this.note,
    required this.snippet,
    required this.searchQuery,
    required this.isSelected,
    required this.onToggle,
    required this.getLocation,
    required this.buildHighlightedText,
  });

  final Note note;
  final String snippet;
  final String searchQuery;
  final bool isSelected;
  final VoidCallback onToggle;
  final Future<String> Function(Note note) getLocation;
  final Widget Function(String text, String searchQuery, TextStyle? style) buildHighlightedText;

  @override
  State<_MacosSearchResultCard> createState() => _MacosSearchResultCardState();
}

class _MacosSearchResultCardState extends State<_MacosSearchResultCard> {
  String? _location;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final location = await widget.getLocation(widget.note);
    if (mounted) {
      setState(() {
        _location = location;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = MacosTheme.of(context);
    final l10n = context.l10n;
    final title = widget.note.title.trim().isEmpty
        ? l10n.untitledLabel
        : widget.note.title.trim();

    return Material(
      color: widget.isSelected
          ? theme.primaryColor.withValues(alpha: 0.1)
          : theme.canvasColor,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.isSelected
                  ? theme.primaryColor
                  : theme.dividerColor,
              width: widget.isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Custom checkbox indicator
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: widget.isSelected
                            ? theme.primaryColor
                            : theme.dividerColor,
                        width: 2,
                      ),
                      color: widget.isSelected
                          ? theme.primaryColor
                          : Colors.transparent,
                    ),
                    child: widget.isSelected
                        ? const Icon(
                            CupertinoIcons.checkmark,
                            size: 14,
                            color: Colors.white,
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (_location != null) ...[
                const SizedBox(height: 4),
                Text(
                  _location!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.caption1.copyWith(
                    color: MacosColors.systemGrayColor,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Expanded(
                child: widget.buildHighlightedText(
                  widget.snippet,
                  widget.searchQuery,
                  theme.typography.caption1.copyWith(
                    color: theme.typography.caption1.color?.withValues(
                      alpha: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MaterialSearchResultCard extends StatefulWidget {
  const _MaterialSearchResultCard({
    required this.note,
    required this.snippet,
    required this.searchQuery,
    required this.isSelected,
    required this.onToggle,
    required this.getLocation,
    required this.buildHighlightedText,
  });

  final Note note;
  final String snippet;
  final String searchQuery;
  final bool isSelected;
  final VoidCallback onToggle;
  final Future<String> Function(Note note) getLocation;
  final Widget Function(String text, String searchQuery, TextStyle? style) buildHighlightedText;

  @override
  State<_MaterialSearchResultCard> createState() =>
      _MaterialSearchResultCardState();
}

class _MaterialSearchResultCardState extends State<_MaterialSearchResultCard> {
  String? _location;

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final location = await widget.getLocation(widget.note);
    if (mounted) {
      setState(() {
        _location = location;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.note.title.trim().isEmpty
        ? l10n.untitledLabel
        : widget.note.title.trim();

    return Card(
      elevation: widget.isSelected ? 2 : 0,
      color: widget.isSelected
          ? Theme.of(context).colorScheme.primaryContainer
          : Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: widget.isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: widget.isSelected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onToggle,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                    value: widget.isSelected,
                    onChanged: (_) => widget.onToggle(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
              if (_location != null) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    _location!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: widget.buildHighlightedText(
                    widget.snippet,
                    widget.searchQuery,
                    Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
