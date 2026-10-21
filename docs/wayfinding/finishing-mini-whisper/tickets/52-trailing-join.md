---
status: open
type: task
blocked-by: []
---

# The join only looks backwards, so dictating in front of existing text runs the words together

## The defect

Put the caret immediately before existing text and dictate. The transcript arrives flush against the word that follows it — `…dictated texttext that was already there` — with no separating space. Reported from daily use, 2026-08-21.

`TranscriptJoin` decides two things, a leading space and the first letter's case, and both read only `context.before`. Its own doc comment says so outright:

> Only the text before the insertion point matters: a paste replaces the selection, so the selected text is on its way out.

That justification is about the *selection*, not about text after the caret, and it quietly became a rule about both. `FocusedTextContext` captures `after` and `afterWasTruncated`, and the cleanup prompt already stages `AFTER_CARET` — so the fact is captured, reaches the model, and is then ignored by the one component whose job is joining. The deterministic layer never sees it. `FocusedTextContext.swift:120` is the only construction site, and it passes `before` alone.

## What has to be decided before it is fixed

The trailing rule is not the mirror image of the leading one, and writing it as one would introduce a second defect:

- A following character that hugs what precedes it takes no space: a closing bracket or quote, and `.` `,` `;` `:` `!` `?`. Dictating in front of `, and then we left` must not produce `text , and then`.
- Whitespace already at the caret is the existing separator; adding another doubles it. The leading rule handles this by checking the first character of the transcript, and the trailing rule has to check the first character of `after`.
- `afterWasTruncated` matters for the same reason `beforeWasTruncated` does: an empty `after` slice means "nothing follows" only when it was not truncated to nothing.
- Casing stays one-directional. The transcript's own first letter may be re-cased, because it is ours. The following text is the user's and is never touched, however wrong its capital now looks.

Whether the leading and trailing decisions are one type with two answers or two types is an implementation question, but they share `wasTruncated` handling and the hugging-punctuation set, so a single value with `needsLeadingSpace` and `needsTrailingSpace` is the obvious shape.

## Done when

`TranscriptJoin` takes the following text as well as the preceding text, `FocusedTextContext` passes both, and `Packages/FieldContext/Tests/FieldContextTests/TranscriptJoinTests.swift` covers the caret-before-text cases the way it already covers caret-after-text: a plain word, a following punctuation mark, existing whitespace, and a truncated window. Delivered by a real dictation in front of real text, not only by the test.
