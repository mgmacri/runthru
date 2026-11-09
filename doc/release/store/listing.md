# RunThru — store listing copy (2.0)

Paste into Google Play Console and App Store Connect. Keep both in sync.

## App name

RunThru: Paced Reading

## Subtitle (App Store, max 30)

Read one word at a time

## Short description (Google Play, max 80)

Calm, paced reading one word at a time. Built for ADHD, dyslexia and focus.

## Promotional text (App Store, max 170)

Get through the reading you've been putting off. RunThru shows one word at a time, at a pace that adapts to each word, and always keeps your place.

## Full description (both stores, max 4000)

Your attention isn't broken. It just needs a better direction.

RunThru shows text one word at a time, right where your eyes already are. No
lines to track, no losing your place, no wall of text. Each word gets the time
it needs: longer words and the ends of sentences linger a little, short common
words move along. You set the overall speed; RunThru handles the rhythm.

Built with ADHD, dyslexic, autistic and low-vision readers in mind, and useful
for anyone who wants to get through a document without drifting off.

WHAT YOU CAN READ
- PDFs and EPUBs from your device
- Articles saved to Instapaper
- Files from Google Drive
- Anything you copy or share into the app

READING THAT WORKS WITH YOU
- One word at a time, with a highlighted focus letter so your eyes land in the
  same spot every time
- Pause any time; when you resume, RunThru steps back three words so you never
  lose the thread
- Swipe up to see the whole sentence around the current word, then swipe down
  to carry on from where you choose
- Paragraph and Full Page modes when you want to see more of the text
- Pick only the pages you need, such as one assigned chapter (Unlock)
- Reading goals that set a comfortable pace for deep reading or quick scanning

COMFORT AND ACCESSIBILITY
- Atkinson Hyperlegible as the default reading font, plus alternatives
- Adjustable text size, letter spacing and focus-letter colour, with contrast
  checks
- Respects your system's reduce-motion setting
- Full screen reader support
- An optional 3D reading room that tilts gently with your phone (Unlock)

PRIVATE BY DESIGN
- Your documents are read on your device and stay there
- No ads, no analytics, no tracking, no account
- Instapaper sync is the only thing that ever leaves your device, and only if
  you connect it

FREE TO READ, ONE PAYMENT TO UNLOCK
Reading, every reading mode, every source and every comfort setting are free.
RunThru Unlock is a single one-time purchase, no subscription, that adds
Reading Wins (time, streaks and gentle progress notes), page ranges and the
3D reading room.

## Keywords (App Store, max 100, comma separated, no space after commas)

rsvp,speed reading,adhd,dyslexia,focus,pdf reader,epub,instapaper,accessibility,reading

## Category

Primary: Education. Secondary (App Store): Productivity.

## Contact and policy

- Support email: mattmacri89@gmail.com (same address the runthruapp.com footer uses)
- Privacy policy URL: https://runthruapp.com/privacy (gh-pages `privacy/index.html`, rendered from `doc/legal/privacy_policy.md`)
- Marketing URL: https://runthruapp.com/

## Screenshots

Generate a draft set (1170×2532, iPhone 6.1"):

```bash
flutter test --tags screenshots --run-skipped test/screenshots
# output: screenshots/app/01-library.png … 07-range-picker.png
```

App Store Connect also needs a 6.9" set (1320×2868) and Play needs a
1024×500 feature graphic. Capture those from a real device or change
`phoneSize`/`pixelRatio` in the generator.

## In-app product (create in both consoles)

- Product ID: `runthru_unlock` (must match `runThruUnlockProductId`)
- Type: App Store non-consumable / Play one-time product
- Name: RunThru Unlock
- Description: One-time unlock: Reading Wins, page ranges and the 3D room.
- Price: owner to set (suggested tier: $4.99)
- App Store review screenshot: the Unlock sheet (Settings, RunThru Unlock)

## Data safety / App privacy answers

- Data collected: none. (Purchases are processed by Apple/Google; the app
  stores only an on-device "owned" flag, which is not collected.)
- Data shared: none. (Instapaper progress sync goes to the user's own account
  at their request; both stores treat user-initiated transfer to a
  user-chosen service as not "shared".)
- Encryption in transit: yes (HTTPS only).
- Account deletion: not applicable (no accounts).
- Tracking (App Store): no.
