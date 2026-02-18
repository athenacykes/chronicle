// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Chronicle';

  @override
  String get languageSelfName => '简体中文';

  @override
  String get fallbackProbeMessage => 'English fallback probe';

  @override
  String get searchNotesHint => '搜索笔记...';

  @override
  String get toggleSidebarTooltip => '切换侧边栏';

  @override
  String get conflictsLabel => '冲突';

  @override
  String get syncNowAction => '立即同步';

  @override
  String get settingsTitle => '设置';

  @override
  String get storageSetupTitle => '设置 Chronicle 存储';

  @override
  String get storageSetupDescription =>
      '选择 Chronicle 存储 markdown/json 文件的位置。默认是 ~/Chronicle。';

  @override
  String get storageRootPathLabel => '存储根路径';

  @override
  String get pickFolderAction => '选择文件夹';

  @override
  String get continueAction => '继续';

  @override
  String get chronicleSetupTitle => 'Chronicle 设置';

  @override
  String failedToLoadSettings(Object error) {
    return '加载设置失败：$error';
  }

  @override
  String get syncWorkingStatus => '同步中...';

  @override
  String syncErrorStatus(Object error) {
    return '同步错误：$error';
  }

  @override
  String syncSummaryStatus(Object lastMessage, Object lastSync) {
    return '状态：$lastMessage | 上次同步：$lastSync';
  }

  @override
  String get neverLabel => '从未';

  @override
  String get newMatterAction => '新建 Matter';

  @override
  String get pinnedLabel => '置顶';

  @override
  String activeSectionLabel(int count) {
    return '进行中（$count）';
  }

  @override
  String pausedSectionLabel(int count) {
    return '已暂停（$count）';
  }

  @override
  String completedSectionLabel(int count) {
    return '已完成（$count）';
  }

  @override
  String archivedSectionLabel(int count) {
    return '已归档（$count）';
  }

  @override
  String get orphansLabel => '孤立笔记';

  @override
  String get untitledMatterLabel => '（未命名 Matter）';

  @override
  String get viewsSectionLabel => '视图';

  @override
  String get matterActionsTitle => 'Matter 操作';

  @override
  String get editAction => '编辑';

  @override
  String get unpinAction => '取消置顶';

  @override
  String get pinAction => '置顶';

  @override
  String get setActiveAction => '设为进行中';

  @override
  String get setPausedAction => '设为已暂停';

  @override
  String get setCompletedAction => '设为已完成';

  @override
  String get setArchivedAction => '设为已归档';

  @override
  String get deleteAction => '删除';

  @override
  String get cancelAction => '取消';

  @override
  String get deleteMatterTitle => '删除 Matter';

  @override
  String deleteMatterConfirmation(Object title) {
    return '删除 \"$title\" 及该 Matter 下所有笔记？';
  }

  @override
  String get matterStatusActive => '进行中';

  @override
  String get matterStatusPaused => '已暂停';

  @override
  String get matterStatusCompleted => '已完成';

  @override
  String get matterStatusArchived => '已归档';

  @override
  String get matterStatusBadgeActive => '进行中';

  @override
  String get matterStatusBadgePaused => '暂停';

  @override
  String get matterStatusBadgeCompleted => '完成';

  @override
  String get matterStatusBadgeArchived => '归档';

  @override
  String get matterStatusBadgeLetterActive => '进';

  @override
  String get matterStatusBadgeLetterPaused => '停';

  @override
  String get matterStatusBadgeLetterCompleted => '完';

  @override
  String get matterStatusBadgeLetterArchived => '档';

  @override
  String get selectMatterOrphansOrConflictsPrompt => '请选择 Matter、孤立笔记或冲突开始使用。';

  @override
  String get matterNoLongerExistsMessage => 'Matter 已不存在。';

  @override
  String conflictLoadFailed(Object error) {
    return '加载冲突失败：$error';
  }

  @override
  String conflictsCountTitle(int count) {
    return '冲突（$count）';
  }

  @override
  String get refreshAction => '刷新';

  @override
  String get noConflictsDetectedMessage => '未检测到冲突。';

  @override
  String get selectConflictToReviewPrompt => '请选择一个冲突进行查看。';

  @override
  String conflictTypeRow(Object type) {
    return '类型：$type';
  }

  @override
  String conflictFileRow(Object path) {
    return '冲突文件：$path';
  }

  @override
  String conflictOriginalRow(Object path) {
    return '原始：$path';
  }

  @override
  String conflictLocalRow(Object device) {
    return '本地：$device';
  }

  @override
  String conflictRemoteRow(Object device) {
    return '远端：$device';
  }

  @override
  String get openMainNoteAction => '打开主笔记';

  @override
  String get markResolvedAction => '标记为已解决';

  @override
  String failedToLoadConflict(Object error) {
    return '加载冲突内容失败：$error';
  }

  @override
  String get binaryConflictNotPreviewable => '二进制冲突内容无法预览。';

  @override
  String get conflictContentEmpty => '冲突内容为空。';

  @override
  String get viewModePhase => '阶段';

  @override
  String get viewModeTimeline => '时间线';

  @override
  String get viewModeList => '列表';

  @override
  String get viewModeGraph => '关系图';

  @override
  String get newNoteAction => '新建笔记';

  @override
  String get deleteNoteTitle => '删除笔记';

  @override
  String deleteNoteConfirmation(Object title) {
    return '删除 \"$title\"？';
  }

  @override
  String graphLoadFailed(Object error) {
    return '关系图加载失败：$error';
  }

  @override
  String get noLinkedNotesInMatterMessage =>
      '此 Matter 还没有关联笔记。\n请在笔记操作中创建链接来生成关系图。';

  @override
  String graphLimitedNotice(int limit, int hiddenCount) {
    return '关系图最多显示 $limit 个节点（隐藏 $hiddenCount 个）。';
  }

  @override
  String get untitledLabel => '（未命名）';

  @override
  String get orphanNotesTitle => '孤立笔记';

  @override
  String get newOrphanNoteAction => '新建孤立笔记';

  @override
  String get noNotesYetMessage => '还没有笔记。';

  @override
  String get linkNoteActionEllipsis => '关联笔记...';

  @override
  String editorError(Object error) {
    return '编辑器错误：$error';
  }

  @override
  String get selectNoteToEditPrompt => '请选择要编辑的笔记。';

  @override
  String get titleLabel => '标题';

  @override
  String get linkNoteAction => '关联笔记';

  @override
  String get togglePreviewAction => '切换预览';

  @override
  String get deleteNoteAction => '删除笔记';

  @override
  String get tagsCommaSeparatedLabel => '标签（逗号分隔）';

  @override
  String get moveToOrphansAction => '移动到孤立笔记';

  @override
  String get assignToSelectedMatterAction => '分配到当前 Matter';

  @override
  String get writeMarkdownHereHint => '在此输入 Markdown...';

  @override
  String get saveAction => '保存';

  @override
  String updatedAtRow(Object updatedAt) {
    return '更新时间：$updatedAt';
  }

  @override
  String failedToAttachFiles(Object error) {
    return '添加附件失败：$error';
  }

  @override
  String failedToRemoveAttachment(Object error) {
    return '移除附件失败：$error';
  }

  @override
  String get attachmentFileNotFoundMessage => '未找到附件文件';

  @override
  String get unableToOpenAttachmentMessage => '无法打开附件';

  @override
  String unableToOpenAttachmentWithReason(Object reason) {
    return '无法打开附件：$reason';
  }

  @override
  String attachmentsCountTitle(int count) {
    return '附件（$count）';
  }

  @override
  String get attachFilesActionEllipsis => '添加附件...';

  @override
  String get noAttachmentsYetMessage => '还没有附件。';

  @override
  String get storageRootUnavailableMessage => '存储根路径不可用。请先在设置中配置。';

  @override
  String linkedNotesCountTitle(int count) {
    return '关联笔记（$count）';
  }

  @override
  String failedToLoadLinks(Object error) {
    return '加载链接失败：$error';
  }

  @override
  String get noLinksYetMessage => '还没有链接。';

  @override
  String get openLinkedNoteAction => '打开关联笔记';

  @override
  String get removeLinkAction => '移除链接';

  @override
  String unableToLoadNotes(Object error) {
    return '无法加载笔记：$error';
  }

  @override
  String get noNotesAvailableToLink => '没有可关联的笔记。';

  @override
  String get linkCreatedMessage => '链接已创建';

  @override
  String unableToCreateLink(Object error) {
    return '无法创建链接：$error';
  }

  @override
  String linkSourceRow(Object source) {
    return '来源：$source';
  }

  @override
  String get targetNoteLabel => '目标笔记';

  @override
  String get contextOptionalLabel => '上下文（可选）';

  @override
  String get linkContextHint => '这些笔记为什么相关？';

  @override
  String get linkNoteDialogTitle => '关联笔记';

  @override
  String get createLinkAction => '创建链接';

  @override
  String get orphanLabel => '孤立';

  @override
  String get conflictTypeNote => '笔记';

  @override
  String get conflictTypeLink => '链接';

  @override
  String get conflictTypeUnknown => '未知';

  @override
  String get noSearchResultsMessage => '没有搜索结果。';

  @override
  String get languageLabel => '语言';

  @override
  String get settingsSectionStorage => '存储';

  @override
  String get settingsSectionLanguage => '语言';

  @override
  String get settingsSectionSync => '同步';

  @override
  String get syncTargetTypeLabel => '同步目标类型';

  @override
  String get syncTargetTypeNone => '无';

  @override
  String get syncTargetTypeFilesystem => '文件系统';

  @override
  String get syncTargetTypeWebdav => 'WebDAV';

  @override
  String get webDavUrlLabel => 'WebDAV URL';

  @override
  String get webDavUsernameLabel => 'WebDAV 用户名';

  @override
  String get webDavPasswordLabel => 'WebDAV 密码';

  @override
  String get autoSyncIntervalMinutesLabel => '自动同步间隔（分钟）';

  @override
  String get deletionFailSafeLabel => '删除保护';

  @override
  String get createMatterTitle => '新建 Matter';

  @override
  String get editMatterTitle => '编辑 Matter';

  @override
  String get statusLabel => '状态';

  @override
  String get descriptionLabel => '描述';

  @override
  String get colorHexLabel => '颜色（十六进制）';

  @override
  String get colorHexHint => '#4C956C';

  @override
  String get iconNameLabel => '图标名称';

  @override
  String get iconNameHint => 'description';

  @override
  String get createAction => '创建';

  @override
  String get defaultUntitledNoteTitle => '未命名笔记';

  @override
  String get createNoteTitle => '新建笔记';

  @override
  String get editNoteTitle => '编辑笔记';

  @override
  String get markdownContentLabel => 'Markdown 内容';

  @override
  String get defaultQuickCaptureTitle => '快速记录';

  @override
  String get openAttachmentAction => '打开附件';

  @override
  String get removeAttachmentAction => '移除附件';

  @override
  String get loadingEllipsis => '...';

  @override
  String get fileMissingLabel => '缺失';

  @override
  String get imagePreviewUnavailableMessage => '无法预览图片';
}
