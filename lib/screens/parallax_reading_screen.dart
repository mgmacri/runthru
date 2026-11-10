import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runthru/core/book_structure.dart';
import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/core/context_reveal_notifier.dart';
import 'package:runthru/core/motion_parallax_controller.dart';
import 'package:runthru/core/context_reveal_state.dart';
import 'package:runthru/core/dynamic_font_size.dart';
import 'package:runthru/core/gesture_classifier.dart';
import 'package:runthru/core/gradient_sweep_engine.dart';
import 'package:runthru/core/hint_controller.dart';
import 'package:runthru/core/logger.dart';
import 'package:runthru/core/orp.dart';
import 'package:runthru/core/reading_range_resolver.dart';
import 'package:runthru/core/sentence_resolver.dart';
import 'package:runthru/core/text_segmentation.dart';
import 'package:runthru/core/document_title.dart';
import 'package:runthru/core/time_left.dart';
import 'package:runthru/features/content/providers/document_title_provider.dart';
import 'package:runthru/core/word_timer.dart';
import 'package:runthru/design/design.dart';
import 'package:runthru/features/content/providers/instapaper_bookmarks_provider.dart';
import 'package:runthru/features/content/services/reading_progress_sync.dart';
import 'package:runthru/features/reading/chapter_flow.dart';
import 'package:runthru/features/reading/providers/reading_progress_provider.dart';
import 'package:runthru/features/reading/providers/reading_mode_provider.dart';
import 'package:runthru/features/reading/widgets/chapter_title_card.dart';
import 'package:runthru/features/reading/widgets/contents_sheet.dart';
import 'package:runthru/features/reading/widgets/section_complete_overlay.dart';
import 'package:runthru/features/reading/widgets/book_mode_view.dart';
import 'package:runthru/features/reading/widgets/full_page_mode_view.dart';
import 'package:runthru/features/reading/widgets/mode_switcher.dart';
import 'package:runthru/features/reading/widgets/paragraph_mode_view.dart';
import 'package:runthru/hooks/bookmark_notifier.dart';
import 'package:runthru/services/analytics_service.dart';
import 'package:runthru/services/models.dart';
import 'package:runthru/services/preprocessing_queue.dart';
import 'package:runthru/store/analytics_models.dart';
import 'package:runthru/store/bookmark_store.dart';
import 'package:runthru/store/config.dart';
import 'package:runthru/store/models.dart';
import 'package:runthru/three_d/parallax_room.dart';
import 'package:runthru/widgets/context_reveal_overlay.dart';
import 'package:runthru/features/reading/widgets/reading_ruler.dart';
import 'package:runthru/features/reading/widgets/sentence_mode_view.dart';
import 'package:runthru/widgets/finished_range_overlay.dart';
import 'package:runthru/widgets/hint_overlay.dart';
import 'package:runthru/widgets/pause_fog_3d.dart';
import 'package:window_manager/window_manager.dart';

/// Chooses the best local resume index for an imported document.
///
/// Drive can have both the legacy bookmark entry and the cross-source
/// Continue Reading record. The most recent non-finished local record wins.
@visibleForTesting
int? bestImportedResumeIndex({
  BookmarkData? bookmark,
  ProgressRecord? driveProgress,
}) {
  if (driveProgress != null &&
      !driveProgress.finished &&
      driveProgress.wordIndex > 0) {
    final bookmarkIndex = bookmark?.wordIndex ?? 0;
    if (bookmarkIndex <= 0) return driveProgress.wordIndex;

    final bookmarkTime = bookmark?.timestamp;
    if (bookmarkTime != null &&
        driveProgress.lastReadAt.isAfter(bookmarkTime)) {
      return driveProgress.wordIndex;
    }
  }

  return bookmark?.wordIndex;
}

class ParallaxReadingScreen extends ConsumerStatefulWidget {
  const ParallaxReadingScreen({
    super.key,
    required this.filePath,
    this.clipboardDocument,
    this.contentSource = 'local',
    this.instapaperBookmarkId,
    this.instapaperInitialProgress = 0.0,
  });

  final String filePath;

  /// Optional clipboard document (Rule 28 — ephemeral, session-only).
  final ClipboardDocument? clipboardDocument;

  /// Source classification for reading progress and shelf persistence.
  ///
  /// Supported values are `local`, `clipboard`, `instapaper`, and `drive`.
  final String contentSource;

  /// Instapaper bookmark ID — when set, reading progress is synced back to
  /// Instapaper on pause/back and the bookmark is archived on completion.
  final int? instapaperBookmarkId;

  /// Instapaper’s stored progress (0.0–1.0) at the time the article was opened.
  /// Used to resume from the correct position and prevent regressing progress.
  final double instapaperInitialProgress;

  @override
  ConsumerState<ParallaxReadingScreen> createState() =>
      _ParallaxReadingScreenState();
}

class _ParallaxReadingScreenState extends ConsumerState<ParallaxReadingScreen>
    with WidgetsBindingObserver {
  final ValueNotifier<String> _wordNotifier = ValueNotifier('');
  final FocusNode _focusNode = FocusNode();

  // GlobalKeys for onboarding-tour spotlight targeting.
  final GlobalKey _stageKey = GlobalKey(debugLabel: 'rsvp-stage');
  final GlobalKey _playButtonKey = GlobalKey(debugLabel: 'play-button');
  final GlobalKey _prevButtonKey = GlobalKey(debugLabel: 'prev-button');
  final GlobalKey _speedSelectorKey = GlobalKey(debugLabel: 'speed-selector');
  List<String> _words = [];
  List<String> _allDocWords = [];
  int _wordAdvanceCount = 0;

  /// Offset of the current word slice in the global word stream.
  int _sliceOffset = 0;

  /// Active reading range, if any.
  ReadingRange? _readingRange;

  /// Whether the user has completed the reading range.
  bool _isRangeComplete = false;

  /// The full extracted document (kept for "Continue Reading" past range end).
  ExtractedDocument? _fullDoc;

  /// Front matter, chapters and back matter of [_fullDoc] (document-wide
  /// word indices).
  BookStructure _structure = BookStructure.flat(0);

  /// A chapter moment in progress (title card, chapter complete, book
  /// complete). The timer is paused while one is up, but the reader is not
  /// "paused": no fog, no paused panel.
  _Interlude? _interlude;

  /// Shown on the first title card of a book opened past its front matter.
  String? _pendingSkippedNote;

  /// Document word index before the latest timer step (to tell a step from
  /// a jump).
  int _previousGlobalIndex = 0;

  /// The continuous run of reading inside the current section: where it
  /// began and how long it has been playing. Feeds the chapter-complete
  /// figures, and decides whether a chapter was read or merely passed.
  int _runSection = -1;
  int _runFrom = 0;
  final Stopwatch _runClock = Stopwatch();

  /// Time spent playing since this screen opened (book-complete figures).
  final Stopwatch _readingClock = Stopwatch();

  /// Lets the last word of a book stand before the finish screen.
  Timer? _bookEndTimer;

  /// Index of the section being read, for the header and contents sheet.
  final ValueNotifier<int> _sectionIndex = ValueNotifier(0);

  bool get _chapterMomentsOn =>
      ref.read(configProvider).valueOrNull?.chapterMoments ?? true;

  /// Slice-local index of document word [global].
  int _localIndex(int global) =>
      (global - _sliceOffset).clamp(0, _words.isEmpty ? 0 : _words.length - 1);

  /// EPUB chapter starts (document word indices) for Book-mode page breaks.
  /// Other sources' page boundaries are synthetic ~300-word chunks, not
  /// chapters, so they never force a break.
  Set<int> get _chapterStarts {
    final doc = _fullDoc;
    if (doc == null || !widget.filePath.toLowerCase().endsWith('.epub')) {
      return const {};
    }
    return {for (final b in doc.pageBoundaries) b.startWordIndex};
  }

  /// Paragraph starts for Book mode. Documents without paragraph data
  /// (PDFs, books cached before 2.0) get readable fallback paragraphs, a
  /// break after every few sentences, instead of one wall of text.
  Set<int> get _bookParagraphStarts {
    final real = _paragraphStarts;
    if (real.isNotEmpty) return real;
    final doc = _fullDoc;
    if (doc == null) return const {};
    if (identical(doc, _fallbackStartsDoc) &&
        doc.sentences.length == _fallbackStartsSentenceCount) {
      return _fallbackStartsCache;
    }
    // Source page boundaries are not used: PDF and scanned-EPUB pages break
    // mid-sentence.
    final starts = <int>{};
    var index = 0;
    for (var i = 0; i < doc.sentences.length; i++) {
      if (i % _kFallbackSentencesPerParagraph == 0) starts.add(index);
      index += doc.sentences[i].words.length;
    }
    _fallbackStartsDoc = doc;
    _fallbackStartsSentenceCount = doc.sentences.length;
    return _fallbackStartsCache = starts;
  }

  Set<int> _fallbackStartsCache = const {};
  ExtractedDocument? _fallbackStartsDoc;
  int _fallbackStartsSentenceCount = -1;

  /// Landscape with the header and tray visible (Focus Mode off): the
  /// focal word centres between them.
  bool _landscapeChrome(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final focus =
        ref.read(configProvider).valueOrNull?.focusModeEnabled ?? false;
    return size.width > size.height && !focus;
  }

  /// Book mode's page view, for swipe and keyboard page turns.
  final GlobalKey<BookModeViewState> _bookKey = GlobalKey<BookModeViewState>();

  bool get _inBookMode =>
      ref.read(readingModeNotifierProvider) == ReadingMode.book;

  /// Book pages start on a sentence: entering Book mode snaps the reading
  /// position back to the start of the current sentence.
  void _snapToSentenceStartForBook() {
    if (_words.isEmpty) return;
    var start = _sentenceStartAt(_currentGlobalIndex);
    // At a chapter's first sentence the page opens with the chapter's
    // heading, so the page starts at the heading.
    final section = _structure.sectionAt(start);
    if (section.isTitled && start <= section.textStart) start = section.start;
    final local = (start - _sliceOffset).clamp(0, _words.length - 1);
    ref.read(wordTimerProvider.notifier).seekTo(local);
    _cacheTimerPosition(local);
  }

  /// A Book page turn moves the shared reading position.
  void _onBookTurn(int localIndex) {
    final local = localIndex.clamp(0, _words.length - 1);
    final from = _lastGlobalIndex;
    final to = _sliceOffset + local;
    ref.read(wordTimerProvider.notifier).seekTo(local);
    _cacheTimerPosition(local);
    _previousGlobalIndex = to;
    _wordNotifier.value = _words[local];
    _bookTurnedAcross(from, to);
    // Book mode never pauses, so record progress (Continue Reading,
    // Instapaper) on each page turn.
    _recordShelfProgress();
    _recordInstapaperProgress(_lastTimerState, _lastGlobalIndex);
  }

  /// Book mode: turning the page from one chapter into the next marks the
  /// chapter as finished, just as running off its last word does when
  /// timed; turning into the back matter finishes the book.
  void _bookTurnedAcross(int from, int to) {
    final previous = _structure.sectionAt(from);
    final section = _structure.sectionAt(to);
    _sectionIndex.value = section.index;
    if (!_chapterMomentsOn || to <= from) return;
    if (section.index != previous.index + 1 || to != section.start) return;
    if (previous.kind != SectionKind.body) return;
    if (section.kind == SectionKind.back) {
      _showBookComplete(backMatter: section);
      return;
    }
    if (!section.isTitled ||
        previous.wordCount < RunThruTiming.celebrationMinWords) {
      return;
    }
    setState(() {
      _interlude = _CompleteInterlude(
        completionFor(
          _structure,
          completed: previous,
          next: section,
          readFrom: previous.textStart,
          // Book mode is read at the reader's own pace: no timing.
          readingTime: Duration.zero,
          wpm: ref.read(wordTimerProvider).wpm,
        ),
        next: section,
      );
    });
  }

  /// Book mode: the reader turned past the last page.
  void _onBookEnd() {
    if (_interlude != null || !_finishScreenApplies) return;
    _showBookComplete();
  }

  // Heading line starts (document-wide word indices), cached per document.
  // Null when the document records no headings at all (text extracted
  // before headings were kept): Book mode then recognises them by shape.
  Set<int>? _headingStartsCache;
  ExtractedDocument? _headingStartsDoc;

  Set<int>? get _headingStarts {
    final doc = _fullDoc;
    if (doc == null) return null;
    if (!identical(doc, _headingStartsDoc)) {
      _headingStartsDoc = doc;
      final starts = <int>{};
      var index = 0;
      for (final sentence in doc.sentences) {
        if (sentence.isHeading) starts.add(index);
        index += sentence.words.length;
      }
      _headingStartsCache = starts.isEmpty ? null : starts;
    }
    return _headingStartsCache;
  }

  // Paragraph starts (document-wide word indices), cached per document and
  // sentence count: progressive extraction appends sentences in place.
  Set<int> _paragraphStartsCache = const {};
  ExtractedDocument? _paragraphStartsDoc;
  int _paragraphStartsSentenceCount = -1;

  Set<int> get _paragraphStarts {
    final doc = _fullDoc;
    if (doc == null) return const {};
    if (!identical(doc, _paragraphStartsDoc) ||
        doc.sentences.length != _paragraphStartsSentenceCount) {
      _paragraphStartsDoc = doc;
      _paragraphStartsSentenceCount = doc.sentences.length;
      _paragraphStartsCache = paragraphStartWordIndices(doc);
    }
    return _paragraphStartsCache;
  }

  bool _isFullScreen = false;
  Timer? _onboardingCompleteTimer;

  // ── ContextReveal ──
  late final GradientSweepEngine _sweepEngine;
  bool _showCROnboarding = false;

  // ── Onboarding Hints (Rule 27) ──
  late final HintController _hintController;
  HintInfo? _activeHint;
  final List<String> _queuedHintIds = [];
  bool _hasPausedOnce = false;
  bool _hasNavigatedSentence = false;

  // ── Gesture tracking ──
  Offset? _panStart;
  Offset? _panLast;
  DateTime? _panStartTime;

  /// Brief flash on double-tap sentence restart (200ms).
  bool _showRestartFlash = false;
  Timer? _restartFlashTimer;

  // ── Analytics session tracking ──
  DateTime? _sessionStart;
  int _sessionWordCount = 0;

  /// Cached reference for safe use in dispose().
  late final PreprocessingQueue _queue;

  /// Cached analytics service for safe use in dispose().
  late final AnalyticsService _analyticsService;

  /// Cached bookmark notifier for safe use during lifecycle/dispose flushes.
  late final BookmarkNotifier _bookmarkNotifier;

  /// Cached Instapaper notifier for optimistic list updates and queued sync.
  late final InstapaperBookmarks _instapaperBookmarks;

  /// Session-scoped coalescer for debounced progress writes.
  late final ReadingProgressSync _progressSync;

  /// Cross-source Continue Reading store notifier, cached for safe use in
  /// lifecycle/dispose flushes (drives the library's Continue Reading shelf).
  late final ReadingProgress _shelfProgress;

  /// Motion parallax controller — provides sensor-driven head position to
  /// [ParallaxRoom] and [PauseFog3D] without double gyroscope subscriptions.
  late final MotionParallaxController _motionCtrl;

  /// Whether this is an ephemeral clipboard reading session (Rule 28).
  bool get _isClipboard => widget.contentSource == 'clipboard';

  /// Whether this session is reading an Instapaper article.
  bool get _isInstapaper =>
      widget.contentSource == 'instapaper' ||
      widget.instapaperBookmarkId != null;

  /// Whether this session is reading a Google Drive document.
  bool get _isDrive =>
      widget.contentSource == 'drive' || widget.filePath.startsWith('drive://');

  WordTimerState _lastTimerState = const WordTimerState();
  int _lastGlobalIndex = 0;

  static bool get _isDesktop {
    if (kIsWeb) return false;
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  @override
  void initState() {
    super.initState();
    _queue = ref.read(preprocessingQueueProvider.notifier);
    _analyticsService = ref.read(analyticsServiceProvider);
    _bookmarkNotifier = ref.read(bookmarkProvider(widget.filePath).notifier);
    _instapaperBookmarks = ref.read(instapaperBookmarksProvider.notifier);
    _shelfProgress = ref.read(readingProgressProvider.notifier);
    final instapaperBookmarkId = widget.instapaperBookmarkId;
    _progressSync = ReadingProgressSync(
      writeLocalProgress: ({required contentId, required wordIndex}) async {
        if (!_isClipboard || _isInstapaper) {
          _bookmarkNotifier.updateIndex(wordIndex);
          await _bookmarkNotifier.save();
        }
      },
      remoteWriter: instapaperBookmarkId == null
          ? null
          : InstapaperReadingProgressRemoteWriter(
              bookmarkId: instapaperBookmarkId,
              writeProgress: ({required bookmarkId, required progress}) =>
                  _instapaperBookmarks.syncProgress(
                    bookmarkId: bookmarkId,
                    progress: progress,
                  ),
            ),
      onError: (error, stackTrace) {
        appLog('progress-sync', 'progress sync failed');
      },
    );
    final initWpm =
        (ref.read(configProvider).valueOrNull ?? const AppConfig()).defaultWpm;
    _sweepEngine = GradientSweepEngine(
      onAdvance: _onSweepAdvance,
      wpm: initWpm,
    );
    _hintController = HintController(
      configNotifier: ref.read(configProvider.notifier),
    );
    _motionCtrl = MotionParallaxController();
    appLog('ParallaxReadingScreen', 'initState filePath=${widget.filePath}');
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (_isDesktop) _enterDesktopFullScreen();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      appLog('ParallaxReadingScreen', 'post-frame: loading document');
      if (!mounted) return;
      // Start motion tracking (reduced motion + desktop detected at runtime).
      final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
      if (config.parallaxIntensity != ParallaxIntensity.none) {
        _motionCtrl.start(
          reducedMotion: isReducedMotion(context),
          isDesktop: _isDesktop,
        );
      }
      if (widget.clipboardDocument != null) {
        unawaited(_initClipboardReading());
      } else {
        _initReading();
      }
    });
  }

  @override
  void dispose() {
    _endAnalyticsSession();
    // Provider state must not change while the element tree is being torn
    // down: Riverpod asserts on it, and the throw used to abort the rest of
    // dispose() (system bars stayed hidden, the lifecycle observer leaked,
    // the last position was not persisted). Snapshot what is needed now and
    // write it once this frame is done.
    final shelfWrite = _shelfProgressWrite();
    final queue = _queue;
    final filePath = widget.filePath;
    scheduleMicrotask(() {
      shelfWrite?.call();
      // Drop the session's document from queue state — the text stays in
      // PdfCache and is rehydrated by the next prioritize().
      queue.releaseDocument(filePath);
      queue.resumeBackground();
    });
    unawaited(_flushInstapaperProgress());
    unawaited(_progressSync.dispose());
    _restartFlashTimer?.cancel();
    _onboardingCompleteTimer?.cancel();
    _sentenceGapTimer?.cancel();
    _bookEndTimer?.cancel();
    _sectionIndex.dispose();
    _wordNotifier.dispose();
    _focusNode.dispose();
    _sweepEngine.dispose();
    _motionCtrl.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_isDesktop && _isFullScreen) windowManager.setFullScreen(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _endAnalyticsSession() {
    if (_sessionStart == null || _sessionWordCount <= 0) return;
    final duration = DateTime.now().difference(_sessionStart!);
    if (duration.inSeconds < 1) return;

    final minutes = duration.inMilliseconds / 60000.0;
    final avgWpm = minutes > 0 ? _sessionWordCount / minutes : 0.0;

    final session = ReadingSession(
      startTime: _sessionStart!,
      endTime: DateTime.now(),
      wordsRead: _sessionWordCount,
      avgWpm: avgWpm,
      filePath: widget.filePath,
    );
    _sessionStart = null;
    _sessionWordCount = 0;

    // Fire-and-forget — don't block dispose.
    // Use cached reference since ref may be invalid during dispose().
    _analyticsService.saveSession(session);
  }

  /// Records current reading position for throttled Instapaper progress sync.
  void _recordInstapaperProgress(WordTimerState timerState, int globalIndex) {
    if (widget.instapaperBookmarkId == null) return;

    final totalWords = _allDocWords.isNotEmpty
        ? _allDocWords.length
        : timerState.totalWords;
    final progress = totalWords > 0 ? globalIndex / totalWords : 0.0;
    _progressSync.record(
      ReadingProgressSnapshot(
        contentId: widget.filePath,
        wordIndex: globalIndex,
        totalWordCount: totalWords,
        progress: progress,
      ),
    );
  }

  /// Human-readable title for the Continue Reading shelf entry.
  ///
  /// Prefers the supplied document title (Instapaper articles, clipboard);
  /// falls back to the file's base name for local books.
  /// Continue Reading card title: the same title the reader header shows.
  String get _shelfTitle => _documentTitle;

  /// Records the current position to the cross-source Continue Reading store.
  ///
  /// No-op for ephemeral clipboard sessions (Rule 28). Instapaper articles and
  /// local books are persisted so they surface on the library shelf.
  void _recordShelfProgress() => _shelfProgressWrite()?.call();

  /// The Continue Reading write for the current position, or null when there
  /// is nothing to record. All values are captured now, so the returned
  /// closure is safe to run after this state is disposed.
  void Function()? _shelfProgressWrite() {
    if (_isClipboard && !_isInstapaper) return null;
    final total = _allDocWords.isNotEmpty
        ? _allDocWords.length
        : _lastTimerState.totalWords;
    if (total <= 0 || _lastGlobalIndex <= 0) return null;
    // Finished and not read any further: keep it finished.
    if (_finishedAt >= 0 && _lastGlobalIndex == _finishedAt) return null;
    final shelf = _shelfProgress;
    final contentId = widget.filePath;
    final source = _progressSource;
    final title = _shelfTitle;
    final wordIndex = _lastGlobalIndex;
    final contentHash = _queue.contentHashOf(widget.filePath);
    return () => unawaited(
      shelf.record(
        contentId: contentId,
        source: source,
        title: title,
        wordIndex: wordIndex,
        totalWords: total,
        contentHash: contentHash,
      ),
    );
  }

  /// Records this item as read to the end, which takes it off the Continue
  /// Reading shelf. Written with the position, not as a flag on whatever was
  /// last saved: a book read in one sitting has no earlier record, and the
  /// store keeps the mark only while the reader stays at or past this point.
  void _markShelfFinished() {
    if (_isClipboard && !_isInstapaper) return;
    _finishedAt = _lastGlobalIndex;
    final total = _allDocWords.isNotEmpty
        ? _allDocWords.length
        : _lastTimerState.totalWords;
    if (total <= 0) {
      unawaited(_shelfProgress.markFinished(widget.filePath));
      return;
    }
    unawaited(
      _shelfProgress.record(
        contentId: widget.filePath,
        source: _progressSource,
        title: _shelfTitle,
        wordIndex: _lastGlobalIndex,
        totalWords: total,
        contentHash: _queue.contentHashOf(widget.filePath),
        finished: true,
      ),
    );
  }

  /// Where the reader was when the book was marked finished, or -1. While
  /// the position stays there, leaving the book must not write it back to
  /// Continue Reading as "100%, in progress".
  int _finishedAt = -1;

  String get _progressSource {
    if (_isInstapaper) return 'instapaper';
    if (_isDrive) return 'drive';
    return 'local';
  }

  /// Local files (not Drive, Instapaper or clipboard URIs).
  bool get _isLocalFile => !_isClipboard && !_isInstapaper && !_isDrive;

  String get _documentTitle {
    final clipTitle = widget.clipboardDocument?.title.trim();
    if (clipTitle != null && clipTitle.isNotEmpty) return clipTitle;
    // The EPUB's own title when it has one ("The Lighthouse Keeper's
    // Ledger", not "lighthouse"). Cached by build(): this getter also runs
    // from dispose(), where `ref` must not be touched.
    final title = _resolvedTitle;
    if (title != null) return title;
    return prettyFileTitle(widget.filePath);
  }

  /// Metadata title resolved by [documentTitleProvider], cached in build().
  String? _resolvedTitle;

  String get _documentSubtitle {
    if (_isInstapaper) return 'Instapaper';
    if (_isDrive) return 'Google Drive';
    if (_isClipboard) return 'Clipboard';
    return '';
  }

  /// Flush current reading position to local storage and Instapaper queue.
  Future<void> _flushInstapaperProgress() async {
    if (!_isInstapaper) return;
    _recordInstapaperProgress(_lastTimerState, _lastGlobalIndex);
    await _progressSync.flush(contentId: widget.filePath);
  }

  void _cacheTimerPosition(int localIndex) {
    _lastTimerState = ref.read(wordTimerProvider);
    _lastGlobalIndex = _sliceOffset + localIndex;
  }

  /// Archive the Instapaper bookmark when article is fully read.
  /// Optimistically removes from the local list and enqueues durably.
  void _archiveInstapaper() {
    final bookmarkId = widget.instapaperBookmarkId;
    if (bookmarkId == null) return;
    appLog('instapaper', 'queue archive bookmarkId=$bookmarkId');
    _instapaperBookmarks.archive(bookmarkId: bookmarkId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Nobody is reading: stop the words. They used to keep flashing while
      // the app was in the background (a call, another app, the notification
      // shade), so the reader came back to a lost place. A title card must
      // not start reading behind the reader's back either.
      _bookEndTimer?.cancel();
      if (_interlude is _TitleInterlude || _interlude is _HeadingInterlude) {
        _cancelInterlude();
      }
      if (ref.read(wordTimerProvider).isPlaying) {
        ref.read(wordTimerProvider.notifier).pause();
      }
      _endAnalyticsSession();
      // Persist local bookmark for normal docs and Instapaper articles.
      // Pure clipboard sessions remain ephemeral (Rule 28).
      if (!_isClipboard || _isInstapaper) {
        unawaited(ref.read(bookmarkProvider(widget.filePath).notifier).save());
      }
      _recordShelfProgress();
      unawaited(_flushInstapaperProgress());
    } else if (state == AppLifecycleState.resumed) {
      if (ref.read(wordTimerProvider).isPlaying) {
        _sessionStart = DateTime.now();
        _sessionWordCount = 0;
      }
    }
  }

  Future<void> _enterDesktopFullScreen() async {
    await windowManager.ensureInitialized();
    await windowManager.setFullScreen(true);
    setState(() => _isFullScreen = true);
  }

  Future<void> _exitDesktopFullScreen() async {
    await windowManager.setFullScreen(false);
    setState(() => _isFullScreen = false);
  }

  Future<void> _initReading() async {
    appLog('ParallaxReadingScreen', '_initReading() start');
    final queue = ref.read(preprocessingQueueProvider.notifier);
    await queue.prioritize(widget.filePath);
    await ref.read(configProvider.future);
    if (!mounted) return;
    await ref.read(bookmarkStoreProvider.future);

    if (!mounted) return;
    final processed = ref.read(preprocessingQueueProvider);
    final entry = processed[widget.filePath];
    appLog(
      'ParallaxReadingScreen',
      'after prioritize: status=${entry?.status} hasDoc=${entry?.document != null}',
    );

    if (entry?.document != null) {
      _loadDocument(entry!.document!);
    } else {
      final reason = entry?.errorMessage ?? entry?.status.name ?? 'unknown';
      appLog(
        'ParallaxReadingScreen',
        'ERROR: document null after prioritize — reason=$reason entry=$entry',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              entry?.status == PdfStatus.unsupported
                  ? 'This file type is not supported.'
                  : 'Could not open file. It may be missing or corrupted.',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        context.pop();
      }
    }
  }

  /// Initialize reading from a clipboard document (Rule 28 — ephemeral).
  /// Skips the preprocessing queue and loads the document directly.
  Future<void> _initClipboardReading() async {
    final clipDoc = widget.clipboardDocument;
    if (clipDoc == null || clipDoc.words.isEmpty) {
      appLog('ParallaxReadingScreen', 'WARN: clipboard document empty');
      return;
    }
    appLog(
      'ParallaxReadingScreen',
      '_initClipboardReading: ${clipDoc.words.length} words',
    );
    if (_isDrive) {
      await ref.read(readingProgressProvider.future);
    }
    await ref.read(configProvider.future);
    if (!mounted) return;
    // Pure clipboard sessions are ephemeral (Rule 28) — no bookmarks. Only
    // imported sources need the bookmark store loaded before resume.
    if (_isInstapaper || _isDrive) {
      await ref.read(bookmarkStoreProvider.future);
      if (!mounted) return;
    }
    _loadClipboardDocument(clipDoc.document);
  }

  /// Load a clipboard [ExtractedDocument] — no bookmarks, no range.
  void _loadClipboardDocument(ExtractedDocument doc) {
    _fullDoc = doc;
    _allDocWords = doc.allWords;
    _words = _allDocWords;
    _sliceOffset = 0;
    _readingRange = null;
    _structure = analyzeBookStructure(doc);

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();

    // Resume preference for imported sources: local bookmark (most recent
    // on-device position) takes priority. Instapaper can then fall back to the
    // API's coarse 0..1 progress when no local bookmark exists yet.
    final initialProgress = widget.instapaperInitialProgress;
    int startIndex = 0;
    if (_words.isNotEmpty) {
      final localProgressIndex = _bestImportedResumeIndex();
      if (localProgressIndex != null && localProgressIndex > 0) {
        startIndex = localProgressIndex.clamp(0, _words.length - 1);
      } else if (initialProgress > 0) {
        startIndex = (initialProgress * _words.length).round().clamp(
          0,
          _words.length - 1,
        );
      }
      startIndex = _firstOpenStart(startIndex);
    }

    _wordNotifier.value = _words[startIndex];
    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: startIndex);
    _cacheTimerPosition(startIndex);
    _previousGlobalIndex = startIndex;
    _sectionIndex.value = _structure.sectionAt(startIndex).index;
    timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
    timer.setWpm(config.defaultWpm);
    _startTimerAfterFirstRunGate();
    appLog(
      'ParallaxReadingScreen',
      'clipboard timer loaded wpm=${config.defaultWpm} startIndex=$startIndex initialProgress=$initialProgress',
    );
  }

  int? _bestImportedResumeIndex() {
    if (!_isInstapaper && !_isDrive) return null;

    return bestImportedResumeIndex(
      bookmark: ref
          .read(bookmarkStoreProvider.notifier)
          .resolve(widget.filePath),
      driveProgress: _isDrive
          ? _shelfProgress.getRecord(widget.filePath)
          : null,
    );
  }

  void _loadDocument(ExtractedDocument doc) {
    _fullDoc = doc;
    _allDocWords = doc.allWords;
    appLog(
      'ParallaxReadingScreen',
      '_loadDocument: totalWords=${_allDocWords.length}',
    );

    if (_allDocWords.isEmpty) {
      appLog('ParallaxReadingScreen', 'WARN: allWords is empty');
      return;
    }

    _structure = analyzeBookStructure(doc);
    appLog(
      'ParallaxReadingScreen',
      'structure: sections=${_structure.sections.length} '
          'body=${_structure.bodyStart}..${_structure.bodyEnd}',
    );

    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final bookmark = _bookmarkForCurrentText(
      ref.read(bookmarkStoreProvider.notifier).resolve(widget.filePath),
    );
    final range = bookmark?.readingRange;

    if (range != null && doc.hasPageBoundaries) {
      // Resolve the range to global indices.
      final resolved = resolveAndValidateRange(
        range,
        doc.pageBoundaries,
        _allDocWords,
      );
      if (resolved != null) {
        _readingRange = resolved;
        final rangeStart = resolved.resolvedStartWordIndex;
        final rangeEnd = resolved.resolvedEndWordIndex.clamp(
          0,
          _allDocWords.length - 1,
        );
        _sliceOffset = rangeStart;
        _words = _allDocWords.sublist(rangeStart, rangeEnd + 1);

        // Compute start index within the slice.
        final lastPosition = bookmark?.wordIndex ?? 0;
        int startIndex;
        if (lastPosition <= rangeStart) {
          startIndex = 0;
        } else if (lastPosition >= rangeEnd) {
          // Finished range — show overlay.
          startIndex = _words.length - 1;
          _isRangeComplete = true;
        } else {
          // Resume within slice — resolve sentence boundary.
          final globalResume = resumeIndex(bookmark!, doc);
          startIndex = (globalResume - rangeStart).clamp(0, _words.length - 1);
        }

        appLog(
          'ParallaxReadingScreen',
          'range: $rangeStart-$rangeEnd, sliceLen=${_words.length}, startIdx=$startIndex',
        );

        _wordNotifier.value = _words[startIndex.clamp(0, _words.length - 1)];
        final timer = ref.read(wordTimerProvider.notifier);
        timer.loadDocument(_words.length, startIndex: startIndex);
        _cacheTimerPosition(startIndex);
        _previousGlobalIndex = _sliceOffset + startIndex;
        _sectionIndex.value = _structure
            .sectionAt(_sliceOffset + startIndex)
            .index;
        timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
        timer.setWpm(config.defaultWpm);

        if (_isRangeComplete) {
          timer.pause();
        } else {
          _startTimerAfterFirstRunGate();
        }
        appLog(
          'ParallaxReadingScreen',
          'timer loaded with range slice, wpm=${config.defaultWpm}',
        );
        return;
      }
    }

    // No range — full document.
    _words = _allDocWords;
    _sliceOffset = 0;
    _readingRange = null;

    final startIndex = _firstOpenStart(
      bookmark != null ? resumeIndex(bookmark, doc) : 0,
    );
    appLog('ParallaxReadingScreen', 'startIndex=$startIndex');

    _wordNotifier.value = _words[startIndex.clamp(0, _words.length - 1)];
    // Privacy: log seed length only — never reading content.
    appLog(
      'ParallaxReadingScreen',
      'wordNotifier seeded len=${_wordNotifier.value.length}',
    );

    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: startIndex);
    _cacheTimerPosition(startIndex);
    _previousGlobalIndex = startIndex;
    _sectionIndex.value = _structure.sectionAt(startIndex).index;
    timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
    timer.setWpm(config.defaultWpm);
    _startTimerAfterFirstRunGate();
    appLog('ParallaxReadingScreen', 'timer loaded wpm=${config.defaultWpm}');
  }

  /// Where a document opens. A book with no saved position starts at its
  /// first real chapter, not at its cover and copyright page; the skipped
  /// part stays one tap away on the first title card.
  int _firstOpenStart(int resumeAt) {
    if (resumeAt > 0) return resumeAt;
    final bodyStart = _structure.bodyStart;
    if (bodyStart <= 0 || bodyStart >= _allDocWords.length) return resumeAt;
    final wpm =
        (ref.read(configProvider).valueOrNull ?? const AppConfig()).defaultWpm;
    _pendingSkippedNote =
        'Skipped the front matter · ${formatMinutes(minutesFor(bodyStart, wpm))}';
    appLog('ParallaxReadingScreen', 'first open: starting at body $bodyStart');
    return bodyStart;
  }

  /// A saved position was a word index into the text as it was extracted
  /// then. When this build extracts the same book differently (page
  /// furniture removed, split words rejoined), the old index would land a
  /// little further on: scale it by the change in length and store it.
  BookmarkData? _bookmarkForCurrentText(BookmarkData? bookmark) {
    if (bookmark == null || bookmark.wordIndex <= 0) return bookmark;
    final record = _shelfProgress.getRecord(widget.filePath);
    final oldTotal = record?.totalWords ?? 0;
    final newTotal = _allDocWords.length;
    if (oldTotal <= 0 || oldTotal == newTotal || newTotal <= 0) return bookmark;
    final scaled = (bookmark.wordIndex * newTotal / oldTotal).round().clamp(
      0,
      newTotal - 1,
    );
    appLog(
      'ParallaxReadingScreen',
      'text length changed $oldTotal→$newTotal; position rescaled',
    );
    _bookmarkNotifier.updateIndex(scaled);
    return bookmark.copyWith(wordIndex: scaled);
  }

  void _startTimerAfterFirstRunGate() {
    final config = ref.read(configProvider).valueOrNull ?? const AppConfig();
    final timer = ref.read(wordTimerProvider.notifier);

    // Open in the mode the reader last used.
    if (config.lastReadingMode != null) {
      ref
          .read(readingModeNotifierProvider.notifier)
          .setMode(ReadingModeX.parse(config.lastReadingMode));
    }
    // Book mode is read at the reader's own pace: no timer.
    if (_inBookMode) {
      timer.pause();
      _snapToSentenceStartForBook();
      return;
    }

    // P8 Grade B — show reading goal onboarding once before first session.
    if (!config.hasSeenReadingGoalOnboarding) {
      timer.pause();
      return;
    }

    _play();
  }

  /// Starts or resumes timed reading from the current position.
  ///
  /// At a chapter's first word its title card comes first, and reading then
  /// starts after the heading: the title is announced, not flashed word by
  /// word. Anywhere else this is the timer's own play (with its rewind).
  void _play() {
    if (_words.isEmpty) return;
    final timer = ref.read(wordTimerProvider.notifier);
    final global = _currentGlobalIndex;
    if (_chapterMomentsOn) {
      final start = playStartFor(_structure, global);
      final section = start.announce;
      final skipped = _pendingSkippedNote;
      if (section != null) {
        _pendingSkippedNote = null;
        _announce(section, resumeAt: start.from, skippedNote: skipped);
        return;
      }
      if (skipped != null) {
        // No chapter heading where the book starts: announce the book.
        _pendingSkippedNote = null;
        setState(() {
          _interlude = _TitleInterlude(
            ChapterAnnouncement(headline: _documentTitle, skippedNote: skipped),
            resumeAt: start.from,
          );
        });
        return;
      }
      if (start.from != global) {
        _beginSession();
        timer.resumeFromContextReveal(_localIndex(start.from));
        return;
      }
    }
    _pendingSkippedNote = null;
    _beginSession();
    timer.play();
  }

  void _beginSession() {
    _sessionStart = DateTime.now();
    _sessionWordCount = 0;
  }

  /// Shows [section]'s heading, then reads on from [resumeAt].
  void _announce(
    BookSection section, {
    required int resumeAt,
    String? skippedNote,
  }) {
    final timer = ref.read(wordTimerProvider.notifier);
    final wpm = ref.read(wordTimerProvider).wpm;
    if (ref.read(wordTimerProvider).isPlaying) timer.pause();
    _sectionIndex.value = section.index;
    setState(() {
      // The book's chapters get the full card; front and back matter only
      // have their heading shown whole.
      _interlude = section.kind == SectionKind.body
          ? _TitleInterlude(
              announcementFor(
                _structure,
                section,
                wpm: wpm,
                skippedNote: skippedNote,
              ),
              resumeAt: resumeAt,
            )
          : _HeadingInterlude(section.displayName(), resumeAt: resumeAt);
    });
  }

  /// A chapter moment is over: read on from document word [resumeAt].
  void _endInterludeAndRead(int resumeAt) {
    if (!mounted || _interlude == null) return;
    setState(() => _interlude = null);
    if (_inBookMode || _words.isEmpty) return;
    _beginSession();
    final local = _localIndex(resumeAt);
    _previousGlobalIndex = _sliceOffset + local;
    ref.read(wordTimerProvider.notifier).resumeFromContextReveal(local);
  }

  /// The main action of the moment that is showing: start reading under a
  /// title card, go on from a finished chapter.
  void _advanceInterlude() {
    switch (_interlude) {
      case _TitleInterlude(:final resumeAt):
      case _HeadingInterlude(:final resumeAt):
        _endInterludeAndRead(resumeAt);
      case _CompleteInterlude(:final next):
        _continueToSection(next);
      case _BookInterlude():
      case null:
        break;
    }
  }

  /// After a finished chapter: on to [next], announced by its title card.
  void _continueToSection(BookSection next) {
    if (!mounted) return;
    if (_inBookMode) {
      setState(() => _interlude = null);
      return;
    }
    _runSection = -1;
    _announce(next, resumeAt: next.textStart);
  }

  /// "Take a break": stay paused on the first word of the next chapter.
  void _breakAtSection(BookSection next) {
    if (!mounted) return;
    setState(() => _interlude = null);
    if (_inBookMode || _words.isEmpty) return;
    final local = _localIndex(next.start);
    ref.read(wordTimerProvider.notifier).seekTo(local);
    _cacheTimerPosition(local);
    _previousGlobalIndex = _sliceOffset + local;
    _wordNotifier.value = _words[local];
    _recordShelfProgress();
  }

  /// From the finish screen: read on into the notes and extras.
  void _keepReadingBackMatter(BookSection backMatter) {
    if (!mounted) return;
    setState(() => _interlude = null);
    if (_inBookMode || _words.isEmpty) return;
    final local = _localIndex(backMatter.start);
    ref.read(wordTimerProvider.notifier).seekTo(local);
    _cacheTimerPosition(local);
    _previousGlobalIndex = _sliceOffset + local;
    _wordNotifier.value = _words[local];
    _play();
  }

  /// From the finish screen: start the book's text again.
  void _readAgain() {
    final first = _structure.chapters.isEmpty
        ? _structure.sections.first
        : _structure.chapters.first;
    _jumpToSection(first);
  }

  /// Leaves a chapter moment without reading on: the reader stays paused.
  void _cancelInterlude() {
    if (_interlude == null || !mounted) return;
    setState(() => _interlude = null);
  }

  /// The reader asked for the front matter after all.
  void _restartFromBeginning() {
    if (_words.isEmpty) return;
    setState(() => _interlude = null);
    final local = _localIndex(0);
    ref.read(wordTimerProvider.notifier).seekTo(local);
    _cacheTimerPosition(local);
    _previousGlobalIndex = _sliceOffset + local;
    _wordNotifier.value = _words[local];
    _play();
  }

  /// Moves to [section] (from the contents sheet, or "Read it again") and
  /// starts reading it.
  void _jumpToSection(BookSection section) {
    if (_words.isEmpty) return;
    _bookEndTimer?.cancel();
    final timer = ref.read(wordTimerProvider.notifier);
    if (ref.read(wordTimerProvider).isPlaying) timer.pause();
    setState(() => _interlude = null);
    final local = _localIndex(section.start);
    timer.seekTo(local);
    _cacheTimerPosition(local);
    _previousGlobalIndex = _sliceOffset + local;
    _sectionIndex.value = section.index;
    _wordNotifier.value = _words[local];
    _recordShelfProgress();
    if (_inBookMode) return;
    _play();
  }

  /// Whether the whole document is loaded (not a page-range slice), so any
  /// section can be jumped to.
  bool get _wholeDocument =>
      _sliceOffset == 0 && _words.length == _allDocWords.length;

  /// Whether there is a contents list worth showing.
  bool get _hasContents =>
      _wholeDocument &&
      (_structure.hasChapters ||
          _structure.hasFrontMatter ||
          _structure.hasBackMatter);

  /// Opens the contents sheet; picking a section jumps to it.
  Future<void> _openContents() async {
    if (!mounted || !_hasContents) return;
    // The finished screens have their own choices.
    if (_interlude is _CompleteInterlude || _interlude is _BookInterlude) {
      return;
    }
    _cancelInterlude();
    _bookEndTimer?.cancel();
    if (ref.read(wordTimerProvider).isPlaying) {
      ref.read(wordTimerProvider.notifier).pause();
      _recordShelfProgress();
      _endAnalyticsSession();
    }
    final picked = await showContentsSheet(
      context,
      structure: _structure,
      currentWord: _currentGlobalIndex,
      wpm: ref.read(wordTimerProvider).wpm,
      bookTitle: _documentTitle,
    );
    if (!mounted || picked == null) return;
    _jumpToSection(picked);
  }

  /// Keeps the run of continuous reading in the current section up to date.
  void _trackRun(int global) {
    final section = _structure.sectionAt(global);
    if (section.index != _runSection) {
      _runSection = section.index;
      _runFrom = global;
      _runClock.reset();
      if (ref.read(wordTimerProvider).isPlaying) _runClock.start();
      _sectionIndex.value = section.index;
    }
  }

  /// Acts on a chapter boundary reached while reading. Returns true when
  /// the step was taken over (a moment is showing, or the position moved
  /// on) and the word at [global] must not be flashed.
  bool _handleChapterStep(int previous, int global) {
    final event = chapterEventFor(
      structure: _structure,
      previous: previous,
      current: global,
    );
    if (event == null) {
      _trackRun(global);
      return false;
    }
    final timer = ref.read(wordTimerProvider.notifier);
    final wpm = ref.read(wordTimerProvider).wpm;
    switch (event) {
      case SkipHeading(:final to):
        // A rewind or seek landed among heading words: carry on from the
        // text. (The seek re-enters the listener with the new position.)
        timer.seekTo(_localIndex(to));
        return true;
      case SubHeadingReached(:final heading):
        timer.pause();
        setState(() {
          _interlude = _HeadingInterlude(
            heading.text,
            resumeAt: heading.start + heading.wordCount,
          );
        });
        return true;
      case SectionBoundary(:final completed, :final next):
        final readFrom = _runSection == completed.index
            ? _runFrom
            : completed.end;
        final wordsRead =
            completed.end -
            (readFrom < completed.textStart ? completed.textStart : readFrom);
        final readingTime = _runClock.elapsed;
        timer.pause();
        // The position is now the new chapter: reopening starts there.
        _lastGlobalIndex = global;
        if (!_isClipboard || _isInstapaper) {
          _bookmarkNotifier.updateIndex(global);
        }
        _recordShelfProgress();
        if (event.endsBook) {
          _showBookComplete(backMatter: next);
          return true;
        }
        final celebrate =
            completed.kind == SectionKind.body &&
            next.kind == SectionKind.body &&
            wordsRead >= RunThruTiming.celebrationMinWords;
        if (!celebrate) {
          _announce(next, resumeAt: next.textStart);
          return true;
        }
        _sectionIndex.value = next.index;
        setState(() {
          _interlude = _CompleteInterlude(
            completionFor(
              _structure,
              completed: completed,
              next: next,
              readFrom: readFrom,
              readingTime: readingTime,
              wpm: wpm,
            ),
            next: next,
          );
        });
        return true;
    }
  }

  /// The book's text is finished: mark it read and say so.
  void _showBookComplete({BookSection? backMatter}) {
    if (!mounted) return;
    _bookEndTimer?.cancel();
    final timer = ref.read(wordTimerProvider.notifier);
    if (ref.read(wordTimerProvider).isPlaying) timer.pause();
    if (!_isInstapaper) _markShelfFinished();
    final wpm = ref.read(wordTimerProvider).wpm;
    final structure = _structure;
    final titledChapters = structure.chapters.where((s) => s.isTitled).length;
    setState(() {
      _interlude = _BookInterlude(
        BookCompletion(
          title: _documentTitle,
          wordsInBook: structure.bodyEnd - structure.bodyStart,
          chapterCount: structure.hasChapters ? titledChapters : 0,
          sessionTime: _readingClock.elapsed,
          backMatterMinutes: backMatter == null
              ? null
              : minutesFor(structure.totalWords - backMatter.start, wpm),
        ),
        backMatter: backMatter,
      );
    });
  }

  /// Whether reaching the last word should bring up the finish screen.
  bool get _finishScreenApplies =>
      _readingRange == null &&
      _allDocWords.length >= RunThruTiming.bookCompleteMinWords;

  void _togglePause() {
    appLog('gestures', 'detected: tap');
    // Book mode has no timer; Space turns the page instead.
    if (_inBookMode) {
      if (_interlude != null) return;
      _bookKey.currentState?.nextPage();
      return;
    }
    // "Pause" while a title card is up: stay here, paused. The finished
    // screens have their own buttons.
    final interlude = _interlude;
    if (interlude is _TitleInterlude || interlude is _HeadingInterlude) {
      _cancelInterlude();
      return;
    }
    if (interlude != null) return;
    _bookEndTimer?.cancel();
    // P20 — tap during ContextReveal toggles sweep pause, not RSVP
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      ref.read(contextRevealProvider.notifier).toggleSweepPause();
      if (crState.isSweepPaused) {
        _sweepEngine.resume();
      } else {
        _sweepEngine.pause();
      }
      return;
    }
    final timer = ref.read(wordTimerProvider.notifier);
    if (ref.read(wordTimerProvider).isPlaying) {
      timer.pause();
      if (!_isClipboard || _isInstapaper) {
        unawaited(
          ref
              .read(bookmarkProvider(widget.filePath).notifier)
              .save()
              .catchError((Object e) {
                appLog('bookmark', 'save failed on pause: $e');
              }),
        );
      }
      _recordShelfProgress();
      _endAnalyticsSession();
      unawaited(_flushInstapaperProgress());
      if (!_hasPausedOnce) {
        _hasPausedOnce = true;
        _tryShowHint(HintId.swipeLr);
      }
    } else {
      _play();
    }
  }

  // P4 Grade C — double-tap restarts current sentence
  void _handleDoubleTap() {
    appLog('gestures', 'detected: doubleTap');
    if (_interlude != null) return;

    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      // Sentence view: restart sweep from first word
      ref.read(contextRevealProvider.notifier).resetSweep();
      _sweepEngine.reset();
      _sweepEngine.start();
      appLog('gestures', 'action: doubleTap → restart sweep');
      return;
    }

    // RSVP mode: restart current sentence
    if (_fullDoc == null) return;
    final globalIdx = _currentGlobalIndex;
    var cumulative = 0;
    int previousSentenceStart = 0;

    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIdx < sentenceEnd) {
        // If already at sentence start, seek to previous sentence.
        final targetGlobal = globalIdx == cumulative
            ? previousSentenceStart
            : cumulative;
        final localTarget = (targetGlobal - _sliceOffset).clamp(
          0,
          _words.length - 1,
        );
        ref
            .read(wordTimerProvider.notifier)
            .restartCurrentSentence(localTarget);
        _flashRestartHighlight();
        appLog(
          'gestures',
          'action: doubleTap → restart sentence at word $targetGlobal',
        );
        return;
      }
      previousSentenceStart = cumulative;
      cumulative = sentenceEnd;
    }
  }

  /// Brief anchor highlight flash to confirm sentence restart.
  // P4 Grade C — 200ms flash using RunThruTiming.restartHighlightMs
  void _flashRestartHighlight() {
    _restartFlashTimer?.cancel();
    setState(() => _showRestartFlash = true);
    _restartFlashTimer = Timer(
      const Duration(milliseconds: RunThruTiming.restartHighlightMs),
      () {
        if (mounted) setState(() => _showRestartFlash = false);
      },
    );
  }

  // ── Hint trigger helpers (Rule 27) ──

  /// Show a hint if it hasn't been shown before. Does nothing if another
  /// hint is already active or if the word timer is actively advancing
  /// (hints don't interrupt word display).
  void _tryShowHint(String hintId) {
    if (_activeHint != null) return;
    // Coach hints describe the timed reader ("Tap to pause").
    if (_inBookMode) return;
    final hint = _hintController.check(hintId);
    if (hint != null) {
      setState(() => _activeHint = hint);
    }
  }

  void _dismissActiveHint() {
    final hint = _activeHint;
    if (hint == null) return;
    _hintController.markShown(hint.id);
    final next = _nextQueuedHint();
    setState(() => _activeHint = next);
  }

  HintInfo? _nextQueuedHint() {
    while (_queuedHintIds.isNotEmpty) {
      final id = _queuedHintIds.removeAt(0);
      final hint = _hintController.check(id);
      if (hint != null) return hint;
    }
    return null;
  }

  Future<void> _setFocusModeEnabled(bool enabled) async {
    await ref.read(configProvider.notifier).setFocusModeEnabled(enabled);
    if (!mounted) return;
    _queuedHintIds.removeWhere(_isFocusModeHint);
    if (_activeHint != null && _isFocusModeHint(_activeHint!.id)) {
      setState(() => _activeHint = null);
    }
  }

  bool _isFocusModeHint(String id) {
    return id == HintId.focusPause ||
        id == HintId.focusBackSentence ||
        id == HintId.focusForwardSentence;
  }

  void _selectPausedWpm(int selectedWpm) {
    ref.read(wordTimerProvider.notifier).setWpm(selectedWpm);
    _sweepEngine.updateWpm(selectedWpm);
  }

  /// Extends reading past the original range end to the end of the document.
  void _continueReadingPastRange() {
    if (_fullDoc == null || _readingRange == null) return;

    final rangeEnd = _readingRange!.resolvedEndWordIndex;
    final remaining = _allDocWords.sublist(rangeEnd + 1);
    if (remaining.isEmpty) return;

    _endAnalyticsSession();

    setState(() {
      _isRangeComplete = false;
      _words = remaining;
      _sliceOffset = rangeEnd + 1;
    });

    _wordNotifier.value = _words.first;
    final timer = ref.read(wordTimerProvider.notifier);
    timer.loadDocument(_words.length, startIndex: 0);
    _cacheTimerPosition(0);
    timer.attachWordSource((i) => i < _words.length ? _words[i] : null);
    _previousGlobalIndex = _sliceOffset;
    if (_inBookMode) return;
    _play();
  }

  void _toggleFullScreen() {
    if (_isDesktop) {
      if (_isFullScreen) {
        _exitDesktopFullScreen();
      } else {
        _enterDesktopFullScreen();
      }
    } else {
      setState(() => _isFullScreen = !_isFullScreen);
      SystemChrome.setEnabledSystemUIMode(
        _isFullScreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    }
  }

  void _goBack() {
    if (!mounted) return;
    _bookEndTimer?.cancel();
    // Dismiss ContextReveal if active before navigating away.
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      ref.read(contextRevealProvider.notifier).dismiss();
      _sentenceGapTimer?.cancel();
      _sweepEngine.stop();
    }
    if (!_isClipboard || _isInstapaper) {
      // Fire-and-forget: BookmarkNotifier is not auto-disposed, so the async
      // save completes even after this widget is popped.
      unawaited(
        ref.read(bookmarkProvider(widget.filePath).notifier).save().catchError((
          Object e,
        ) {
          appLog('bookmark', 'save failed on back: $e');
        }),
      );
    }
    _recordShelfProgress();
    unawaited(_flushInstapaperProgress());
    ref.read(wordTimerProvider.notifier).pause();
    if (mounted) context.pop();
  }

  // ── ContextReveal gesture handlers ──

  /// Current global word index from the timer.
  int get _currentGlobalIndex {
    final localIdx = ref.read(wordTimerProvider).currentIndex;
    return _sliceOffset + localIdx;
  }

  /// Extract visible words for the current CR tier + window.
  List<String> _contextRevealWords() {
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) return [];

    final leftmost = crState.resumeWordIndex;
    final tier = crState.tier;

    if (tier == ContextRevealTier.sentence) {
      return _sentenceWordsAt(leftmost);
    }

    final count = tier.wordCount;
    final half = count ~/ 2;
    final start = (leftmost - half).clamp(0, _allDocWords.length - 1);
    final end = (start + count).clamp(0, _allDocWords.length);
    return _allDocWords.sublist(start, end);
  }

  /// Get all words in the sentence containing [globalIndex].
  List<String> _sentenceWordsAt(int globalIndex) {
    if (_fullDoc == null) return [];
    var cumulative = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIndex < sentenceEnd) {
        return sentence.words;
      }
      cumulative = sentenceEnd;
    }
    // Past end — return last sentence
    return _fullDoc!.sentences.isNotEmpty ? _fullDoc!.sentences.last.words : [];
  }

  /// Get the global start index of the sentence containing [globalIndex].
  int _sentenceStartAt(int globalIndex) {
    if (_fullDoc == null) return globalIndex;
    var cumulative = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIndex < sentenceEnd) return cumulative;
      cumulative = sentenceEnd;
    }
    // Past end — return start of last sentence
    if (_fullDoc!.sentences.isNotEmpty) {
      return cumulative - _fullDoc!.sentences.last.words.length;
    }
    return globalIndex;
  }

  void _onSwipeUp() {
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) {
      ref.read(readingModeNotifierProvider.notifier).cycleMode();
      final mode = ref.read(readingModeNotifierProvider).label;
      appLog('gestures', 'action: swipeUp → reading mode $mode');
    } else {
      // P1 Grade C — elastic jiggle ceiling feedback
      appLog('gestures', 'action: swipeUp → jiggle (already in sentence view)');
      ref.read(contextRevealProvider.notifier).triggerJiggle();
    }
  }

  // v4 — dismiss CR onboarding, mark hint shown, then enter CR
  void _dismissCROnboarding() {
    setState(() => _showCROnboarding = false);
    ref.read(configProvider.notifier).markHintShown('hint_swipe_up');
    ref.read(contextRevealProvider.notifier).enterSentence(_currentGlobalIndex);
    _sweepEngine.start();
  }

  void _onSwipeDown() {
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) {
      ref.read(readingModeNotifierProvider.notifier).cycleModeReverse();
      final mode = ref.read(readingModeNotifierProvider).label;
      appLog('gestures', 'action: swipeDown → reading mode $mode');
      return;
    }
    appLog('gestures', 'action: swipeDown → dismissing ContextReveal');

    // Compute the global index of the currently highlighted word (sweep
    // position within the visible sentence) so RSVP resumes at that word.
    final sweepPos = crState.sweepPosition;
    final sentenceStartGlobal = _sentenceStartAt(crState.resumeWordIndex);
    final resumeGlobal = sentenceStartGlobal + sweepPos;

    ref.read(contextRevealProvider.notifier).dismiss();
    _sentenceGapTimer?.cancel();
    _sweepEngine.stop();
    final localIndex = (resumeGlobal - _sliceOffset).clamp(
      0,
      _words.length - 1,
    );
    ref.read(wordTimerProvider.notifier).resumeFromContextReveal(localIndex);
  }

  void _onSwipeLeft() {
    if (_inBookMode) {
      _bookKey.currentState?.nextPage();
      return;
    }
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      // v4 — sentence mode: navigate to next sentence
      if (_fullDoc == null) return;
      final currentStart = _sentenceStartAt(crState.resumeWordIndex);
      final sentenceWords = _sentenceWordsAt(currentStart);
      final nextStart = currentStart + sentenceWords.length;
      if (nextStart < _allDocWords.length) {
        _sentenceGapTimer?.cancel();
        ref.read(contextRevealProvider.notifier).enterSentence(nextStart);
        _sweepEngine.reset();
        _sweepEngine.start();
        appLog(
          'gestures',
          'action: swipeLeft → next sentence at word $nextStart',
        );
      } else {
        appLog('gestures', 'action: swipeLeft → already at last sentence');
      }
    } else {
      // v4 — RSVP mode: navigate to next sentence
      _seekToNextSentence();
      // P27 — show double-tap hint after first sentence navigation
      if (!_hasNavigatedSentence) {
        _hasNavigatedSentence = true;
        _tryShowHint(HintId.doubleTap);
      }
    }
  }

  void _onSwipeRight() {
    if (_inBookMode) {
      _bookKey.currentState?.previousPage();
      return;
    }
    final crState = ref.read(contextRevealProvider);
    if (crState.isActive) {
      // v4 — sentence mode: navigate to previous sentence
      if (_fullDoc == null) return;
      final currentStart = _sentenceStartAt(crState.resumeWordIndex);
      if (currentStart > 0) {
        _sentenceGapTimer?.cancel();
        final prevStart = _sentenceStartAt(currentStart - 1);
        ref.read(contextRevealProvider.notifier).enterSentence(prevStart);
        _sweepEngine.reset();
        _sweepEngine.start();
        appLog(
          'gestures',
          'action: swipeRight → previous sentence at word $prevStart',
        );
      } else {
        appLog('gestures', 'action: swipeRight → already at first sentence');
      }
    } else {
      // v4 — RSVP mode: navigate to previous sentence
      _seekToPreviousSentence();
      // P27 — show double-tap hint after first sentence navigation
      if (!_hasNavigatedSentence) {
        _hasNavigatedSentence = true;
        _tryShowHint(HintId.doubleTap);
      }
    }
  }

  /// Navigate to the first word of the next sentence (RSVP mode).
  void _seekToNextSentence() {
    if (_fullDoc == null) return;
    if (_interlude is _CompleteInterlude || _interlude is _BookInterlude) {
      return;
    }
    _cancelInterlude();
    final globalIdx = _currentGlobalIndex;
    var cumulative = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIdx < sentenceEnd) {
        // Current sentence found — seek to start of next sentence.
        if (sentenceEnd < _allDocWords.length) {
          final localTarget = (sentenceEnd - _sliceOffset).clamp(
            0,
            _words.length - 1,
          );
          ref.read(wordTimerProvider.notifier).seekTo(localTarget);
          appLog(
            'gestures',
            'action: swipeLeft → next sentence at word $sentenceEnd',
          );
        } else {
          appLog('gestures', 'action: swipeLeft → already at last sentence');
        }
        return;
      }
      cumulative = sentenceEnd;
    }
  }

  /// Navigate to the first word of the previous sentence (RSVP mode).
  void _seekToPreviousSentence() {
    if (_fullDoc == null) return;
    if (_interlude is _CompleteInterlude || _interlude is _BookInterlude) {
      return;
    }
    _cancelInterlude();
    final globalIdx = _currentGlobalIndex;
    var cumulative = 0;
    int previousSentenceStart = 0;
    for (final sentence in _fullDoc!.sentences) {
      final sentenceEnd = cumulative + sentence.words.length;
      if (globalIdx < sentenceEnd) {
        // If already at sentence start, go to previous sentence.
        final target = globalIdx == cumulative
            ? previousSentenceStart
            : cumulative;
        final localTarget = (target - _sliceOffset).clamp(0, _words.length - 1);
        ref.read(wordTimerProvider.notifier).seekTo(localTarget);
        appLog(
          'gestures',
          'action: swipeRight → previous sentence at word $target',
        );
        return;
      }
      previousSentenceStart = cumulative;
      cumulative = sentenceEnd;
    }
  }

  Timer? _sentenceGapTimer;

  void _onSweepAdvance() {
    if (!mounted) return;
    final crState = ref.read(contextRevealProvider);
    if (!crState.isActive) return;
    final words = _contextRevealWords();
    final atEnd = ref
        .read(contextRevealProvider.notifier)
        .advanceSweep(words.length);
    if (atEnd) {
      _autoAdvanceToNextSentence(crState);
    }
  }

  /// Auto-advance to next sentence after the inter-sentence gap delay.
  // Grade D — tunable via RunThruTiming.sentenceGapMs
  void _autoAdvanceToNextSentence(ContextRevealState crState) {
    _sentenceGapTimer?.cancel();
    _sweepEngine.pause();
    _sentenceGapTimer = Timer(
      const Duration(milliseconds: RunThruTiming.sentenceGapMs),
      () {
        if (!mounted) return;
        final current = ref.read(contextRevealProvider);
        if (!current.isActive || current.isSweepPaused) return;
        if (_fullDoc == null) return;

        final currentStart = _sentenceStartAt(current.resumeWordIndex);
        final sentenceWords = _sentenceWordsAt(currentStart);
        final nextStart = currentStart + sentenceWords.length;

        if (nextStart < _allDocWords.length) {
          ref.read(contextRevealProvider.notifier).enterSentence(nextStart);
          _sweepEngine.reset();
          _sweepEngine.start();
          appLog('sweep', 'auto-advance to sentence at word $nextStart');
        } else {
          // Last sentence — hold on final word, no further advance
          _sweepEngine.stop();
          appLog('sweep', 'reached last sentence, holding');
        }
      },
    );
  }

  // P3 Grade C — swipe detection via Listener pointer events.
  // Uses classifySwipe() from gesture_classifier.dart for dual-gate
  // threshold validation (distance ratio + velocity).
  // RULE 24 COMPLIANCE: Listener is used instead of onVerticalDragEnd /
  // onHorizontalDragEnd so swipe detection never competes in the gesture
  // arena with overlay GestureDetectors. Raw pointer events bypass the
  // arena and are consistent with Rule 24's intent.
  void _handlePointerUp(PointerUpEvent event) {
    final start = _panStart;
    final last = _panLast;
    final startTime = _panStartTime;
    _panStart = null;
    _panLast = null;
    _panStartTime = null;

    if (start == null || last == null || startTime == null) return;
    // A chapter moment owns the screen: its taps are its own.
    if (_interlude != null) return;

    final dx = last.dx - start.dx;
    final dy = last.dy - start.dy;
    final elapsedMs = DateTime.now().difference(startTime).inMilliseconds;
    final screenSize = MediaQuery.sizeOf(context);

    final direction = classifySwipe(
      dx: dx,
      dy: dy,
      elapsedMs: elapsedMs,
      screenWidth: screenSize.width,
      screenHeight: screenSize.height,
    );

    if (direction == null) {
      // Only log if there was meaningful drag (avoids noise from taps).
      if (dx.abs() > 5 || dy.abs() > 5) {
        final vel = elapsedMs > 0
            ? (dx.abs() / (elapsedMs / 1000)).toStringAsFixed(0)
            : '0';
        appLog(
          'gestures',
          'rejected: dx=${dx.toStringAsFixed(0)} dy=${dy.toStringAsFixed(0)} '
              'velocity=$vel elapsed=${elapsedMs}ms',
        );
      }
      return;
    }

    final vel = elapsedMs > 0
        ? (direction == SwipeDirection.up || direction == SwipeDirection.down
              ? dy.abs() / (elapsedMs / 1000)
              : dx.abs() / (elapsedMs / 1000))
        : 0.0;
    final dist =
        direction == SwipeDirection.up || direction == SwipeDirection.down
        ? dy.abs()
        : dx.abs();

    appLog(
      'gestures',
      'detected: ${direction.name} velocity=${vel.toStringAsFixed(0)} '
          'distance=${dist.toStringAsFixed(0)}',
    );

    switch (direction) {
      case SwipeDirection.up:
        _onSwipeUp();
      case SwipeDirection.down:
        _onSwipeDown();
      case SwipeDirection.left:
        _onSwipeLeft();
      case SwipeDirection.right:
        _onSwipeRight();
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.escape) {
      _goBack();
    } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
      _toggleFullScreen();
    } else if (_interlude != null) {
      // Space or Enter takes the moment's main action; nothing else moves
      // the reading position under it.
      if (event.logicalKey == LogicalKeyboardKey.space ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        _advanceInterlude();
      }
      // TASK-044 — ContextReveal keyboard shortcuts
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _onSwipeUp();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _onSwipeDown();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _onSwipeLeft();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _onSwipeRight();
    } else if (event.logicalKey == LogicalKeyboardKey.space) {
      _togglePause();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final timer = ref.read(wordTimerProvider.notifier);
      final currentWpm = ref.read(wordTimerProvider).wpm;
      // Scroll up = increase WPM, scroll down = decrease
      if (event.scrollDelta.dy < 0) {
        timer.setWpm((currentWpm + 10).clamp(30, 1000));
      } else if (event.scrollDelta.dy > 0) {
        timer.setWpm((currentWpm - 10).clamp(30, 1000));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Perf: progress is intentionally NOT watched here — it changes on every
    // word advance and would rebuild the whole screen at word frequency.
    // _ProgressRail watches it internally so only the rail rebuilds.
    final isPlaying = ref.watch(wordTimerProvider.select((s) => s.isPlaying));
    final wpm = ref.watch(wordTimerProvider.select((s) => s.wpm));
    // Select only the config fields used in build() to avoid
    // unnecessary rebuilds from bookmark auto-save every 5s.
    final config = ref.watch(
      configProvider.select((c) {
        final v = c.valueOrNull ?? const AppConfig();
        return (
          parallaxIntensity: v.parallaxIntensity,
          anchorColorIndex: v.anchorColorIndex,
          readingFontFamily: v.readingFontFamily,
          readingRulerEnabled: v.readingRulerEnabled,
          focusModeEnabled: v.focusModeEnabled,
          chapterMoments: v.chapterMoments,
          bookFontSize: v.bookFontSize,
          letterSpacing: v.letterSpacing,
          wordSpacing: v.wordSpacing,
        );
      }),
    );
    final readingMode = ref.watch(readingModeNotifierProvider);
    // Rebuild the header when the document's metadata title resolves.
    if (_isLocalFile) {
      _resolvedTitle =
          ref.watch(documentTitleProvider(widget.filePath)).valueOrNull ??
          _resolvedTitle;
    }
    ref.listen<ReadingMode>(readingModeNotifierProvider, (prev, next) {
      if (prev == next) return;
      unawaited(
        ref.read(configProvider.notifier).setLastReadingMode(next.name),
      );
      if (next == ReadingMode.book) {
        _bookEndTimer?.cancel();
        _cancelInterlude();
        ref.read(wordTimerProvider.notifier).pause();
        _snapToSentenceStartForBook();
      }
    });

    ref.listen<WordTimerState>(wordTimerProvider, (prev, next) {
      // Reading is the host; background extraction is a guest. No new
      // extraction chunk starts while words are flashing — the queue
      // scheduler pauses between chunks and resumes when reading stops.
      if (prev?.isPlaying != next.isPlaying) {
        if (next.isPlaying) {
          _queue.pauseBackground();
          _readingClock.start();
          _runClock.start();
          // Resuming rewinds a few words; never back into a heading.
          if (config.chapterMoments && _words.isNotEmpty) {
            final global = _sliceOffset + next.currentIndex;
            final start = playStartFor(_structure, global);
            if (start.from != global) {
              ref
                  .read(wordTimerProvider.notifier)
                  .seekTo(_localIndex(start.from));
              return;
            }
          }
        } else {
          _queue.resumeBackground();
          _readingClock.stop();
          _runClock.stop();
        }
      }
      if (prev?.currentIndex != next.currentIndex) {
        final idx = next.currentIndex;
        final global = _sliceOffset + idx;
        final previousGlobal = _previousGlobalIndex;
        _previousGlobalIndex = global;

        // Chapter boundaries: a chapter ending, a heading to announce.
        if (_words.isNotEmpty) {
          if (next.isPlaying && config.chapterMoments) {
            if (_handleChapterStep(previousGlobal, global)) return;
          } else {
            _trackRun(global);
          }
        }

        // Update word display.
        if (_words.isNotEmpty && idx < _words.length) {
          _wordNotifier.value = _words[idx];
          _wordAdvanceCount++;
          _sessionWordCount++;
          if (_wordAdvanceCount <= 5) {
            // Privacy: never log word text — reading content must not
            // appear in the in-app log viewer or DevTools output.
            appLog(
              'ParallaxReadingScreen',
              'word advance #$_wordAdvanceCount idx=$idx '
                  'len=${_words[idx].length}',
            );
          }

          // P27 — trigger onboarding hints at word milestones
          if (_wordAdvanceCount == 1) {
            _tryShowHint(HintId.tap);
          } else if (_wordAdvanceCount == 10) {
            _tryShowHint(HintId.swipeUp);
          }
        } else {
          appLog(
            'ParallaxReadingScreen',
            'WARN: idx=$idx _words.length=${_words.length}',
          );
        }

        // Save global word index (sliceOffset + slice-local index).
        // Rule 28 — clipboard sessions stay ephemeral, but Instapaper
        // articles persist locally so reopens resume from the last word
        // even before the API sync completes.
        if (!_isClipboard || _isInstapaper) {
          final globalIndex = _sliceOffset + idx;
          _lastTimerState = next;
          _lastGlobalIndex = globalIndex;
          ref
              .read(bookmarkProvider(widget.filePath).notifier)
              .updateIndex(globalIndex);
          _recordInstapaperProgress(next, globalIndex);
        }

        // Detect range completion.
        if (_readingRange != null && !_isRangeComplete && next.isFinished) {
          setState(() => _isRangeComplete = true);
          unawaited(_flushInstapaperProgress());
        }

        // Archive Instapaper bookmark when the full article is finished.
        if (next.isFinished && _isInstapaper) {
          unawaited(_flushInstapaperProgress());
          _archiveInstapaper();
          _markShelfFinished();
        } else if (next.isFinished && _readingRange == null) {
          // Local book read to the end — drop it from Continue Reading.
          _markShelfFinished();
        }

        // Read to the last word: let it stand a moment, then say so.
        if (next.isFinished &&
            (prev?.isPlaying ?? false) &&
            _interlude == null &&
            _finishScreenApplies) {
          _bookEndTimer?.cancel();
          _bookEndTimer = Timer(RunThruTiming.bookEndDwell, () {
            if (!mounted || _interlude != null) return;
            if (!ref.read(wordTimerProvider).isFinished) return;
            _showBookComplete();
          });
        }
      }
    });

    // A chapter moment is not a pause: no fog, no paused panel, and the
    // play button keeps showing "pause" while a title card is up.
    final interlude = _interlude;
    final inMoment = interlude != null;
    final cardUp =
        interlude is _TitleInterlude || interlude is _HeadingInterlude;
    final showPaused = !isPlaying && !inMoment && _words.isNotEmpty;

    final anchorColor =
        RunThruTokens.anchorColors[config.anchorColorIndex.clamp(
          0,
          RunThruTokens.anchorColors.length - 1,
        )];

    // P4 Grade C — flash anchor color on double-tap sentence restart
    final effectiveAnchorColor = _showRestartFlash
        ? RunThruTokens.stageText
        : anchorColor;

    // P20 — watch ContextReveal state for overlay rendering
    final crState = ref.watch(contextRevealProvider);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Reading screen',
      child: Material(
        color: RunThruTokens.roomBackground,
        textStyle: const TextStyle(decoration: TextDecoration.none),
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            _goBack();
          },
          child: KeyboardListener(
            focusNode: _focusNode,
            autofocus: true,
            onKeyEvent: _handleKeyEvent,
            child: Listener(
              onPointerSignal: _handlePointerSignal,
              child: ColoredBox(
                color: RunThruTokens.roomBackground,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // A11y: honor the system text-size setting on the stage.
                    // The scale is clamped so a 30-character word still fits
                    // the viewport; the word is already viewport-proportional.
                    final textScale = MediaQuery.textScalerOf(
                      context,
                    ).scale(1.0).clamp(1.0, 1.3).toDouble();
                    final fontSize = (dynamicFontSize(constraints) * textScale)
                        .clamp(16.0, 400.0)
                        .toDouble();

                    return Listener(
                      // Passive pointer tracking — doesn't compete in the
                      // gesture arena, so onLongPress can still fire.
                      onPointerDown: (e) {
                        _panStart = e.position;
                        _panStartTime = DateTime.now();
                      },
                      onPointerMove: (e) => _panLast = e.position,
                      onPointerUp: _handlePointerUp,
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              // Book pages handle their own taps; an outer
                              // double-tap would delay every page turn.
                              // A chapter moment handles its own taps;
                              // a double-tap recogniser here would delay
                              // them.
                              onTap: readingMode == ReadingMode.book || inMoment
                                  ? null
                                  : _togglePause,
                              onDoubleTap:
                                  readingMode == ReadingMode.book || inMoment
                                  ? null
                                  : _handleDoubleTap,
                              child: ValueListenableBuilder<String>(
                                valueListenable: _wordNotifier,
                                builder: (context, currentWord, _) {
                                  // P7 Grade C — shared overlay stack for all intensity modes
                                  final overlayStack = Stack(
                                    children: [
                                      // Live region announcing the current RSVP
                                      // word to assistive technology. Invisible;
                                      // shared by the flat-2D and 3D word paths.
                                      if (currentWord.isNotEmpty &&
                                          !crState.isActive &&
                                          readingMode == ReadingMode.singleWord)
                                        Positioned(
                                          left: 0,
                                          top: 0,
                                          child: IgnorePointer(
                                            child: Semantics(
                                              liveRegion: true,
                                              container: true,
                                              label: currentWord,
                                              child: const SizedBox(
                                                width: 1,
                                                height: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (currentWord.isNotEmpty &&
                                          !crState.isActive &&
                                          readingMode ==
                                              ReadingMode.singleWord &&
                                          config.parallaxIntensity !=
                                              ParallaxIntensity.none)
                                        IgnorePointer(
                                          child: Align(
                                            alignment: Alignment.center,
                                            child: _FocalTourTarget(
                                              key: _stageKey,
                                              word: currentWord,
                                              fontSize: fontSize,
                                              fontFamily:
                                                  config.readingFontFamily,
                                            ),
                                          ),
                                        ),
                                      // The continuous-text modes draw their
                                      // own reading-band ruler; the flanking
                                      // hairlines are single-word only.
                                      if (config.readingRulerEnabled &&
                                          readingMode == ReadingMode.singleWord)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: ReadingRuler(
                                              visible: true,
                                              viewportHeight: MediaQuery.sizeOf(
                                                context,
                                              ).height,
                                            ),
                                          ),
                                        ),
                                      if (!crState.isActive &&
                                          readingMode != ReadingMode.singleWord)
                                        Positioned.fill(
                                          // Perf: the word index changes every
                                          // advance — scope its watch to this
                                          // Consumer so only the mode view
                                          // rebuilds, not the whole screen.
                                          child: Consumer(
                                            builder: (context, modeRef, _) {
                                              final currentIndex = modeRef
                                                  .watch(
                                                    wordTimerProvider.select(
                                                      (s) => s.currentIndex,
                                                    ),
                                                  );
                                              return AnimatedSwitcher(
                                                duration:
                                                    isReducedMotion(context)
                                                    ? Duration.zero
                                                    : const Duration(
                                                        milliseconds: 240,
                                                      ),
                                                child: switch (readingMode) {
                                                  ReadingMode.singleWord =>
                                                    const SizedBox.shrink(),
                                                  ReadingMode.sentence =>
                                                    SentenceModeView(
                                                      key: const ValueKey(
                                                        'sentence',
                                                      ),
                                                      anchorColor: anchorColor,
                                                      words: _words,
                                                      currentIndex:
                                                          currentIndex,
                                                      letterSpacing:
                                                          config.letterSpacing,
                                                      wordSpacing:
                                                          config.wordSpacing,
                                                      fontFamily: config
                                                          .readingFontFamily,
                                                      fontSize: fontSize,
                                                      wpm: wpm,
                                                    ),
                                                  ReadingMode.paragraph =>
                                                    ParagraphModeView(
                                                      key: const ValueKey(
                                                        'paragraph',
                                                      ),
                                                      anchorColor: anchorColor,
                                                      paragraphStarts:
                                                          _paragraphStarts,
                                                      wordOffset: _sliceOffset,
                                                      words: _words,
                                                      currentIndex:
                                                          currentIndex,
                                                      letterSpacing:
                                                          config.letterSpacing,
                                                      wordSpacing:
                                                          config.wordSpacing,
                                                      fontFamily: config
                                                          .readingFontFamily,
                                                      fontSize: fontSize,
                                                      wpm: wpm,
                                                    ),
                                                  ReadingMode.book => BookModeView(
                                                    key: _bookKey,
                                                    words: _words,
                                                    startIndex: currentIndex,
                                                    onTurn: _onBookTurn,
                                                    fontFamily: config
                                                        .readingFontFamily,
                                                    fontSize:
                                                        config.bookFontSize,
                                                    letterSpacing:
                                                        config.letterSpacing,
                                                    wordSpacing:
                                                        config.wordSpacing,
                                                    wpm: wpm,
                                                    onFontSizeChanged: (size) =>
                                                        ref
                                                            .read(
                                                              configProvider
                                                                  .notifier,
                                                            )
                                                            .setBookFontSize(
                                                              size,
                                                            ),
                                                    paragraphStarts:
                                                        _bookParagraphStarts,
                                                    chapterStarts:
                                                        _chapterStarts,
                                                    headingStarts:
                                                        _headingStarts,
                                                    structure: _structure,
                                                    onEnd: _onBookEnd,
                                                    wordOffset: _sliceOffset,
                                                    totalWords:
                                                        _allDocWords.length,
                                                    topInset:
                                                        MediaQuery.paddingOf(
                                                          context,
                                                        ).top +
                                                        (config.focusModeEnabled
                                                            ? 56
                                                            : _kReaderHeaderRowExtent),
                                                    bottomInset:
                                                        MediaQuery.paddingOf(
                                                          context,
                                                        ).bottom,
                                                  ),
                                                  ReadingMode.fullPage =>
                                                    FullPageModeView(
                                                      key: const ValueKey(
                                                        'fullPage',
                                                      ),
                                                      anchorColor: anchorColor,
                                                      paragraphStarts:
                                                          _paragraphStarts,
                                                      wordOffset: _sliceOffset,
                                                      words: _words,
                                                      currentIndex:
                                                          currentIndex,
                                                      letterSpacing:
                                                          config.letterSpacing,
                                                      wordSpacing:
                                                          config.wordSpacing,
                                                      fontFamily: config
                                                          .readingFontFamily,
                                                      fontSize: fontSize,
                                                      wpm: wpm,
                                                    ),
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                      // The header and action tray have no
                                      // background, so continuous text would
                                      // scroll straight under the buttons.
                                      // Fade it into the stage behind them.
                                      if (!crState.isActive &&
                                          readingMode !=
                                              ReadingMode.singleWord &&
                                          readingMode != ReadingMode.book)
                                        Positioned.fill(
                                          child: _ChromeFade(
                                            top:
                                                MediaQuery.paddingOf(
                                                  context,
                                                ).top +
                                                (config.focusModeEnabled
                                                    ? 0
                                                    : _kReaderHeaderExtent),
                                            bottom:
                                                MediaQuery.paddingOf(
                                                  context,
                                                ).bottom +
                                                (config.focusModeEnabled
                                                    ? 0
                                                    : _kReaderTrayExtent),
                                          ),
                                        ),
                                      // Mounted in focus mode too — the pause
                                      // overlay is the only way back out of
                                      // focus mode (its toggle must appear).
                                      if (!crState.isActive &&
                                          readingMode != ReadingMode.book)
                                        Positioned.fill(
                                          child: PauseFog3D(
                                            isPaused: showPaused,
                                            wpm: wpm,
                                            // The text modes keep their
                                            // passage readable when paused.
                                            strength:
                                                readingMode ==
                                                    ReadingMode.singleWord
                                                ? 1.0
                                                : 0.22,
                                            focusModeEnabled:
                                                config.focusModeEnabled,
                                            // Landscape is too short for the
                                            // toggle, the paused sentence and
                                            // the tray together; Focus Mode
                                            // stays in Settings there.
                                            onFocusModeChanged:
                                                _landscapeChrome(context)
                                                ? null
                                                : _setFocusModeEnabled,
                                            externalPosition:
                                                _motionCtrl.positionNotifier,
                                            onRecalibrate:
                                                _motionCtrl.recalibrate,
                                          ),
                                        ),
                                      if (isPlaying &&
                                          !config.focusModeEnabled &&
                                          !crState.isActive &&
                                          readingMode ==
                                              ReadingMode.singleWord &&
                                          _words.isNotEmpty)
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom:
                                              MediaQuery.paddingOf(
                                                context,
                                              ).bottom +
                                              26,
                                          child: const Center(
                                            child: _TapToPausePrompt(),
                                          ),
                                        ),
                                      if (_isRangeComplete &&
                                          _readingRange != null)
                                        Positioned.fill(
                                          child: FinishedRangeOverlay(
                                            visible: _isRangeComplete,
                                            startPage: _readingRange!.startPage,
                                            endPage: _readingRange!.endPage,
                                            wordCount: _words.length,
                                            averageWpm: wpm,
                                            onContinueReading:
                                                _continueReadingPastRange,
                                            onSetNewRange: () {
                                              unawaited(
                                                ref
                                                    .read(
                                                      bookmarkProvider(
                                                        widget.filePath,
                                                      ).notifier,
                                                    )
                                                    .save(),
                                              );
                                              unawaited(
                                                _flushInstapaperProgress(),
                                              );
                                              context.push(
                                                Uri(
                                                  path: '/range-picker',
                                                  queryParameters: {
                                                    'path': widget.filePath,
                                                  },
                                                ).toString(),
                                              );
                                            },
                                            onGoToLibrary: () {
                                              unawaited(
                                                ref
                                                    .read(
                                                      bookmarkProvider(
                                                        widget.filePath,
                                                      ).notifier,
                                                    )
                                                    .save(),
                                              );
                                              unawaited(
                                                _flushInstapaperProgress(),
                                              );
                                              ref
                                                  .read(
                                                    wordTimerProvider.notifier,
                                                  )
                                                  .pause();
                                              context.go('/');
                                            },
                                          ),
                                        ),
                                      // ── ContextReveal Overlay ──
                                      // IgnorePointer so the back button passes
                                      // through — all gestures are handled by the
                                      // parent Listener/GestureDetector.
                                      if (crState.isActive)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: Semantics(
                                              liveRegion: true,
                                              label:
                                                  'Context reveal: ${crState.tier.name} view. '
                                                  '${_contextRevealWords().join(' ')}. '
                                                  'Swipe down to resume reading.',
                                              child: ContextRevealOverlay(
                                                tier: crState.tier,
                                                words: _contextRevealWords(),
                                                sweepPosition:
                                                    crState.sweepPosition,
                                                fontSize: fontSize,
                                                fontFamily:
                                                    config.readingFontFamily,
                                                isJiggling: crState.isJiggling,
                                                isSweepPaused:
                                                    crState.isSweepPaused,
                                                backgroundColor:
                                                    config.parallaxIntensity ==
                                                        ParallaxIntensity.none
                                                    ? RunThruTokens.stageBase
                                                    : RunThruTokens
                                                          .cubeBackWall,
                                                backgroundOpacity:
                                                    config.parallaxIntensity ==
                                                        ParallaxIntensity.none
                                                    ? 1.0
                                                    : 0.88,
                                                onJiggleComplete: () => ref
                                                    .read(
                                                      contextRevealProvider
                                                          .notifier,
                                                    )
                                                    .clearJiggle(),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // PauseFog3D in sentence mode — rendered after CR
                                      // overlay so it's visible on top when sweep is paused.
                                      if (crState.isActive &&
                                          crState.isSweepPaused &&
                                          config.parallaxIntensity !=
                                              ParallaxIntensity.none)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: PauseFog3D(
                                              isPaused: crState.isSweepPaused,
                                              wpm: wpm,
                                              externalPosition:
                                                  _motionCtrl.positionNotifier,
                                              onRecalibrate:
                                                  _motionCtrl.recalibrate,
                                            ),
                                          ),
                                        ),
                                      // Simple dimming for 2D sentence-mode pause
                                      if (crState.isActive &&
                                          crState.isSweepPaused &&
                                          config.parallaxIntensity ==
                                              ParallaxIntensity.none)
                                        const Positioned.fill(
                                          child: IgnorePointer(
                                            child: ColoredBox(
                                              color: RunThruTokens
                                                  .stagePauseOverlay,
                                            ),
                                          ),
                                        ),
                                      // ── Chapter title card ──
                                      if (interlude is _TitleInterlude)
                                        Positioned.fill(
                                          child: ChapterTitleCard(
                                            key: ValueKey(
                                              'title-card-${interlude.resumeAt}',
                                            ),
                                            announcement:
                                                interlude.announcement,
                                            insets: EdgeInsets.only(
                                              top:
                                                  MediaQuery.paddingOf(
                                                    context,
                                                  ).top +
                                                  (config.focusModeEnabled
                                                      ? 56
                                                      : _kReaderHeaderExtent),
                                              bottom:
                                                  MediaQuery.paddingOf(
                                                    context,
                                                  ).bottom +
                                                  (config.focusModeEnabled
                                                      ? 0
                                                      : _kReaderTrayExtent),
                                            ),
                                            onDone: () => _endInterludeAndRead(
                                              interlude.resumeAt,
                                            ),
                                            onReadFromStart:
                                                interlude
                                                        .announcement
                                                        .skippedNote ==
                                                    null
                                                ? null
                                                : _restartFromBeginning,
                                          ),
                                        ),
                                      if (interlude is _HeadingInterlude)
                                        Positioned.fill(
                                          child: SubHeadingCard(
                                            key: ValueKey(
                                              'heading-card-${interlude.resumeAt}',
                                            ),
                                            text: interlude.text,
                                            fontFamily:
                                                config.readingFontFamily,
                                            onDone: () => _endInterludeAndRead(
                                              interlude.resumeAt,
                                            ),
                                          ),
                                        ),
                                      // ── ContextReveal Onboarding (shown once) ──
                                      if (_showCROnboarding)
                                        Positioned.fill(
                                          child: GestureDetector(
                                            onTap: _dismissCROnboarding,
                                            child: ColoredBox(
                                              color: RunThruTokens
                                                  .stagePauseOverlay
                                                  .withAlpha(230),
                                              child: Center(
                                                child: Semantics(
                                                  liveRegion: true,
                                                  child: Padding(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 32,
                                                        ),
                                                    child: Text(
                                                      // v4 copy — 2-state model:
                                                      // none ↔ sentence only.
                                                      'Swipe up to see the full sentence.\n'
                                                      'Swipe left or right to move between sentences.\n'
                                                      'Swipe down to resume.',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: RunThruTypography
                                                          .body
                                                          .copyWith(
                                                            color: RunThruTokens
                                                                .stageText,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      // ── Onboarding Hint Overlay (Rule 27) ──
                                      if (_activeHint != null)
                                        HintOverlay(
                                          text: _activeHint!.message,
                                          position: _activeHint!.position,
                                          slideFrom: _activeHint!.slideFrom,
                                          onDismiss: _dismissActiveHint,
                                        ),
                                    ],
                                  );

                                  // P7 Grade C — "None" renders flat 2D, no 3D room geometry
                                  if (config.parallaxIntensity ==
                                      ParallaxIntensity.none) {
                                    return Stack(
                                      children: [
                                        // Flat stage background
                                        Positioned.fill(
                                          child: Container(
                                            decoration:
                                                RunThruDecorations.insetDecoration(
                                                  RunThruSurface.stage,
                                                  borderRadius: 0,
                                                ),
                                          ),
                                        ),
                                        // ORP focal word (hidden during ContextReveal)
                                        // In landscape the header and tray
                                        // take most of the height, so the
                                        // word centres in the space between
                                        // them instead of touching the play
                                        // button.
                                        if (currentWord.isNotEmpty &&
                                            !crState.isActive &&
                                            readingMode ==
                                                ReadingMode.singleWord)
                                          Positioned(
                                            left: 0,
                                            right: 0,
                                            top: _landscapeChrome(context)
                                                ? MediaQuery.paddingOf(
                                                        context,
                                                      ).top +
                                                      _kReaderHeaderExtent
                                                : 0,
                                            bottom: _landscapeChrome(context)
                                                ? MediaQuery.paddingOf(
                                                        context,
                                                      ).bottom +
                                                      _kReaderTrayExtent
                                                : 0,
                                            child: _OrpFocalWord(
                                              focalTargetKey: _stageKey,
                                              word: currentWord,
                                              fontSize: fontSize,
                                              fontFamily:
                                                  config.readingFontFamily,
                                              isPaused: showPaused,
                                              dimWhenPaused: true,
                                              anchorColor: anchorColor,
                                            ),
                                          ),
                                        // Pause veil is now handled by PauseFog3D
                                        // inside overlayStack (rising lavender blind).
                                        // Shared overlays
                                        Positioned.fill(child: overlayStack),
                                      ],
                                    );
                                  }

                                  return ValueListenableBuilder<Offset>(
                                    valueListenable:
                                        _motionCtrl.positionNotifier,
                                    builder: (context, headPos, _) =>
                                        ParallaxRoom(
                                          headX: headPos.dx,
                                          headY: headPos.dy,
                                          // Hide RSVP word during ContextReveal
                                          currentWord:
                                              crState.isActive ||
                                                  readingMode !=
                                                      ReadingMode.singleWord
                                              ? ''
                                              : currentWord,
                                          fontSize: fontSize,
                                          anchorColor: effectiveAnchorColor,
                                          isPlaying: isPlaying,
                                          fontFamily: config.readingFontFamily,
                                          wpm: wpm,
                                          intervalMs: (60000 / wpm).round(),
                                          parallaxIntensity:
                                              config.parallaxIntensity,
                                          child: overlayStack,
                                        ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // While playing, focus mode swallows everything but
                          // tap-to-pause. Once paused, taps fall through so
                          // the pause overlay's Focus Mode toggle stays
                          // reachable (otherwise focus mode is inescapable).
                          if (config.focusModeEnabled && isPlaying)
                            Positioned.fill(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: _togglePause,
                              ),
                            ),
                          // Focus mode: minimal back arrow (always a11y visible)
                          if (config.focusModeEnabled)
                            Positioned(
                              top: MediaQuery.paddingOf(context).top + 8,
                              left: 8,
                              child: Semantics(
                                button: true,
                                label: 'Back: library',
                                onTap: _goBack,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _goBack,
                                  excludeFromSemantics: true,
                                  child: const SizedBox(
                                    width: RunThruA11y.minTapTarget,
                                    height: RunThruA11y.minTapTarget,
                                    child: Center(
                                      child: ExcludeSemantics(
                                        child: Icon(
                                          Icons.arrow_back,
                                          color: RunThruTokens.stageText,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          // Non-focus: header row + progress rail + context
                          // sentence + persistent action tray
                          if (!config.focusModeEnabled) ...[
                            // Header + progress rail
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {},
                                child: SafeArea(
                                  bottom: false,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          4,
                                          8,
                                          0,
                                        ),
                                        // Rebuilds when the chapter changes,
                                        // not on every word.
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: _sectionIndex,
                                          builder: (context, sectionIndex, _) {
                                            final sections =
                                                _structure.sections;
                                            final section =
                                                sectionIndex < sections.length
                                                ? sections[sectionIndex]
                                                : null;
                                            final chapter =
                                                section != null &&
                                                    section.isTitled &&
                                                    _hasContents
                                                ? section.displayName()
                                                : '';
                                            return _ReaderHeaderRow(
                                              onBack: _goBack,
                                              title: _documentTitle,
                                              subtitle: chapter.isNotEmpty
                                                  ? chapter
                                                  : _documentSubtitle,
                                              onContents: _hasContents
                                                  ? _openContents
                                                  : null,
                                              onFont: () => context.push(
                                                '/reader-settings',
                                              ),
                                              onFullScreen: _isDesktop
                                                  ? _toggleFullScreen
                                                  : null,
                                              isFullScreen: _isFullScreen,
                                            );
                                          },
                                        ),
                                      ),
                                      // Book mode shows one progress figure,
                                      // in its page footer.
                                      if (readingMode != ReadingMode.book)
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                            20,
                                            6,
                                            20,
                                            8,
                                          ),
                                          child: _ProgressRail(
                                            wpm: wpm,
                                            structure: _wholeDocument
                                                ? _structure
                                                : null,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Sentence below the word (paused + singleWord
                            // mode) — design reader.jsx: the current sentence
                            // sits at the bottom of the word stage with the
                            // live word inked.
                            if (showPaused &&
                                !crState.isActive &&
                                readingMode == ReadingMode.singleWord)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom:
                                    MediaQuery.paddingOf(context).bottom +
                                    (_landscapeChrome(context)
                                        ? _kReaderTrayExtent + 4
                                        : 196),
                                child: IgnorePointer(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 30,
                                    ),
                                    // Perf: the parent no longer rebuilds on
                                    // word-index changes, so the paused panel
                                    // watches the index itself (only mounted
                                    // while paused — no per-word cost during
                                    // playback).
                                    child: Consumer(
                                      builder: (context, panelRef, _) {
                                        panelRef.watch(
                                          wordTimerProvider.select(
                                            (s) => s.currentIndex,
                                          ),
                                        );
                                        final globalIdx = _currentGlobalIndex;
                                        final start = _sentenceStartAt(
                                          globalIdx,
                                        );
                                        return _ContextSentencePanel(
                                          words: _sentenceWordsAt(globalIdx),
                                          highlightIndex: globalIdx - start,
                                          fontFamily: config.readingFontFamily,
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            // Persistent action tray (hidden in Book mode,
                            // which has its own page footer).
                            if (readingMode != ReadingMode.book)
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {},
                                  child: SafeArea(
                                    top: false,
                                    child: _PersistentActionTray(
                                      isPlaying: isPlaying || cardUp,
                                      wpm: wpm,
                                      onPlayPause: _togglePause,
                                      onPrevSentence: _seekToPreviousSentence,
                                      onNextSentence: _seekToNextSentence,
                                      onWpmSelected: _selectPausedWpm,
                                      playButtonKey: _playButtonKey,
                                      prevButtonKey: _prevButtonKey,
                                      speedSelectorKey: _speedSelectorKey,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                          // ── Chapter complete / book complete ──
                          // Over the stage and the tray; the header row
                          // (Back, modes) stays reachable above it.
                          if (interlude is _CompleteInterlude)
                            Positioned(
                              top:
                                  MediaQuery.paddingOf(context).top +
                                  (config.focusModeEnabled
                                      ? 56
                                      : readingMode == ReadingMode.book
                                      ? _kReaderHeaderRowExtent
                                      : _kReaderHeaderExtent),
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: SectionCompleteOverlay(
                                key: ValueKey(
                                  'chapter-complete-${interlude.next.start}',
                                ),
                                completion: interlude.completion,
                                autoContinue: readingMode != ReadingMode.book,
                                onContinue: () =>
                                    _continueToSection(interlude.next),
                                onBreak: readingMode == ReadingMode.book
                                    ? null
                                    : () => _breakAtSection(interlude.next),
                              ),
                            ),
                          if (interlude is _BookInterlude)
                            Positioned(
                              top:
                                  MediaQuery.paddingOf(context).top +
                                  (config.focusModeEnabled
                                      ? 56
                                      : readingMode == ReadingMode.book
                                      ? _kReaderHeaderRowExtent
                                      : _kReaderHeaderExtent),
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: BookCompleteOverlay(
                                key: const ValueKey('book-complete'),
                                completion: interlude.completion,
                                onLibrary: _goBack,
                                onReadAgain: _readAgain,
                                onKeepReading: interlude.backMatter == null
                                    ? null
                                    : () => _keepReadingBackMatter(
                                        interlude.backMatter!,
                                      ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Chapter moments ───────────────────────────────────────────────────────────

/// A chapter moment the reader is in. The timer is paused for its length.
sealed class _Interlude {
  const _Interlude();
}

/// A chapter title card; reading resumes at [resumeAt] (document index).
class _TitleInterlude extends _Interlude {
  const _TitleInterlude(this.announcement, {required this.resumeAt});

  final ChapterAnnouncement announcement;
  final int resumeAt;
}

/// A heading shown whole (a sub-heading, or a front/back matter title).
class _HeadingInterlude extends _Interlude {
  const _HeadingInterlude(this.text, {required this.resumeAt});

  final String text;
  final int resumeAt;
}

/// A chapter was finished; [next] is announced when the reader goes on.
class _CompleteInterlude extends _Interlude {
  const _CompleteInterlude(this.completion, {required this.next});

  final SectionCompletion completion;
  final BookSection next;
}

/// The book's text was finished. [backMatter] is what follows, if anything.
class _BookInterlude extends _Interlude {
  const _BookInterlude(this.completion, {this.backMatter});

  final BookCompletion completion;
  final BookSection? backMatter;
}

// ── Reader chrome ─────────────────────────────────────────────────────────────

/// Height of the header row + progress rail below the top safe area.
const double _kReaderHeaderExtent = 104;

/// Sentences per fallback paragraph in Book mode (documents without
/// paragraph data).
const int _kFallbackSentencesPerParagraph = 4;

/// Height of the header row alone (Book mode hides the progress rail).
const double _kReaderHeaderRowExtent = 72;

/// Height of the persistent action tray above the bottom safe area.
const double _kReaderTrayExtent = 172;

/// Distance over which continuous text fades out before reaching the chrome.
const double _kChromeFeather = 36;

/// Opaque stage colour behind the reader chrome, fading to clear over
/// [_kChromeFeather], so Sentence, Paragraph and Full Page text never runs
/// under the header or the play/speed tray. Two flat gradients, no layer.
class _ChromeFade extends StatelessWidget {
  const _ChromeFade({required this.top, required this.bottom});

  final double top;
  final double bottom;

  @override
  Widget build(BuildContext context) {
    const solid = RunThruTokens.stageBase;
    final clear = RunThruTokens.stageBase.withValues(alpha: 0);
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + _kChromeFeather,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [solid, solid, clear],
                  stops: [0, top / (top + _kChromeFeather), 1],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: bottom + _kChromeFeather,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [solid, solid, clear],
                  stops: [0, bottom / (bottom + _kChromeFeather), 1],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReaderHeaderRow extends StatelessWidget {
  const _ReaderHeaderRow({
    required this.onBack,
    required this.title,
    this.subtitle,
    this.onContents,
    this.onFont,
    this.onFullScreen,
    this.isFullScreen = false,
  });

  final VoidCallback onBack;
  final String title;
  final String? subtitle;

  /// Opens the contents list. When set, the title block is a button.
  final VoidCallback? onContents;
  final VoidCallback? onFont;
  final VoidCallback? onFullScreen;
  final bool isFullScreen;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeadBtn(
          onTap: onBack,
          semanticLabel: 'Back: library',
          child: const Icon(
            Icons.chevron_left_rounded,
            color: RunThruTokens.stageText,
            size: 22,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _HeaderTitle(
            title: title,
            subtitle: subtitle,
            onContents: onContents,
          ),
        ),
        const SizedBox(width: 8),
        if (onFont != null) ...[
          _HeadBtn(
            onTap: onFont!,
            semanticLabel: 'Open: reading settings',
            child: Text(
              'Aa',
              style: RunThruTypography.caption.copyWith(
                color: RunThruTokens.stageText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        if (onFullScreen != null) ...[
          _HeadBtn(
            onTap: onFullScreen!,
            semanticLabel: isFullScreen
                ? 'Exit: full screen'
                : 'Enter: full screen',
            child: Icon(
              isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: RunThruTokens.stageText,
              size: 20,
            ),
          ),
          const SizedBox(width: 6),
        ],
        const ModeSwitcher(),
      ],
    );
  }
}

/// The book's title with the current chapter beneath it. With
/// [onContents] the block is one button that opens the contents list.
class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.title, this.subtitle, this.onContents});

  final String title;
  final String? subtitle;
  final VoidCallback? onContents;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle ?? '';
    final onContents = this.onContents;
    final faint = RunThruTokens.stageText.withValues(alpha: 0.62);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: RunThruTypography.rowTitle.copyWith(
            color: RunThruTokens.stageText,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          textAlign: TextAlign.center,
        ),
        if (subtitle.isNotEmpty || onContents != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  subtitle.isNotEmpty ? subtitle : 'Contents',
                  style: RunThruTypography.tinyLabel.copyWith(
                    color: onContents == null
                        ? faint
                        : RunThruTokens.shellTealDeep,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  textScaler: TextScaler.noScaling,
                ),
              ),
              if (onContents != null)
                const Icon(
                  Icons.expand_more_rounded,
                  size: 14,
                  color: RunThruTokens.shellTealDeep,
                ),
            ],
          ),
      ],
    );
    if (onContents == null) return column;
    return Semantics(
      button: true,
      label: subtitle.isNotEmpty
          ? 'Contents: $title, $subtitle'
          : 'Contents: $title',
      onTap: onContents,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onContents,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: RunThruA11y.minTapTarget,
          ),
          child: Center(child: ExcludeSemantics(child: column)),
        ),
      ),
    );
  }
}

class _HeadBtn extends StatelessWidget {
  const _HeadBtn({
    required this.onTap,
    required this.semanticLabel,
    required this.child,
  });

  final VoidCallback onTap;

  /// Accessibility label in '[Action]: [Subject]' format.
  final String semanticLabel;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 38dp visual circle inside a 48dp hit area (RunThruA11y.minTapTarget)
    // so the compact stage chrome still meets Android tap-target guidance.
    return Semantics(
      button: true,
      label: semanticLabel,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The labeled Semantics above is the single tappable node for AT;
        // without this the detector adds a second, unlabeled tap node.
        excludeFromSemantics: true,
        child: SizedBox(
          width: RunThruA11y.minTapTarget,
          height: RunThruA11y.minTapTarget,
          child: Center(
            child: DecoratedBox(
              decoration: RunThruDecorations.raisedDecoration(
                RunThruSurface.stage,
                size: RunThruShadowSize.small,
                borderRadius: 999,
              ),
              child: SizedBox(
                width: 38,
                height: 38,
                child: Center(child: ExcludeSemantics(child: child)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressRail extends ConsumerWidget {
  const _ProgressRail({required this.wpm, this.structure});

  final int wpm;

  /// The book's sections, when the whole document is loaded: the rail then
  /// marks where chapters begin and says how much of the chapter is left.
  final BookStructure? structure;

  int _minutes(int words) => wpm <= 0 || words <= 0 ? 0 : (words / wpm).ceil();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Perf: progress changes every word advance — watching it here keeps the
    // per-word rebuild scoped to this small rail instead of the full screen.
    final (index, totalWords) = ref.watch(
      wordTimerProvider.select((s) => (s.currentIndex, s.totalWords)),
    );
    final progress = totalWords > 0 ? index / totalWords : 0.0;
    final remainingWords = (totalWords - index).clamp(0, totalWords);
    final pct = (progress * 100).round().clamp(0, 100);
    final bookLeft = remainingWords <= 0
        ? ''
        : formatTimeLeft(_minutes(remainingWords));

    // With chapters: "8 min left in chapter" is the nearer goal.
    final structure = this.structure;
    final chaptered =
        structure != null &&
        structure.hasChapters &&
        structure.totalWords == totalWords;
    var chapterLeft = '';
    if (chaptered) {
      final section = structure.sectionAt(index);
      if (section.kind == SectionKind.body && section.end > index) {
        chapterLeft =
            '${formatMinutes(_minutes(section.end - index))} left in chapter';
      }
    }
    final faint = RunThruTypography.tinyLabel.copyWith(
      color: RunThruTokens.stageText.withValues(alpha: 0.54),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Neumorphic inset rail with teal fill
        SizedBox(
          height: 5,
          child: DecoratedBox(
            decoration: RunThruDecorations.insetDecoration(
              RunThruSurface.stage,
              size: RunThruShadowSize.small,
              borderRadius: 999,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    // heightFactor: without it the fill has no height of
                    // its own and the rail always looks empty.
                    child: FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      heightFactor: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              RunThruTokens.shellTeal,
                              RunThruTokens.shellTealDeep,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  // Where chapters begin. Repaints only when the book does.
                  if (chaptered)
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _ChapterMarksPainter(structure),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Text(
              '$pct%',
              style: RunThruTypography.tinyLabel.copyWith(
                color: RunThruTokens.shellTealDeep,
                fontWeight: FontWeight.w800,
              ),
              textScaler: TextScaler.noScaling,
            ),
            if (chapterLeft.isNotEmpty)
              Text(
                '  ·  $wpm WPM',
                style: faint,
                textScaler: TextScaler.noScaling,
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                chapterLeft.isNotEmpty
                    ? [
                        chapterLeft,
                        if (bookLeft.isNotEmpty) bookLeft,
                      ].join('  ·  ')
                    : bookLeft.isNotEmpty
                    ? '$bookLeft · $wpm WPM'
                    : '$wpm WPM',
                style: faint,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                textScaler: TextScaler.noScaling,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Small notches on the progress rail where the book's chapters begin.
class _ChapterMarksPainter extends CustomPainter {
  const _ChapterMarksPainter(this.structure);

  final BookStructure structure;

  /// Past this many chapters the notches would be a solid band.
  static const int _maxMarks = 60;

  @override
  void paint(Canvas canvas, Size size) {
    final chapters = structure.chapters;
    final total = structure.totalWords;
    if (total <= 0 || chapters.length < 2 || chapters.length > _maxMarks) {
      return;
    }
    // A light notch reads on the filled rail, a dark one on the empty
    // rail: drawn side by side, one of them always shows.
    final light = Paint()
      ..color = RunThruTokens.stageBase
      ..strokeWidth = 1.5;
    final dark = Paint()
      ..color = RunThruTokens.stageText.withValues(alpha: 0.26)
      ..strokeWidth = 1;
    void mark(int word) {
      final x = size.width * word / total;
      canvas
        ..drawLine(Offset(x, 0), Offset(x, size.height), light)
        ..drawLine(Offset(x + 1.25, 0), Offset(x + 1.25, size.height), dark);
    }

    for (final chapter in chapters) {
      if (chapter.start > 0) mark(chapter.start);
    }
    // The end of the book's text, when back matter follows.
    if (structure.bodyEnd < total) mark(structure.bodyEnd);
  }

  @override
  bool shouldRepaint(_ChapterMarksPainter oldDelegate) =>
      !identical(oldDelegate.structure, structure);
}

class _ContextSentencePanel extends StatelessWidget {
  const _ContextSentencePanel({
    required this.words,
    required this.highlightIndex,
    required this.fontFamily,
  });

  final List<String> words;
  final int highlightIndex;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    if (words.isEmpty) return const SizedBox.shrink();
    final faint = RunThruTypography.body.copyWith(
      color: RunThruTokens.stageText.withValues(alpha: 0.45),
      fontFamily: fontFamily,
      fontSize: 15,
      fontWeight: FontWeight.w500,
      height: 1.7,
    );
    final inked = faint.copyWith(
      color: RunThruTokens.stageText,
      fontWeight: FontWeight.w700,
    );
    // The panel holds four lines. In a long sentence the current word could
    // fall past line four and be faded out, so show a window around it.
    final window = sentenceWindowAround(words, highlightIndex);
    final shown = window.words;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340),
        child: Semantics(
          label: words.join(' '),
          child: ExcludeSemantics(
            child: RichText(
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.fade,
              textScaler: TextScaler.noScaling,
              text: TextSpan(
                children: [
                  if (window.clippedStart) TextSpan(text: '… ', style: faint),
                  for (var i = 0; i < shown.length; i++)
                    TextSpan(
                      text: i == shown.length - 1 ? shown[i] : '${shown[i]} ',
                      style: i == window.highlight ? inked : faint,
                    ),
                  if (window.clippedEnd) TextSpan(text: ' …', style: faint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Persistent action tray ────────────────────────────────────────────────────

class _PersistentActionTray extends StatelessWidget {
  const _PersistentActionTray({
    required this.isPlaying,
    required this.wpm,
    required this.onPlayPause,
    required this.onPrevSentence,
    required this.onNextSentence,
    required this.onWpmSelected,
    this.playButtonKey,
    this.prevButtonKey,
    this.speedSelectorKey,
  });

  final bool isPlaying;
  final int wpm;
  final VoidCallback onPlayPause;
  final VoidCallback onPrevSentence;
  final VoidCallback onNextSentence;
  final ValueChanged<int> onWpmSelected;
  final GlobalKey? playButtonKey;
  final GlobalKey? prevButtonKey;
  final GlobalKey? speedSelectorKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                key: prevButtonKey,
                child: _RoundReaderButton(
                  tooltip: 'Previous sentence',
                  icon: Icons.keyboard_double_arrow_left_rounded,
                  onPressed: onPrevSentence,
                ),
              ),
              const SizedBox(width: 18),
              SizedBox(
                key: playButtonKey,
                child: Semantics(
                  button: true,
                  label: isPlaying ? 'Pause reading' : 'Resume reading',
                  child: GestureDetector(
                    onTap: onPlayPause,
                    child: DecoratedBox(
                      decoration: RunThruDecorations.tealButton(
                        borderRadius: 999,
                      ),
                      child: SizedBox(
                        width: 76,
                        height: 76,
                        child: Center(
                          child: Icon(
                            isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 40,
                            color: RunThruTokens.shellCream,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              _RoundReaderButton(
                tooltip: 'Next sentence',
                icon: Icons.keyboard_double_arrow_right_rounded,
                onPressed: onNextSentence,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            key: speedSelectorKey,
            child: _SpeedSelector(selected: wpm, onSelected: onWpmSelected),
          ),
        ],
      ),
    );
  }
}

class _RoundReaderButton extends StatelessWidget {
  const _RoundReaderButton({
    required this.tooltip,
    required this.icon,
    this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RunThruTokens.stageBase,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: RunThruTokens.stageLightShadow,
            offset: Offset(-3, -3),
            blurRadius: 7,
          ),
          BoxShadow(
            color: RunThruTokens.stageDarkShadow,
            offset: Offset(3, 3),
            blurRadius: 8,
          ),
        ],
      ),
      child: Semantics(
        button: true,
        label: tooltip,
        onTap: onPressed,
        child: Tooltip(
          message: tooltip,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerUp: onPressed == null ? null : (_) => onPressed!.call(),
            child: ExcludeSemantics(
              child: IconButton(
                onPressed: onPressed == null ? null : () {},
                icon: Icon(icon, color: RunThruTokens.stageText, size: 24),
                style: IconButton.styleFrom(
                  minimumSize: const Size(52, 52),
                  fixedSize: const Size(52, 52),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpeedSelector extends StatelessWidget {
  const _SpeedSelector({required this.selected, this.onSelected});

  final int selected;
  final ValueChanged<int>? onSelected;

  static const _values = [200, 300, 400, 500];

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('reader-speed-selector-visible-group'),
      label: 'Speed selector. Current speed $selected words per minute.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SPEED',
            style: RunThruTypography.tinyLabel.copyWith(
              color: RunThruTokens.stageText.withValues(alpha: 0.58),
              fontWeight: FontWeight.w800,
            ),
            textScaler: TextScaler.noScaling,
          ),
          const SizedBox(width: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: RunThruTokens.stageBase,
              borderRadius: BorderRadius.circular(999),
              boxShadow: const [
                BoxShadow(
                  color: RunThruTokens.stageLightShadow,
                  offset: Offset(-2, -2),
                  blurRadius: 5,
                ),
                BoxShadow(
                  color: RunThruTokens.stageDarkShadow,
                  offset: Offset(2, 2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: _values.map((value) {
                  // Only an exact match is highlighted. Speeds between the
                  // chips (e.g. the 250 WPM "Comfortable" goal) used to light
                  // up 300, contradicting the header and TalkBack.
                  final active = value == selected;
                  return Semantics(
                    button: true,
                    selected: active,
                    label: '$value WPM',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected?.call(value),
                      child: AnimatedContainer(
                        duration: isReducedMotion(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        width: 58,
                        constraints: const BoxConstraints(
                          minHeight: RunThruA11y.minTapTarget,
                        ),
                        alignment: Alignment.center,
                        decoration: active
                            ? BoxDecoration(
                                color: RunThruTokens.stageBase,
                                borderRadius: BorderRadius.circular(999),
                                boxShadow: const [
                                  BoxShadow(
                                    color: RunThruTokens.stageLightShadow,
                                    offset: Offset(-2, -2),
                                    blurRadius: 5,
                                  ),
                                  BoxShadow(
                                    color: RunThruTokens.stageDarkShadow,
                                    offset: Offset(2, 2),
                                    blurRadius: 6,
                                  ),
                                ],
                              )
                            : null,
                        child: Text(
                          '$value',
                          style: RunThruTypography.caption.copyWith(
                            color: active
                                ? RunThruTokens.shellAccent
                                : RunThruTokens.stageText.withValues(
                                    alpha: 0.62,
                                  ),
                            fontWeight: active
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TapToPausePrompt extends StatelessWidget {
  const _TapToPausePrompt();

  @override
  Widget build(BuildContext context) {
    final color = RunThruTokens.stageText.withValues(alpha: 0.56);

    return IgnorePointer(
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 8,
              height: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PauseBar(color: color),
                  _PauseBar(color: color),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'Tap to pause',
              style: RunThruTypography.tinyLabel.copyWith(color: color),
              textScaler: TextScaler.noScaling,
            ),
          ],
        ),
      ),
    );
  }
}

class _PauseBar extends StatelessWidget {
  const _PauseBar({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
      child: const SizedBox(width: 2.5, height: 12),
    );
  }
}

// ── ORP Focal Word ────────────────────────────────────────────────────────────

const _readerFocalGuideLineHeight = 14.0;
// Gap between the word's em box and each guide tick. Kept tight so the ticks
// read as part of the word, not as separate marks floating above and below.
const _readerFocalGuideGap = 6.0;
const _readerFocalTargetBreathingRoom = 8.0;

EdgeInsets _focalTargetPadding(double fontSize) {
  return EdgeInsets.symmetric(
    horizontal: (fontSize * 0.18).clamp(8.0, 18.0),
    vertical:
        _readerFocalGuideGap +
        _readerFocalGuideLineHeight +
        _readerFocalTargetBreathingRoom,
  );
}

class _FocalTourTarget extends StatelessWidget {
  const _FocalTourTarget({
    super.key,
    required this.word,
    required this.fontSize,
    required this.fontFamily,
  });

  final String word;
  final double fontSize;
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final padding = _focalTargetPadding(fontSize);
    // fontSize arrives pre-scaled by the clamped system text scale (see the
    // reading screen LayoutBuilder), so no additional textScaler is applied —
    // this keeps the measured box identical to the rendered word.
    final textPainter = TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          fontSize: fontSize,
          fontFamily: fontFamily,
          fontWeight: FontWeight.w400,
        ),
      ),
      textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
    )..layout();

    return SizedBox(
      width: textPainter.width + padding.horizontal,
      height: textPainter.height + padding.vertical,
    );
  }
}

class _OrpFocalWord extends StatelessWidget {
  const _OrpFocalWord({
    this.focalTargetKey,
    required this.word,
    required this.fontSize,
    required this.fontFamily,
    required this.isPaused,
    this.dimWhenPaused = true,
    this.anchorColor = RunThruTokens.stageFocalRed,
  });

  /// Colour of the anchor letter and guide ticks (the reader's setting).
  final Color anchorColor;

  final GlobalKey? focalTargetKey;
  final String word;
  final double fontSize;
  final String fontFamily;
  final bool isPaused;
  final bool dimWhenPaused;

  @override
  Widget build(BuildContext context) {
    if (word.isEmpty) return const SizedBox.shrink();

    // One anchor rule for every mode: always a letter, never punctuation.
    // -1 means the token has no letters (a lone dash): show it plainly,
    // centred, instead of flashing an empty stage.
    final displayOrpIdx = anchorIndexInWord(word);

    final style = TextStyle(
      fontSize: fontSize,
      color: RunThruTokens.stageText,
      fontFamily: fontFamily,
      fontWeight: FontWeight.w400,
      height: 1.0,
    );
    final direction = Directionality.of(context);

    // Spritz-style ORP pinning: the word shifts so the anchor letter's
    // centre sits exactly on the fixed centre column (design reader.jsx
    // FocalWord). Widths are measured synchronously so the pin never lags
    // a frame behind the word flash.
    final double shift;
    if (displayOrpIdx < 0) {
      shift = 0;
    } else {
      final prefixWidth = _textWidth(
        word.substring(0, displayOrpIdx),
        style,
        direction,
      );
      final letterWidth = _textWidth(word[displayOrpIdx], style, direction);
      final wordWidth = _textWidth(word, style, direction);
      shift = wordWidth / 2 - (prefixWidth + letterWidth / 2);
    }

    final guideLineColor = anchorColor.withValues(alpha: 0.55);
    const guideLineWidth = 2.0;
    const guideLineRadius = 2.0;
    final guideOffset =
        fontSize / 2 + _readerFocalGuideGap + _readerFocalGuideLineHeight / 2;

    final guideLine = DecoratedBox(
      decoration: BoxDecoration(
        color: guideLineColor,
        borderRadius: BorderRadius.circular(guideLineRadius),
      ),
      child: const SizedBox(
        width: guideLineWidth,
        height: _readerFocalGuideLineHeight,
      ),
    );

    final wordWidget = Stack(
      fit: StackFit.expand,
      children: [
        // Fixed centre-column guide ticks — these never move; each word
        // aligns its anchor letter to them.
        Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(0, -guideOffset),
            child: guideLine,
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(0, guideOffset),
            child: guideLine,
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Transform.translate(
            offset: Offset(shift, 0),
            child: Padding(
              key: focalTargetKey,
              padding: _focalTargetPadding(fontSize),
              child: RichText(
                textScaler: TextScaler.noScaling,
                text: TextSpan(
                  children: displayOrpIdx < 0
                      ? [TextSpan(text: word)]
                      : [
                          TextSpan(text: word.substring(0, displayOrpIdx)),
                          TextSpan(
                            text: word[displayOrpIdx],
                            style: TextStyle(color: anchorColor),
                          ),
                          TextSpan(text: word.substring(displayOrpIdx + 1)),
                        ],
                  style: style,
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (!isPaused || !dimWhenPaused) {
      return wordWidget;
    }

    return AnimatedOpacity(
      opacity: 0.32,
      duration: isReducedMotion(context)
          ? Duration.zero
          : const Duration(milliseconds: RunThruTiming.hintSlideInMs),
      child: wordWidget,
    );
  }

  double _textWidth(String text, TextStyle style, TextDirection direction) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}
