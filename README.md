# ✎ Thoughtful Reading for KOReader

Book club style questions at the end of chapters, fully offline. Answer in a few words, attach one of your highlights, or just tick *Noted in my journal*.

> Made for ZenOS, but works in plain KOReader too. Questions and feedback are welcome under [Issues](../../issues).

## Features

- **Questions at chapter ends:** two questions (1–3, adjustable) for the part of the book you're in (Beginning, Middle, End), from different categories. At the start of volume 2 or later, series questions come first. Questions with tags only appear in matching books (e.g. crime, WH40K, nonfiction).
- **Your highlights:** a passage you highlighted since the last stop can become "Why did you mark this?".
- **Lexicon questions:** with a lexicon for the book ([Book Lexicon](https://github.com/Lamberjoe/booklexicon.koplugin) or the ZenOS fork), there is one question about a main character after 40 % and one at the end. The end question shows your answer from the middle, so you can see whether your opinion held up. The lexicon is only read, never written.
- **Characters:** the people of the lexicon, counted in the part you've already read (no spoilers). The 2–3 most named people are main characters. `Role: Main` or `Role: Side` on a lexicon card overrides the count.
- **Questions & answers:** all questions of the book by part, with your answers, highlights, chapter and %.
- **All books:** every book you answered questions for, the last answered first, in the book and in the library. You can change answers there and open the book.
- **Export:** one book, or all books, as a Markdown file in `koreader/clipboard/`.
- **Edit questions:** change, add or delete questions on the device. They're saved to `koreader/settings/thoughtfulreading_questions.txt`, which you can also edit on a PC.

## Installation

Copy the folder `thoughtfulreading.koplugin` into `koreader/plugins/` and restart KOReader. The menu is under **Tools › Thoughtful Reading**.

## Settings

- **Show questions:** at every chapter end, every 3rd chapter, only beginning/middle/end, or never (then only *Ask me now*)
- **Questions per stop:** 1–3
- **Questions about lexicon cards:** on/off (default on)
- **Gestures:** *Ask me now* and *Questions & answers* can be put on a gesture (Gesture manager). The plugin sets no gesture itself.

## Where the data is stored

- Answers: with each book, in its `.sdr` folder
- List of books with answers (for All books): KOReader's settings
- Own questions: `koreader/settings/thoughtfulreading_questions.txt` (one question per line: `part | category | tags | question`)

## Mockup

[`mockup/thoughtful-reading.html`](mockup/thoughtful-reading.html) is a clickable mockup of the whole plugin at Kobo size. Download it and open it in a browser.

## Versions

- **0.2.0:** All books (also in the library), Export all books, Edit questions, lexicon questions and Characters, two-page view fix
- **0.2.1:** chapter stops stay right after a font or margin change, names counted faster, texts translatable, finds a lexicon that stays with a renamed book
- **0.1.0:** questions at chapter ends, highlight questions, answers, list per book, export

## License

GPL-3.0, like ZenOS.
