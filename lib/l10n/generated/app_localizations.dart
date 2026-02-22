import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Chronicle'**
  String get appTitle;

  /// No description provided for @languageSelfName.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageSelfName;

  /// No description provided for @fallbackProbeMessage.
  ///
  /// In en, this message translates to:
  /// **'English fallback probe'**
  String get fallbackProbeMessage;

  /// No description provided for @searchNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes...'**
  String get searchNotesHint;

  /// No description provided for @toggleSidebarTooltip.
  ///
  /// In en, this message translates to:
  /// **'Toggle sidebar'**
  String get toggleSidebarTooltip;

  /// No description provided for @conflictsLabel.
  ///
  /// In en, this message translates to:
  /// **'Conflicts'**
  String get conflictsLabel;

  /// No description provided for @syncNowAction.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNowAction;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @storageSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up Chronicle storage'**
  String get storageSetupTitle;

  /// No description provided for @storageSetupDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose where Chronicle stores markdown/json files. Default is ~/Chronicle.'**
  String get storageSetupDescription;

  /// No description provided for @storageRootPathLabel.
  ///
  /// In en, this message translates to:
  /// **'Storage root path'**
  String get storageRootPathLabel;

  /// No description provided for @pickFolderAction.
  ///
  /// In en, this message translates to:
  /// **'Pick Folder'**
  String get pickFolderAction;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @chronicleSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Chronicle Setup'**
  String get chronicleSetupTitle;

  /// No description provided for @failedToLoadSettings.
  ///
  /// In en, this message translates to:
  /// **'Failed to load settings: {error}'**
  String failedToLoadSettings(Object error);

  /// No description provided for @syncWorkingStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync: working...'**
  String get syncWorkingStatus;

  /// No description provided for @syncErrorStatus.
  ///
  /// In en, this message translates to:
  /// **'Sync error: {error}'**
  String syncErrorStatus(Object error);

  /// No description provided for @syncSummaryStatus.
  ///
  /// In en, this message translates to:
  /// **'Status: {lastMessage} | Last sync: {lastSync}'**
  String syncSummaryStatus(Object lastMessage, Object lastSync);

  /// No description provided for @neverLabel.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get neverLabel;

  /// No description provided for @newMatterAction.
  ///
  /// In en, this message translates to:
  /// **'New Matter'**
  String get newMatterAction;

  /// No description provided for @pinnedLabel.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get pinnedLabel;

  /// No description provided for @activeSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Active ({count})'**
  String activeSectionLabel(int count);

  /// No description provided for @pausedSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Paused ({count})'**
  String pausedSectionLabel(int count);

  /// No description provided for @completedSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Completed ({count})'**
  String completedSectionLabel(int count);

  /// No description provided for @archivedSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Archived ({count})'**
  String archivedSectionLabel(int count);

  /// No description provided for @orphansLabel.
  ///
  /// In en, this message translates to:
  /// **'Orphans'**
  String get orphansLabel;

  /// No description provided for @untitledMatterLabel.
  ///
  /// In en, this message translates to:
  /// **'(untitled matter)'**
  String get untitledMatterLabel;

  /// No description provided for @viewsSectionLabel.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get viewsSectionLabel;

  /// No description provided for @matterActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Matter Actions'**
  String get matterActionsTitle;

  /// No description provided for @editAction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editAction;

  /// No description provided for @unpinAction.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get unpinAction;

  /// No description provided for @pinAction.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get pinAction;

  /// No description provided for @setActiveAction.
  ///
  /// In en, this message translates to:
  /// **'Set Active'**
  String get setActiveAction;

  /// No description provided for @setPausedAction.
  ///
  /// In en, this message translates to:
  /// **'Set Paused'**
  String get setPausedAction;

  /// No description provided for @setCompletedAction.
  ///
  /// In en, this message translates to:
  /// **'Set Completed'**
  String get setCompletedAction;

  /// No description provided for @setArchivedAction.
  ///
  /// In en, this message translates to:
  /// **'Set Archived'**
  String get setArchivedAction;

  /// No description provided for @deleteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAction;

  /// No description provided for @closeAction.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeAction;

  /// No description provided for @cancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelAction;

  /// No description provided for @deleteMatterTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Matter'**
  String get deleteMatterTitle;

  /// No description provided for @deleteMatterConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" and all notes in this matter?'**
  String deleteMatterConfirmation(Object title);

  /// No description provided for @matterStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get matterStatusActive;

  /// No description provided for @matterStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get matterStatusPaused;

  /// No description provided for @matterStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get matterStatusCompleted;

  /// No description provided for @matterStatusArchived.
  ///
  /// In en, this message translates to:
  /// **'Archived'**
  String get matterStatusArchived;

  /// No description provided for @matterStatusBadgeActive.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get matterStatusBadgeActive;

  /// No description provided for @matterStatusBadgePaused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get matterStatusBadgePaused;

  /// No description provided for @matterStatusBadgeCompleted.
  ///
  /// In en, this message translates to:
  /// **'DONE'**
  String get matterStatusBadgeCompleted;

  /// No description provided for @matterStatusBadgeArchived.
  ///
  /// In en, this message translates to:
  /// **'ARCHIVED'**
  String get matterStatusBadgeArchived;

  /// No description provided for @matterStatusBadgeLetterActive.
  ///
  /// In en, this message translates to:
  /// **'A'**
  String get matterStatusBadgeLetterActive;

  /// No description provided for @matterStatusBadgeLetterPaused.
  ///
  /// In en, this message translates to:
  /// **'P'**
  String get matterStatusBadgeLetterPaused;

  /// No description provided for @matterStatusBadgeLetterCompleted.
  ///
  /// In en, this message translates to:
  /// **'D'**
  String get matterStatusBadgeLetterCompleted;

  /// No description provided for @matterStatusBadgeLetterArchived.
  ///
  /// In en, this message translates to:
  /// **'R'**
  String get matterStatusBadgeLetterArchived;

  /// No description provided for @selectMatterOrphansOrConflictsPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a Matter, Orphans, or Conflicts to begin.'**
  String get selectMatterOrphansOrConflictsPrompt;

  /// No description provided for @matterNoLongerExistsMessage.
  ///
  /// In en, this message translates to:
  /// **'Matter no longer exists.'**
  String get matterNoLongerExistsMessage;

  /// No description provided for @conflictLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Conflict load failed: {error}'**
  String conflictLoadFailed(Object error);

  /// No description provided for @conflictsCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Conflicts ({count})'**
  String conflictsCountTitle(int count);

  /// No description provided for @refreshAction.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshAction;

  /// No description provided for @noConflictsDetectedMessage.
  ///
  /// In en, this message translates to:
  /// **'No conflicts detected.'**
  String get noConflictsDetectedMessage;

  /// No description provided for @selectConflictToReviewPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a conflict to review.'**
  String get selectConflictToReviewPrompt;

  /// No description provided for @conflictTypeRow.
  ///
  /// In en, this message translates to:
  /// **'Type: {type}'**
  String conflictTypeRow(Object type);

  /// No description provided for @conflictFileRow.
  ///
  /// In en, this message translates to:
  /// **'Conflict file: {path}'**
  String conflictFileRow(Object path);

  /// No description provided for @conflictOriginalRow.
  ///
  /// In en, this message translates to:
  /// **'Original: {path}'**
  String conflictOriginalRow(Object path);

  /// No description provided for @conflictLocalRow.
  ///
  /// In en, this message translates to:
  /// **'Local: {device}'**
  String conflictLocalRow(Object device);

  /// No description provided for @conflictRemoteRow.
  ///
  /// In en, this message translates to:
  /// **'Remote: {device}'**
  String conflictRemoteRow(Object device);

  /// No description provided for @openMainNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Open Main Note'**
  String get openMainNoteAction;

  /// No description provided for @markResolvedAction.
  ///
  /// In en, this message translates to:
  /// **'Mark Resolved'**
  String get markResolvedAction;

  /// No description provided for @failedToLoadConflict.
  ///
  /// In en, this message translates to:
  /// **'Failed to load conflict: {error}'**
  String failedToLoadConflict(Object error);

  /// No description provided for @binaryConflictNotPreviewable.
  ///
  /// In en, this message translates to:
  /// **'Binary conflict content is not previewable.'**
  String get binaryConflictNotPreviewable;

  /// No description provided for @conflictContentEmpty.
  ///
  /// In en, this message translates to:
  /// **'Conflict content is empty.'**
  String get conflictContentEmpty;

  /// No description provided for @viewModePhase.
  ///
  /// In en, this message translates to:
  /// **'Phase'**
  String get viewModePhase;

  /// No description provided for @viewModeTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get viewModeTimeline;

  /// No description provided for @viewModeList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get viewModeList;

  /// No description provided for @viewModeGraph.
  ///
  /// In en, this message translates to:
  /// **'Graph'**
  String get viewModeGraph;

  /// No description provided for @newNoteAction.
  ///
  /// In en, this message translates to:
  /// **'New Note'**
  String get newNoteAction;

  /// No description provided for @deleteNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete note'**
  String get deleteNoteTitle;

  /// No description provided for @deleteNoteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\"?'**
  String deleteNoteConfirmation(Object title);

  /// No description provided for @graphLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Graph load failed: {error}'**
  String graphLoadFailed(Object error);

  /// No description provided for @noLinkedNotesInMatterMessage.
  ///
  /// In en, this message translates to:
  /// **'No linked notes yet in this matter.\nCreate links from note actions to populate the graph.'**
  String get noLinkedNotesInMatterMessage;

  /// No description provided for @graphLimitedNotice.
  ///
  /// In en, this message translates to:
  /// **'Graph limited to {limit} nodes ({hiddenCount} hidden).'**
  String graphLimitedNotice(int limit, int hiddenCount);

  /// No description provided for @untitledLabel.
  ///
  /// In en, this message translates to:
  /// **'(untitled)'**
  String get untitledLabel;

  /// No description provided for @orphanNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'Orphan Notes'**
  String get orphanNotesTitle;

  /// No description provided for @newOrphanNoteAction.
  ///
  /// In en, this message translates to:
  /// **'New Orphan Note'**
  String get newOrphanNoteAction;

  /// No description provided for @noNotesYetMessage.
  ///
  /// In en, this message translates to:
  /// **'No notes yet.'**
  String get noNotesYetMessage;

  /// No description provided for @linkNoteActionEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Link Note...'**
  String get linkNoteActionEllipsis;

  /// No description provided for @editorError.
  ///
  /// In en, this message translates to:
  /// **'Editor error: {error}'**
  String editorError(Object error);

  /// No description provided for @selectNoteToEditPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a note to edit.'**
  String get selectNoteToEditPrompt;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @linkNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Link Note'**
  String get linkNoteAction;

  /// No description provided for @togglePreviewAction.
  ///
  /// In en, this message translates to:
  /// **'Toggle Preview'**
  String get togglePreviewAction;

  /// No description provided for @deleteNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Delete Note'**
  String get deleteNoteAction;

  /// No description provided for @tagsCommaSeparatedLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma separated)'**
  String get tagsCommaSeparatedLabel;

  /// No description provided for @moveToOrphansAction.
  ///
  /// In en, this message translates to:
  /// **'Move to Orphans'**
  String get moveToOrphansAction;

  /// No description provided for @moveNoteToMatterAction.
  ///
  /// In en, this message translates to:
  /// **'Move to Matter...'**
  String get moveNoteToMatterAction;

  /// No description provided for @moveNoteToPhaseAction.
  ///
  /// In en, this message translates to:
  /// **'Move to Phase...'**
  String get moveNoteToPhaseAction;

  /// No description provided for @moveNoteToMatterDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Move Note to Matter'**
  String get moveNoteToMatterDialogTitle;

  /// No description provided for @moveNoteToPhaseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Move Note to Phase'**
  String get moveNoteToPhaseDialogTitle;

  /// No description provided for @moveNoteCurrentMatterLabel.
  ///
  /// In en, this message translates to:
  /// **'Current matter'**
  String get moveNoteCurrentMatterLabel;

  /// No description provided for @moveSourceMatterMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'Cannot move note because its source matter is unavailable.'**
  String get moveSourceMatterMissingMessage;

  /// No description provided for @movePhaseRequiresSameMatterMessage.
  ///
  /// In en, this message translates to:
  /// **'You can only move to another phase in the same matter.'**
  String get movePhaseRequiresSameMatterMessage;

  /// No description provided for @moveTargetMatterHasNoPhases.
  ///
  /// In en, this message translates to:
  /// **'Cannot move note. \"{matter}\" has no phases.'**
  String moveTargetMatterHasNoPhases(Object matter);

  /// No description provided for @moveNoteFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to move note: {error}'**
  String moveNoteFailed(Object error);

  /// No description provided for @assignToSelectedMatterAction.
  ///
  /// In en, this message translates to:
  /// **'Assign to Selected Matter'**
  String get assignToSelectedMatterAction;

  /// No description provided for @writeMarkdownHereHint.
  ///
  /// In en, this message translates to:
  /// **'Write markdown here...'**
  String get writeMarkdownHereHint;

  /// No description provided for @saveAction.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveAction;

  /// No description provided for @editModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editModeLabel;

  /// No description provided for @readModeLabel.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get readModeLabel;

  /// No description provided for @noteMoreActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'More note actions'**
  String get noteMoreActionsTooltip;

  /// No description provided for @noteTagsUtilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get noteTagsUtilityTitle;

  /// No description provided for @noteAttachmentsUtilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get noteAttachmentsUtilityTitle;

  /// No description provided for @noteLinkedNotesUtilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Linked Notes'**
  String get noteLinkedNotesUtilityTitle;

  /// No description provided for @updatedAtRow.
  ///
  /// In en, this message translates to:
  /// **'Updated: {updatedAt}'**
  String updatedAtRow(Object updatedAt);

  /// No description provided for @failedToAttachFiles.
  ///
  /// In en, this message translates to:
  /// **'Failed to attach files: {error}'**
  String failedToAttachFiles(Object error);

  /// No description provided for @failedToRemoveAttachment.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove attachment: {error}'**
  String failedToRemoveAttachment(Object error);

  /// No description provided for @attachmentFileNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'Attachment file not found'**
  String get attachmentFileNotFoundMessage;

  /// No description provided for @unableToOpenAttachmentMessage.
  ///
  /// In en, this message translates to:
  /// **'Unable to open attachment'**
  String get unableToOpenAttachmentMessage;

  /// No description provided for @unableToOpenAttachmentWithReason.
  ///
  /// In en, this message translates to:
  /// **'Unable to open attachment: {reason}'**
  String unableToOpenAttachmentWithReason(Object reason);

  /// No description provided for @attachmentsCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachments ({count})'**
  String attachmentsCountTitle(int count);

  /// No description provided for @attachFilesActionEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Attach files...'**
  String get attachFilesActionEllipsis;

  /// No description provided for @noAttachmentsYetMessage.
  ///
  /// In en, this message translates to:
  /// **'No attachments yet.'**
  String get noAttachmentsYetMessage;

  /// No description provided for @storageRootUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Storage root unavailable. Configure settings first.'**
  String get storageRootUnavailableMessage;

  /// No description provided for @linkedNotesCountTitle.
  ///
  /// In en, this message translates to:
  /// **'Linked Notes ({count})'**
  String linkedNotesCountTitle(int count);

  /// No description provided for @failedToLoadLinks.
  ///
  /// In en, this message translates to:
  /// **'Failed to load links: {error}'**
  String failedToLoadLinks(Object error);

  /// No description provided for @noLinksYetMessage.
  ///
  /// In en, this message translates to:
  /// **'No links yet.'**
  String get noLinksYetMessage;

  /// No description provided for @openLinkedNoteAction.
  ///
  /// In en, this message translates to:
  /// **'Open linked note'**
  String get openLinkedNoteAction;

  /// No description provided for @removeLinkAction.
  ///
  /// In en, this message translates to:
  /// **'Remove link'**
  String get removeLinkAction;

  /// No description provided for @unableToLoadNotes.
  ///
  /// In en, this message translates to:
  /// **'Unable to load notes: {error}'**
  String unableToLoadNotes(Object error);

  /// No description provided for @noNotesAvailableToLink.
  ///
  /// In en, this message translates to:
  /// **'No notes available to link.'**
  String get noNotesAvailableToLink;

  /// No description provided for @linkCreatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Link created'**
  String get linkCreatedMessage;

  /// No description provided for @unableToCreateLink.
  ///
  /// In en, this message translates to:
  /// **'Unable to create link: {error}'**
  String unableToCreateLink(Object error);

  /// No description provided for @linkSourceRow.
  ///
  /// In en, this message translates to:
  /// **'Source: {source}'**
  String linkSourceRow(Object source);

  /// No description provided for @targetNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Target note'**
  String get targetNoteLabel;

  /// No description provided for @contextOptionalLabel.
  ///
  /// In en, this message translates to:
  /// **'Context (optional)'**
  String get contextOptionalLabel;

  /// No description provided for @linkContextHint.
  ///
  /// In en, this message translates to:
  /// **'Why are these notes related?'**
  String get linkContextHint;

  /// No description provided for @linkNoteDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Link Note'**
  String get linkNoteDialogTitle;

  /// No description provided for @createLinkAction.
  ///
  /// In en, this message translates to:
  /// **'Create Link'**
  String get createLinkAction;

  /// No description provided for @orphanLabel.
  ///
  /// In en, this message translates to:
  /// **'Orphan'**
  String get orphanLabel;

  /// No description provided for @conflictTypeNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get conflictTypeNote;

  /// No description provided for @conflictTypeLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get conflictTypeLink;

  /// No description provided for @conflictTypeUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get conflictTypeUnknown;

  /// No description provided for @noSearchResultsMessage.
  ///
  /// In en, this message translates to:
  /// **'No search results.'**
  String get noSearchResultsMessage;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @settingsSectionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get settingsSectionStorage;

  /// No description provided for @settingsSectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// No description provided for @settingsSectionSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get settingsSectionSync;

  /// No description provided for @syncTargetTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Sync target type'**
  String get syncTargetTypeLabel;

  /// No description provided for @syncTargetTypeNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get syncTargetTypeNone;

  /// No description provided for @syncTargetTypeFilesystem.
  ///
  /// In en, this message translates to:
  /// **'File system'**
  String get syncTargetTypeFilesystem;

  /// No description provided for @syncTargetTypeWebdav.
  ///
  /// In en, this message translates to:
  /// **'WebDAV'**
  String get syncTargetTypeWebdav;

  /// No description provided for @webDavUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'WebDAV URL'**
  String get webDavUrlLabel;

  /// No description provided for @webDavUsernameLabel.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Username'**
  String get webDavUsernameLabel;

  /// No description provided for @webDavPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'WebDAV Password'**
  String get webDavPasswordLabel;

  /// No description provided for @autoSyncIntervalMinutesLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-sync interval (minutes)'**
  String get autoSyncIntervalMinutesLabel;

  /// No description provided for @deletionFailSafeLabel.
  ///
  /// In en, this message translates to:
  /// **'Deletion fail-safe'**
  String get deletionFailSafeLabel;

  /// No description provided for @syncAdvancedActionsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Advanced sync actions'**
  String get syncAdvancedActionsTooltip;

  /// No description provided for @syncRecoverLocalWinsAction.
  ///
  /// In en, this message translates to:
  /// **'Re-upload local to remote'**
  String get syncRecoverLocalWinsAction;

  /// No description provided for @syncRecoverRemoteWinsAction.
  ///
  /// In en, this message translates to:
  /// **'Re-download remote to local'**
  String get syncRecoverRemoteWinsAction;

  /// No description provided for @syncForceDeletionNextRunAction.
  ///
  /// In en, this message translates to:
  /// **'Force apply deletions (next run)'**
  String get syncForceDeletionNextRunAction;

  /// No description provided for @syncRecoverLocalWinsTitle.
  ///
  /// In en, this message translates to:
  /// **'Local Wins Recovery'**
  String get syncRecoverLocalWinsTitle;

  /// No description provided for @syncRecoverLocalWinsWarning.
  ///
  /// In en, this message translates to:
  /// **'This will overwrite remote data with local data and may delete remote files that do not exist locally. Back up first if needed.'**
  String get syncRecoverLocalWinsWarning;

  /// No description provided for @syncRecoverRemoteWinsTitle.
  ///
  /// In en, this message translates to:
  /// **'Remote Wins Recovery'**
  String get syncRecoverRemoteWinsTitle;

  /// No description provided for @syncRecoverRemoteWinsWarning.
  ///
  /// In en, this message translates to:
  /// **'This will overwrite local data with remote data and may delete local files that do not exist remotely. Back up first if needed.'**
  String get syncRecoverRemoteWinsWarning;

  /// No description provided for @syncForceDeletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Force Apply Deletions'**
  String get syncForceDeletionTitle;

  /// No description provided for @syncForceDeletionWarning.
  ///
  /// In en, this message translates to:
  /// **'This arms a one-time override for deletion fail-safe on the next sync run. {summary}\nProceed only if you have a backup.'**
  String syncForceDeletionWarning(Object summary);

  /// No description provided for @syncForceDeletionSummary.
  ///
  /// In en, this message translates to:
  /// **'Current blocked plan: {candidate} deletions over {tracked} tracked files.'**
  String syncForceDeletionSummary(int candidate, int tracked);

  /// No description provided for @syncForceDeletionSummaryUnknown.
  ///
  /// In en, this message translates to:
  /// **'No current deletion-count estimate is available.'**
  String get syncForceDeletionSummaryUnknown;

  /// No description provided for @syncForceDeletionArmedStatus.
  ///
  /// In en, this message translates to:
  /// **'Force deletion override armed'**
  String get syncForceDeletionArmedStatus;

  /// No description provided for @createMatterTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Matter'**
  String get createMatterTitle;

  /// No description provided for @editMatterTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Matter'**
  String get editMatterTitle;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @matterPresetColorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Preset colors'**
  String get matterPresetColorsLabel;

  /// No description provided for @matterCustomColorAction.
  ///
  /// In en, this message translates to:
  /// **'Custom color'**
  String get matterCustomColorAction;

  /// No description provided for @matterUseColorAction.
  ///
  /// In en, this message translates to:
  /// **'Use color'**
  String get matterUseColorAction;

  /// No description provided for @matterIconPickerLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon'**
  String get matterIconPickerLabel;

  /// No description provided for @matterIconDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get matterIconDescriptionLabel;

  /// No description provided for @matterIconFolderLabel.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get matterIconFolderLabel;

  /// No description provided for @matterIconWorkLabel.
  ///
  /// In en, this message translates to:
  /// **'Work'**
  String get matterIconWorkLabel;

  /// No description provided for @matterIconGavelLabel.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get matterIconGavelLabel;

  /// No description provided for @matterIconSchoolLabel.
  ///
  /// In en, this message translates to:
  /// **'School'**
  String get matterIconSchoolLabel;

  /// No description provided for @matterIconAccountBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get matterIconAccountBalanceLabel;

  /// No description provided for @matterIconHomeLabel.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get matterIconHomeLabel;

  /// No description provided for @matterIconBuildLabel.
  ///
  /// In en, this message translates to:
  /// **'Build'**
  String get matterIconBuildLabel;

  /// No description provided for @matterIconBoltLabel.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get matterIconBoltLabel;

  /// No description provided for @matterIconAssignmentLabel.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get matterIconAssignmentLabel;

  /// No description provided for @matterIconEventLabel.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get matterIconEventLabel;

  /// No description provided for @matterIconCampaignLabel.
  ///
  /// In en, this message translates to:
  /// **'Campaign'**
  String get matterIconCampaignLabel;

  /// No description provided for @matterIconLocalHospitalLabel.
  ///
  /// In en, this message translates to:
  /// **'Health'**
  String get matterIconLocalHospitalLabel;

  /// No description provided for @matterIconScienceLabel.
  ///
  /// In en, this message translates to:
  /// **'Science'**
  String get matterIconScienceLabel;

  /// No description provided for @matterIconTerminalLabel.
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get matterIconTerminalLabel;

  /// No description provided for @colorHexLabel.
  ///
  /// In en, this message translates to:
  /// **'Color (hex)'**
  String get colorHexLabel;

  /// No description provided for @colorHexHint.
  ///
  /// In en, this message translates to:
  /// **'#4C956C'**
  String get colorHexHint;

  /// No description provided for @iconNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Icon name'**
  String get iconNameLabel;

  /// No description provided for @iconNameHint.
  ///
  /// In en, this message translates to:
  /// **'description'**
  String get iconNameHint;

  /// No description provided for @createAction.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get createAction;

  /// No description provided for @defaultUntitledNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Untitled Note'**
  String get defaultUntitledNoteTitle;

  /// No description provided for @createNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Note'**
  String get createNoteTitle;

  /// No description provided for @editNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Note'**
  String get editNoteTitle;

  /// No description provided for @markdownContentLabel.
  ///
  /// In en, this message translates to:
  /// **'Markdown content'**
  String get markdownContentLabel;

  /// No description provided for @defaultQuickCaptureTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Capture'**
  String get defaultQuickCaptureTitle;

  /// No description provided for @openAttachmentAction.
  ///
  /// In en, this message translates to:
  /// **'Open attachment'**
  String get openAttachmentAction;

  /// No description provided for @removeAttachmentAction.
  ///
  /// In en, this message translates to:
  /// **'Remove attachment'**
  String get removeAttachmentAction;

  /// No description provided for @loadingEllipsis.
  ///
  /// In en, this message translates to:
  /// **'...'**
  String get loadingEllipsis;

  /// No description provided for @fileMissingLabel.
  ///
  /// In en, this message translates to:
  /// **'Missing'**
  String get fileMissingLabel;

  /// No description provided for @imagePreviewUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'Image preview unavailable'**
  String get imagePreviewUnavailableMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
