import 'package:runthru/core/clipboard_document.dart';
import 'package:runthru/services/models.dart';

const sampleContentId = 'sample://runthru-welcome';
const sampleTitle = 'Welcome to RunThru';

const _sampleText =
    'Reading should feel effortless. RunThru shows you one word at a time, '
    'right where your eyes are already looking. There is nothing to scan and '
    'nothing to track, so you never lose your place.\n\n'
    'That tinted letter marks the spot your brain recognises a word fastest. '
    'Every word lines up to it automatically. Your eyes stay still while the '
    'words come to you.\n\n'
    'You are always in control. Pause anytime with a tap. Step back a sentence '
    'if something slipped past. Adjust the speed until it feels just right.\n\n'
    'Start gentle. There is no rush and no finish line. RunThru bends to you, '
    'never the other way around.';

ClipboardDocument get sampleDocument =>
    ClipboardDocument.fromClipboardText(_sampleText);

ExtractedDocument get sampleExtractedDocument => sampleDocument.document;
