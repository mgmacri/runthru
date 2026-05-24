# ReadBrain — RunThru × Obsidian Second Brain

> *Every word you've ever paced through, remembered.*

---

## Vision

Reading without retention is a treadmill. RunThru already solves the attention problem — you actually finish things. ReadBrain solves what comes next: **your reading becomes a living knowledge graph**, built by a tiny AI model running entirely on your device, automatically synced into an Obsidian vault that thinks alongside you.

No cloud. No subscription wall on the thinking. 1.5–3B parameters is all you need.

---

## The Core Loop

```
Read in RunThru  →  Edge AI extracts meaning  →  Obsidian vault grows
       ↑                                                    ↓
  Re-enter reading  ←  Vault surfaces connections  ←  Canvas / graph
```

1. You pace through an article or book chapter in RunThru.
2. An on-device model (running via a local inference engine) processes the text as you read — at your pace, not ahead of you.
3. Extracted notes, concepts, questions, and connections are written to your Obsidian vault via the local REST API plugin.
4. The vault builds itself. Bidirectional links form between this session and every prior one.
5. Obsidian's graph view becomes your memory palace.

---

## Edge AI Model Selection

Target: runs on iPhone 12+ / mid-range Android. Latency < 300ms per paragraph.

| Model | Params | Why It Works |
|-------|--------|--------------|
| **Qwen 2.5-1.5B-Instruct** | 1.5B | Best reasoning-per-token in class. Vocabulary optimized for English + code |
| **Llama 3.2 3B-Instruct** | 3B | Strong instruction following, great at list extraction |
| **Gemma 2 2B-IT** | 2B | Excellent summarization, Google-trained on quality data |
| **SmolLM2-1.7B-Instruct** | 1.7B | Designed for edge deployment by HuggingFace — tiny footprint |
| **Phi-3.5-mini** | 3.8B | Best in class reasoning; only viable on high-end devices |

**Architecture decision:** Ship Qwen 2.5-1.5B as default (fastest, smallest), unlock Llama 3B as "Deeper Thinking" mode for users with A15+ chips. Use GGUF quantization via llama.cpp bindings or use Apple MLX on iOS.

---

## What the AI Extracts (Per Reading Session)

The model processes text in 3-paragraph windows, sliding as you read. It outputs structured JSON that maps to Obsidian note types.

### 1. Concepts (`/Concepts/*.md`)
Atomic ideas from the text. Each becomes its own evergreen note.

```json
{
  "concept": "Attentional narrowing under cognitive load",
  "definition": "Working memory compression causes peripheral signal dropout during high-demand tasks",
  "source": "The Attention Merchants, Ch. 4",
  "evidence": "Kahneman's pupil dilation studies showed...",
  "tags": ["cognition", "attention", "neuroscience"]
}
```

### 2. Claims + Evidence (`/Claims/*.md`)
Falsifiable assertions the author makes, tagged by confidence level.

```
Claim: Social media degrades sustained reading ability
Confidence: medium
Evidence type: correlational study (N=847)
Counter-evidence noted: yes
```

### 3. Open Questions (`/Questions/*.md`)
Questions the text raises that it doesn't answer. Seeds for future reading.

```
- What's the neurological basis for reading flow states?
- How does ORP compare to RSVP for retention?
- Is the "digital natives" claim empirically supported?
```

### 4. Quotable Passages (`/Quotes/*.md`)
The model scores sentences for memorability using a lightweight heuristic: density × surprise × brevity.

```
"Attention is the rarest and purest form of generosity." — Simone Weil
Score: 0.94 | Tags: attention, generosity, philosophy
```

### 5. Connection Hooks (`/Connections/*.md`)
The most powerful output. The model checks what you've already read (via vault index) and flags:
- **Echoes**: This idea appeared before in vault note X
- **Tensions**: This contradicts claim Y from 3 weeks ago
- **Bridges**: This explains why Z (from your questions folder) works

---

## Vault Architecture

```
📁 ReadBrain/
├── 📁 Inbox/              # Raw session dumps — unprocessed
├── 📁 Sources/            # One note per book/article
│   ├── The Attention Merchants.md
│   └── Deep Work - Cal Newport.md
├── 📁 Concepts/           # Atomic evergreen notes
├── 📁 Claims/             # Falsifiable assertions + evidence
├── 📁 Questions/          # Open questions, unsorted
├── 📁 Quotes/             # Memorable passages, scored
├── 📁 Connections/        # Cross-source bridges
├── 📁 Synthesis/          # AI-generated synthesis essays
├── 📁 Sessions/           # Per-reading-session journals
│   └── 2026-05-23 - Attention Merchants Ch4.md
├── 📁 Canvas/             # Auto-generated concept maps
└── 🗺️ GRAPH_HOME.md      # Entry point with MOC structure
```

### Source Note Template

```markdown
---
title: The Attention Merchants
author: Tim Wu
type: book
started: 2026-05-10
finished: 2026-05-23
runthru_sessions: 12
avg_wpm: 247
completion: 100%
tags: [media, attention, history, economics]
---

## Key Concepts
- [[Attention economy]]
- [[Manufactured consent]]
- [[Advertiser-audience contract]]

## Open Questions
![[Questions/attention-merchants-questions]]

## My Synthesis
*AI-generated first draft, edit freely:*
Wu argues that the commodification of attention precedes social media by a century...
```

---

## The Engagement Speed Signal

This is original and unique to RunThru. Nobody else has this data.

Your WPM at each moment tells the model where you were **engaged vs. scanning**.

- WPM drops → high engagement or confusion → flag this passage as High-Value
- WPM spikes → skimming → mark as Low-Retention zone
- WPM dial turn-back → you re-read something → mark as Conceptually Dense

These signals are attached to every extracted note:

```
Concept: "Parasocial relationship formation"
Engagement signal: HIGH (WPM dropped 40% here)
Re-read: yes (returned to passage twice)
Vault weight: 0.91
```

High-weight concepts rise to the top of your graph. Low-weight ones stay buried. Your attention is the ranking algorithm.

---

## Original Plugins (Ship These)

### 1. `runthru-obsidian-sync` — The Bridge Plugin

An Obsidian community plugin that:
- Exposes a local WebSocket server on port 27183
- Receives structured JSON from RunThru (via app URL scheme on iOS, local HTTP on Android)
- Writes notes to vault using Obsidian's native file API
- Respects frontmatter templates per folder
- Fires Dataview-compatible metadata

Install: `obsidian://install-plugin?id=runthru-obsidian-sync`

### 2. `PaceMap` — Session Canvas Builder

After each reading session, auto-generates an Obsidian Canvas (`.canvas`) file:
- Nodes = extracted concepts, color-coded by engagement weight
- Edges = connection types (echo, tension, bridge)
- Source node anchored at center
- Drag-and-rearrange forever; AI won't overwrite your layout

The canvas is beautiful. It looks like a mind map you built but didn't have to.

### 3. `GhostReader` — Pre-Flight Questions

Before you start a reading session, the vault scans your existing notes and generates:
- 3 "prime" questions to hold in mind while reading
- 2 "watch for" flags based on existing tensions in your vault
- 1 "connect to" suggestion linking today's content to old notes

Example output before reading Ch. 5 of Attention Merchants:
```
Prime questions:
→ How does the attention economy relate to your note on [[Flow State]]?
→ What would Wu say about RunThru's pacing model?
→ Is "manufactured demand" morally distinct from persuasion?

Watch for:
→ Any data that contradicts [[Claim: Social media is the root cause]]
→ Historical examples that would extend your [[Timeline: Media tech]] note

Connect to:
→ [[Deep Work - Cal Newport]] — Wu likely echoes Newport's distraction economy framing
```

### 4. `MemoryArc` — Spaced Repetition from the Vault

Bidirectional: not just reading → vault, but vault → reading.

When you open RunThru, MemoryArc surfaces:
- 3 quotes you captured, ready for review (SRS intervals)
- 1 open question from your vault to keep in mind
- 1 concept from 30 days ago that links to today's content

Feels like your past self left you notes. Because they did.

### 5. `ReadingDNA` — Your Vault Taxonomy, Auto-Built

Every user builds different vaults. ReadingDNA analyzes your 90-day vault graph and:
- Identifies your 5 "core interest clusters" (tag clouds that actually connect)
- Suggests folder restructures that match how YOU think, not a template
- Flags orphan notes with no connections (dead reads — you captured but never engaged)
- Generates a monthly "intellectual fingerprint" — what shifted this month

---

## Community Vault Templates

Ship a marketplace with pre-built vault starters for different reader types:

### Template: The Researcher
```
Focus: Claims + evidence chains
Highlights: Dataview table of all claims by confidence
Best for: Academics, journalists, fact-checkers
```

### Template: The Builder
```
Focus: Concept → Application → Project links
Highlights: "How would I use this?" note appended to every concept
Best for: Engineers, entrepreneurs, makers
```

### Template: The Philosopher
```
Focus: Questions and tensions
Highlights: Dialectic view — pairs every claim with best counter-claim
Best for: People who argue with books
```

### Template: The Storyteller
```
Focus: Quotes, imagery, voice
Highlights: Writing prompt generated from every memorable passage
Best for: Writers, creatives, people stealing good sentences
```

### Template: The Minimalist
```
Focus: One note per book, ever
Highlights: Auto-compress all session outputs into a single evolving Source note
Best for: People who don't want a second job managing their second brain
```

---

## The Synthesis Engine

Once your vault has > 20 source notes, unlock **Synthesis Mode**.

The on-device model reads your vault's concept index (not full notes — just titles and tags, keeping context window manageable) and generates:

**Cross-Book Thesis Drafts**
"Based on your reading of Wu, Newport, and Kahneman: here is a 3-paragraph argument about why the attention economy and cognitive bandwidth are structurally linked."

**Intellectual Timeline**
"In January you believed X. By April, after reading Y, your vault shifted toward Z. Here's the evolution."

**Debate Seed**
"Here are two concepts from your vault that directly contradict each other. Neither source acknowledges the other. What do you think?"

These outputs land in `/Synthesis/` and are clearly labeled AI-generated, meant to be edited, extended, or deleted. They're starting points, not conclusions.

---

## Technical Architecture

### RunThru Side (Flutter)

```dart
// Fires after each paragraph window during pacing
class ReadBrainExtractor {
  final EdgeInferenceService _ai;  // llama.cpp FFI bindings
  final ObsidianBridgeClient _bridge;

  Future<void> processWindow({
    required String text,
    required double wpm,
    required String sourceId,
  }) async {
    final extraction = await _ai.extract(
      prompt: _buildExtractionPrompt(text, wpm),
      maxTokens: 512,
    );
    await _bridge.push(ExtractionPayload(
      sourceId: sourceId,
      engagement: wpm,
      data: extraction,
    ));
  }
}
```

```dart
// Local bridge — iOS uses URL scheme, desktop uses HTTP
class ObsidianBridgeClient {
  static const _port = 27183;

  Future<void> push(ExtractionPayload payload) async {
    if (Platform.isIOS || Platform.isAndroid) {
      await _pushUrlScheme(payload);
    } else {
      await _pushHttp(payload);
    }
  }
}
```

### Inference Pipeline

```
Text window (3 paragraphs)
    ↓
Tokenizer (sentencepiece, on-device)
    ↓
GGUF model (Q4_K_M quantization)
    ↓
Structured output (JSON mode / grammar-constrained decoding)
    ↓
ExtractionPayload struct
    ↓
Obsidian REST API / WebSocket
```

**Grammar-constrained decoding** is the key. Instead of hoping the model outputs valid JSON, we constrain the token sampler to only produce tokens that match our JSON schema at each position. Zero parse failures. llama.cpp supports this natively via `llama_grammar`.

### Obsidian Plugin Side (TypeScript)

```typescript
// runthru-obsidian-sync/main.ts
export default class RunThruSync extends Plugin {
  private server: WebSocketServer;

  async onload() {
    this.server = new WebSocketServer({ port: 27183 });
    this.server.on('connection', (ws) => {
      ws.on('message', async (data) => {
        const payload = JSON.parse(data.toString()) as ExtractionPayload;
        await this.writeToVault(payload);
      });
    });
  }

  async writeToVault(payload: ExtractionPayload) {
    const noteWriter = new NoteWriter(this.app.vault, payload);
    await noteWriter.writeAll();  // concepts, claims, quotes, connections
  }
}
```

---

## Privacy Architecture

- All inference runs **on-device**. Text never leaves the phone.
- Obsidian vault syncs via **iCloud / Obsidian Sync** — user-controlled, not RunThru servers.
- The bridge is a **local WebSocket** on loopback (127.0.0.1). No external calls.
- Model weights ship in the app bundle or download once to local storage.
- **Zero telemetry** on reading content. Session metadata (WPM, completion) stays in RunThru's local analytics (already privacy-first).

ReadBrain is structurally incapable of sending your reading content anywhere. The architecture enforces this — there's no endpoint to send it to.

---

## Monetization Angle (Ethical)

ReadBrain is a **premium feature**, not a paywall on core reading.

| Tier | Features |
|------|----------|
| Free | ReadThru pacing, core reading, basic session notes (manual) |
| ReadBrain ($4.99/mo or $39/yr) | Full AI extraction, vault sync, all plugins, all templates |
| ReadBrain + Community ($6.99/mo) | Template marketplace, shared connection graphs (anonymized), Synthesis engine |

Accessibility features never gated. The dyslexia font, spacing controls, CVD themes — free forever.

---

## What Makes This Actually Different

Everything else in the "read-to-note" space is:
- Browser extensions that capture highlights you manually make
- GPT-4 summaries you paste in (cloud, expensive, generic)
- Readwise (great, but no on-device AI, no pacing integration)

ReadBrain is different because:

1. **The engagement signal** — your WPM during reading is a real-time attention measurement no other app has. It's the metadata that makes your notes *yours*.

2. **Edge-first** — 1.5–3B models are genuinely good enough for extraction tasks. This runs on your phone with no API key.

3. **RunThru's pacing is the input modality** — reading through the cube viewport at your personal WPM creates a fundamentally different extraction surface than scrolling through a PDF.

4. **The vault builds connections, not just notes** — most tools dump text. ReadBrain's connection detection (echo/tension/bridge) is what makes the graph worth exploring.

5. **Bidirectionality** — vault → reading (GhostReader, MemoryArc) is rare. Most tools are one-way. This closes the loop.

---

## Roadmap (If This Gets Built)

| Phase | Deliverable |
|-------|------------|
| **R0** | Obsidian REST API bridge, basic session note export, no AI |
| **R1** | On-device model integration (Qwen 1.5B), concept + quote extraction |
| **R2** | Engagement signal attached to extractions, PaceMap canvas builder |
| **R3** | GhostReader (pre-session priming), MemoryArc (SRS loop back) |
| **R4** | Synthesis engine, vault template marketplace, community plugins |
| **R5** | ReadingDNA (personal taxonomy), cross-vault anonymized graph community |

---

## The Name

**ReadBrain** — working title. Alternatives:
- **PaperMind** — cleaner, slightly less literal
- **VaultReader** — obvious but clear
- **Echoes** — evocative of the connection detection feature
- **The Margin** — where reading and thinking meet

---

*Saved: 2026-05-23*
*Context: RunThru M1.6+ ideation — post-launch feature exploration*
