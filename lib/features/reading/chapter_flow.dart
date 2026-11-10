/// Decides what the reader does at chapter boundaries.
///
/// Pure: given the book's structure and how the reading position moved, it
/// says whether a chapter just ended, a heading should be announced, or the
/// position landed inside a heading and should move on to the text. The
/// reading screen acts on the answer; the word timer knows nothing of it.
library;

import 'package:runthru/core/book_structure.dart';
import 'package:runthru/features/reading/widgets/chapter_title_card.dart';
import 'package:runthru/features/reading/widgets/section_complete_overlay.dart';

/// Something the reader should do because the position moved.
sealed class ChapterEvent {
  const ChapterEvent();
}

/// Reading ran off the end of [completed] onto the first word of [next].
class SectionBoundary extends ChapterEvent {
  /// Creates the event.
  const SectionBoundary({required this.completed, required this.next});

  /// The section that was just read to its last word.
  final BookSection completed;

  /// The section that starts here.
  final BookSection next;

  /// Whether the book's text ends here: what follows is back matter.
  bool get endsBook =>
      completed.kind == SectionKind.body && next.kind == SectionKind.back;
}

/// Reading reached a heading inside a chapter.
class SubHeadingReached extends ChapterEvent {
  /// Creates the event.
  const SubHeadingReached(this.heading);

  /// The heading to announce.
  final SubHeading heading;
}

/// The position landed among heading words (a rewind, a seek): reading
/// should carry on from [to], the first word of the text.
class SkipHeading extends ChapterEvent {
  /// Creates the event.
  const SkipHeading(this.to);

  /// First word after the heading.
  final int to;
}

/// The event for the position moving from [previous] to [current] while
/// the timer is running, or null when reading simply continues.
///
/// Only a step of exactly one word onto a section's first word counts as
/// finishing the section before it: a jump (sentence skip, contents, a
/// rewind) is never a completion.
ChapterEvent? chapterEventFor({
  required BookStructure structure,
  required int previous,
  required int current,
}) {
  final section = structure.sectionAt(current);
  final advanced = current == previous + 1;

  if (current == section.start && section.index > 0 && advanced) {
    final completed = structure.sections[section.index - 1];
    final boundary = SectionBoundary(completed: completed, next: section);
    if (section.isTitled || boundary.endsBook) return boundary;
  }

  if (section.headingWords > 0 &&
      current >= section.start &&
      current < section.textStart &&
      section.textStart < section.end) {
    // Stepping onto an untitled boundary never reaches here (no heading);
    // anything else among heading words moves on to the text.
    return SkipHeading(section.textStart);
  }

  final sub = _subHeadingContaining(structure, current);
  if (sub != null) {
    if (current == sub.start && advanced) return SubHeadingReached(sub);
    final after = sub.start + sub.wordCount;
    if (after < structure.totalWords) return SkipHeading(after);
  }
  return null;
}

/// Where reading should start when play is pressed at [index]: the title
/// card to show first (when the position is a chapter's first word), and
/// the word to start from.
({BookSection? announce, int from}) playStartFor(
  BookStructure structure,
  int index,
) {
  final section = structure.sectionAt(index);
  final inHeading =
      section.headingWords > 0 &&
      index >= section.start &&
      index < section.textStart &&
      section.textStart < section.end;
  if (index == section.start && section.isTitled) {
    return (announce: section, from: section.textStart);
  }
  if (inHeading) return (announce: null, from: section.textStart);
  final sub = _subHeadingContaining(structure, index);
  if (sub != null && sub.start + sub.wordCount < structure.totalWords) {
    return (announce: null, from: sub.start + sub.wordCount);
  }
  return (announce: null, from: index);
}

SubHeading? _subHeadingContaining(BookStructure structure, int index) {
  final list = structure.subHeadings;
  var lo = 0;
  var hi = list.length - 1;
  SubHeading? found;
  while (lo <= hi) {
    final mid = (lo + hi) ~/ 2;
    if (list[mid].start <= index) {
      found = list[mid];
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (found == null || index >= found.start + found.wordCount) return null;
  return found;
}

/// Minutes to read [words] at [wpm] (at least one).
int minutesFor(int words, int wpm) {
  if (words <= 0) return 0;
  final minutes = (words / wpm.clamp(30, 1500)).ceil();
  return minutes < 1 ? 1 : minutes;
}

/// The title card for [section].
ChapterAnnouncement announcementFor(
  BookStructure structure,
  BookSection section, {
  required int wpm,
  String? skippedNote,
}) {
  final number = structure.chapterNumber(section);
  final count = structure.chapters.length;
  return ChapterAnnouncement(
    headline: section.headline,
    overline: section.overline,
    groupTitle: section.groupTitle,
    subtitle: section.subtitle,
    position: number > 0 && count >= 2 ? '$number of $count' : null,
    minutes: section.wordCount > 0 ? minutesFor(section.wordCount, wpm) : null,
    skippedNote: skippedNote,
  );
}

/// "Chapter 3 complete", "Prologue complete", "Section complete".
String completionHeadline(BookSection section) {
  if (section.label.isNotEmpty) return '${section.label} complete';
  return switch (section.role) {
    SectionRole.prologue => 'Prologue complete',
    SectionRole.epilogue => 'Epilogue complete',
    SectionRole.introduction => 'Introduction complete',
    SectionRole.chapter => 'Chapter complete',
    _ => 'Section complete',
  };
}

/// The chapter's own name under the headline, unless the headline already
/// says it ("Prologue complete" needs no "Prologue" beneath).
String? _completionDetail(BookSection section) {
  final title = section.title;
  if (title.isEmpty) return null;
  final headline = completionHeadline(section).toLowerCase();
  if (headline.startsWith(title.toLowerCase())) return null;
  return title;
}

/// The chapter-complete summary for [completed], read from word
/// [readFrom] in [readingTime].
SectionCompletion completionFor(
  BookStructure structure, {
  required BookSection completed,
  required BookSection? next,
  required int readFrom,
  required Duration readingTime,
  required int wpm,
}) {
  final from = readFrom < completed.textStart ? completed.textStart : readFrom;
  final bodyWords = structure.bodyEnd - structure.bodyStart;
  final number = structure.chapterNumber(completed);
  return SectionCompletion(
    headline: completionHeadline(completed),
    detail: _completionDetail(completed),
    wordsRead: (completed.end - from).clamp(0, completed.end),
    readingTime: readingTime,
    chapterNumber: number,
    chapterCount: number > 0 ? structure.chapters.length : 0,
    bookProgress: bodyWords <= 0
        ? 1
        : ((completed.end - structure.bodyStart) / bodyWords).clamp(0.0, 1.0),
    nextName: next?.displayName(fallback: 'Next section'),
    nextMinutes: next == null || next.wordCount <= 0
        ? null
        : minutesFor(next.wordCount, wpm),
  );
}
