// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Chronicle';

  @override
  String get languageSelfName => 'English';

  @override
  String get fallbackProbeMessage => 'English fallback probe';

  @override
  String get searchNotesHint => 'Search notes...';

  @override
  String get toggleSidebarTooltip => 'Toggle sidebar';

  @override
  String get conflictsLabel => 'Conflicts';

  @override
  String get syncNowAction => 'Sync now';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get storageSetupTitle => 'Set up Chronicle storage';

  @override
  String get storageSetupDescription =>
      'Choose where Chronicle stores markdown/json files. Default is ~/Chronicle.';

  @override
  String get storageRootPathLabel => 'Storage root path';

  @override
  String get pickFolderAction => 'Pick Folder';

  @override
  String get continueAction => 'Continue';

  @override
  String get chronicleSetupTitle => 'Chronicle Setup';

  @override
  String failedToLoadSettings(Object error) {
    return 'Failed to load settings: $error';
  }

  @override
  String get syncWorkingStatus => 'Sync: working...';

  @override
  String syncErrorStatus(Object error) {
    return 'Sync error: $error';
  }

  @override
  String syncSummaryStatus(Object lastMessage, Object lastSync) {
    return 'Status: $lastMessage | Last sync: $lastSync';
  }

  @override
  String get neverLabel => 'never';

  @override
  String get newMatterAction => 'New Matter';

  @override
  String get pinnedLabel => 'Pinned';

  @override
  String activeSectionLabel(int count) {
    return 'Active ($count)';
  }

  @override
  String pausedSectionLabel(int count) {
    return 'Paused ($count)';
  }

  @override
  String completedSectionLabel(int count) {
    return 'Completed ($count)';
  }

  @override
  String archivedSectionLabel(int count) {
    return 'Archived ($count)';
  }

  @override
  String get orphansLabel => 'Orphans';

  @override
  String get untitledMatterLabel => '(untitled matter)';

  @override
  String get viewsSectionLabel => 'Views';

  @override
  String get matterActionsTitle => 'Matter Actions';

  @override
  String get editAction => 'Edit';

  @override
  String get unpinAction => 'Unpin';

  @override
  String get pinAction => 'Pin';

  @override
  String get setActiveAction => 'Set Active';

  @override
  String get setPausedAction => 'Set Paused';

  @override
  String get setCompletedAction => 'Set Completed';

  @override
  String get setArchivedAction => 'Set Archived';

  @override
  String get deleteAction => 'Delete';

  @override
  String get closeAction => 'Close';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get deleteMatterTitle => 'Delete Matter';

  @override
  String deleteMatterConfirmation(Object title) {
    return 'Delete \"$title\" and all notes in this matter?';
  }

  @override
  String get matterStatusActive => 'Active';

  @override
  String get matterStatusPaused => 'Paused';

  @override
  String get matterStatusCompleted => 'Completed';

  @override
  String get matterStatusArchived => 'Archived';

  @override
  String get matterStatusBadgeActive => 'ACTIVE';

  @override
  String get matterStatusBadgePaused => 'PAUSED';

  @override
  String get matterStatusBadgeCompleted => 'DONE';

  @override
  String get matterStatusBadgeArchived => 'ARCHIVED';

  @override
  String get matterStatusBadgeLetterActive => 'A';

  @override
  String get matterStatusBadgeLetterPaused => 'P';

  @override
  String get matterStatusBadgeLetterCompleted => 'D';

  @override
  String get matterStatusBadgeLetterArchived => 'R';

  @override
  String get selectMatterOrphansOrConflictsPrompt =>
      'Select a Matter, Orphans, or Conflicts to begin.';

  @override
  String get matterNoLongerExistsMessage => 'Matter no longer exists.';

  @override
  String conflictLoadFailed(Object error) {
    return 'Conflict load failed: $error';
  }

  @override
  String conflictsCountTitle(int count) {
    return 'Conflicts ($count)';
  }

  @override
  String get refreshAction => 'Refresh';

  @override
  String get noConflictsDetectedMessage => 'No conflicts detected.';

  @override
  String get selectConflictToReviewPrompt => 'Select a conflict to review.';

  @override
  String conflictTypeRow(Object type) {
    return 'Type: $type';
  }

  @override
  String conflictFileRow(Object path) {
    return 'Conflict file: $path';
  }

  @override
  String conflictOriginalRow(Object path) {
    return 'Original: $path';
  }

  @override
  String conflictLocalRow(Object device) {
    return 'Local: $device';
  }

  @override
  String conflictRemoteRow(Object device) {
    return 'Remote: $device';
  }

  @override
  String get openMainNoteAction => 'Open Main Note';

  @override
  String get markResolvedAction => 'Mark Resolved';

  @override
  String failedToLoadConflict(Object error) {
    return 'Failed to load conflict: $error';
  }

  @override
  String get binaryConflictNotPreviewable =>
      'Binary conflict content is not previewable.';

  @override
  String get conflictContentEmpty => 'Conflict content is empty.';

  @override
  String get viewModePhase => 'Phase';

  @override
  String get viewModeTimeline => 'Timeline';

  @override
  String get viewModeList => 'List';

  @override
  String get viewModeGraph => 'Graph';

  @override
  String get newNoteAction => 'New Note';

  @override
  String get deleteNoteTitle => 'Delete note';

  @override
  String deleteNoteConfirmation(Object title) {
    return 'Delete \"$title\"?';
  }

  @override
  String graphLoadFailed(Object error) {
    return 'Graph load failed: $error';
  }

  @override
  String get noLinkedNotesInMatterMessage =>
      'No linked notes yet in this matter.\nCreate links from note actions to populate the graph.';

  @override
  String graphLimitedNotice(int limit, int hiddenCount) {
    return 'Graph limited to $limit nodes ($hiddenCount hidden).';
  }

  @override
  String get untitledLabel => '(untitled)';

  @override
  String get orphanNotesTitle => 'Orphan Notes';

  @override
  String get newOrphanNoteAction => 'New Orphan Note';

  @override
  String get noNotesYetMessage => 'No notes yet.';

  @override
  String get linkNoteActionEllipsis => 'Link Note...';

  @override
  String editorError(Object error) {
    return 'Editor error: $error';
  }

  @override
  String get selectNoteToEditPrompt => 'Select a note to edit.';

  @override
  String get titleLabel => 'Title';

  @override
  String get linkNoteAction => 'Link Note';

  @override
  String get togglePreviewAction => 'Toggle Preview';

  @override
  String get deleteNoteAction => 'Delete Note';

  @override
  String get tagsCommaSeparatedLabel => 'Tags (comma separated)';

  @override
  String get moveToOrphansAction => 'Move to Orphans';

  @override
  String get assignToSelectedMatterAction => 'Assign to Selected Matter';

  @override
  String get writeMarkdownHereHint => 'Write markdown here...';

  @override
  String get saveAction => 'Save';

  @override
  String get editModeLabel => 'Edit';

  @override
  String get readModeLabel => 'Read';

  @override
  String get noteMoreActionsTooltip => 'More note actions';

  @override
  String get noteTagsUtilityTitle => 'Tags';

  @override
  String get noteAttachmentsUtilityTitle => 'Attachments';

  @override
  String get noteLinkedNotesUtilityTitle => 'Linked Notes';

  @override
  String updatedAtRow(Object updatedAt) {
    return 'Updated: $updatedAt';
  }

  @override
  String failedToAttachFiles(Object error) {
    return 'Failed to attach files: $error';
  }

  @override
  String failedToRemoveAttachment(Object error) {
    return 'Failed to remove attachment: $error';
  }

  @override
  String get attachmentFileNotFoundMessage => 'Attachment file not found';

  @override
  String get unableToOpenAttachmentMessage => 'Unable to open attachment';

  @override
  String unableToOpenAttachmentWithReason(Object reason) {
    return 'Unable to open attachment: $reason';
  }

  @override
  String attachmentsCountTitle(int count) {
    return 'Attachments ($count)';
  }

  @override
  String get attachFilesActionEllipsis => 'Attach files...';

  @override
  String get noAttachmentsYetMessage => 'No attachments yet.';

  @override
  String get storageRootUnavailableMessage =>
      'Storage root unavailable. Configure settings first.';

  @override
  String linkedNotesCountTitle(int count) {
    return 'Linked Notes ($count)';
  }

  @override
  String failedToLoadLinks(Object error) {
    return 'Failed to load links: $error';
  }

  @override
  String get noLinksYetMessage => 'No links yet.';

  @override
  String get openLinkedNoteAction => 'Open linked note';

  @override
  String get removeLinkAction => 'Remove link';

  @override
  String unableToLoadNotes(Object error) {
    return 'Unable to load notes: $error';
  }

  @override
  String get noNotesAvailableToLink => 'No notes available to link.';

  @override
  String get linkCreatedMessage => 'Link created';

  @override
  String unableToCreateLink(Object error) {
    return 'Unable to create link: $error';
  }

  @override
  String linkSourceRow(Object source) {
    return 'Source: $source';
  }

  @override
  String get targetNoteLabel => 'Target note';

  @override
  String get contextOptionalLabel => 'Context (optional)';

  @override
  String get linkContextHint => 'Why are these notes related?';

  @override
  String get linkNoteDialogTitle => 'Link Note';

  @override
  String get createLinkAction => 'Create Link';

  @override
  String get orphanLabel => 'Orphan';

  @override
  String get conflictTypeNote => 'Note';

  @override
  String get conflictTypeLink => 'Link';

  @override
  String get conflictTypeUnknown => 'Unknown';

  @override
  String get noSearchResultsMessage => 'No search results.';

  @override
  String get languageLabel => 'Language';

  @override
  String get settingsSectionStorage => 'Storage';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsSectionSync => 'Sync';

  @override
  String get syncTargetTypeLabel => 'Sync target type';

  @override
  String get syncTargetTypeNone => 'None';

  @override
  String get syncTargetTypeFilesystem => 'File system';

  @override
  String get syncTargetTypeWebdav => 'WebDAV';

  @override
  String get webDavUrlLabel => 'WebDAV URL';

  @override
  String get webDavUsernameLabel => 'WebDAV Username';

  @override
  String get webDavPasswordLabel => 'WebDAV Password';

  @override
  String get autoSyncIntervalMinutesLabel => 'Auto-sync interval (minutes)';

  @override
  String get deletionFailSafeLabel => 'Deletion fail-safe';

  @override
  String get syncAdvancedActionsTooltip => 'Advanced sync actions';

  @override
  String get syncRecoverLocalWinsAction => 'Re-upload local to remote';

  @override
  String get syncRecoverRemoteWinsAction => 'Re-download remote to local';

  @override
  String get syncForceDeletionNextRunAction =>
      'Force apply deletions (next run)';

  @override
  String get syncRecoverLocalWinsTitle => 'Local Wins Recovery';

  @override
  String get syncRecoverLocalWinsWarning =>
      'This will overwrite remote data with local data and may delete remote files that do not exist locally. Back up first if needed.';

  @override
  String get syncRecoverRemoteWinsTitle => 'Remote Wins Recovery';

  @override
  String get syncRecoverRemoteWinsWarning =>
      'This will overwrite local data with remote data and may delete local files that do not exist remotely. Back up first if needed.';

  @override
  String get syncForceDeletionTitle => 'Force Apply Deletions';

  @override
  String syncForceDeletionWarning(Object summary) {
    return 'This arms a one-time override for deletion fail-safe on the next sync run. $summary\nProceed only if you have a backup.';
  }

  @override
  String syncForceDeletionSummary(int candidate, int tracked) {
    return 'Current blocked plan: $candidate deletions over $tracked tracked files.';
  }

  @override
  String get syncForceDeletionSummaryUnknown =>
      'No current deletion-count estimate is available.';

  @override
  String get syncForceDeletionArmedStatus => 'Force deletion override armed';

  @override
  String get createMatterTitle => 'Create Matter';

  @override
  String get editMatterTitle => 'Edit Matter';

  @override
  String get statusLabel => 'Status';

  @override
  String get descriptionLabel => 'Description';

  @override
  String get matterPresetColorsLabel => 'Preset colors';

  @override
  String get matterCustomColorAction => 'Custom color';

  @override
  String get matterUseColorAction => 'Use color';

  @override
  String get matterIconPickerLabel => 'Icon';

  @override
  String get matterIconDescriptionLabel => 'Description';

  @override
  String get matterIconFolderLabel => 'Folder';

  @override
  String get matterIconWorkLabel => 'Work';

  @override
  String get matterIconGavelLabel => 'Legal';

  @override
  String get matterIconSchoolLabel => 'School';

  @override
  String get matterIconAccountBalanceLabel => 'Finance';

  @override
  String get matterIconHomeLabel => 'Home';

  @override
  String get matterIconBuildLabel => 'Build';

  @override
  String get matterIconBoltLabel => 'Fast';

  @override
  String get matterIconAssignmentLabel => 'Task';

  @override
  String get matterIconEventLabel => 'Event';

  @override
  String get matterIconCampaignLabel => 'Campaign';

  @override
  String get matterIconLocalHospitalLabel => 'Health';

  @override
  String get matterIconScienceLabel => 'Science';

  @override
  String get matterIconTerminalLabel => 'Terminal';

  @override
  String get colorHexLabel => 'Color (hex)';

  @override
  String get colorHexHint => '#4C956C';

  @override
  String get iconNameLabel => 'Icon name';

  @override
  String get iconNameHint => 'description';

  @override
  String get createAction => 'Create';

  @override
  String get defaultUntitledNoteTitle => 'Untitled Note';

  @override
  String get createNoteTitle => 'Create Note';

  @override
  String get editNoteTitle => 'Edit Note';

  @override
  String get markdownContentLabel => 'Markdown content';

  @override
  String get defaultQuickCaptureTitle => 'Quick Capture';

  @override
  String get openAttachmentAction => 'Open attachment';

  @override
  String get removeAttachmentAction => 'Remove attachment';

  @override
  String get loadingEllipsis => '...';

  @override
  String get fileMissingLabel => 'Missing';

  @override
  String get imagePreviewUnavailableMessage => 'Image preview unavailable';
}
