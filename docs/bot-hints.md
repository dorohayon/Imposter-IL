# Bot hint dataset — format and rules

The file is `server/internal/content/bot_hints.json`. It is compiled into the
server with `go:embed` and validated by `go test ./internal/content/`, so a
dataset that breaks a rule fails CI rather than a game.

A skeleton listing every current word, with the category fallback pools seeded
and one worked example (`פיצה`), is already in the file. Fill in the rest.

## Shape

```json
{
  "version": 1,
  "categories": [
    {
      "id": "food",
      "name": "אוכל",
      "impostorFallbackHints": ["טעים", "חם", "מתוק"],
      "citizenHints": {
        "פיצה": ["משולש", "גבינה", "תנור", "איטליה", "משלוח", "פטריות"]
      }
    }
  ]
}
```

- `id` and `name` must match `content.Categories` exactly. Do not add, rename
  or reorder categories here; this file follows the word list, never leads it.
- `citizenHints` is keyed by the secret word, exactly as spelled in
  `content.Categories`. Every word needs an entry and no key may be a word that
  is not in that category.
- Hints are plain strings. There are no weights: `version` is the room to add
  them later if uniform choice ever proves not to be enough.
- UTF-8, no BOM, LF line endings, two-space indent.

**`impostorFallbackHints` is the only thing the impostor may read.** There is
deliberately no impostor list per word. If you ever feel like adding one, that
is the leak this whole structure exists to prevent.

## How many

| | count |
|---|---|
| `citizenHints` per word | 5–7 |
| `impostorFallbackHints` per category | 10–16 |

## Rules a hint must satisfy

These are the engine's own rules, not style preferences. The tests check each
one with the same code that runs in a game (`game.NormalizeWord`,
`game.IsPrefixedForm`, `content.Blocked`), so a hint that breaks one is a bot
that stays silent on its turn.

1. **One word.** No spaces. A geresh is fine and belongs in words that are
   spelled with one — `צ'יפס`, `ג'ונגל`, `דוג'ו` — because normalisation drops
   it and only whitespace breaks the one-word rule. Dropping it to be safe just
   produces a misspelling players can see. Avoid hyphens, though: whether a
   hyphenated word counts as one is still open in `docs/open-decisions.md`.
2. **At most 25 characters.**
3. **Not on the blocklist** (`server/internal/content/blocked_words.txt`).
4. **Must not contain the secret word.** The check is on the normalised form,
   which drops niqqud, geresh, maqaf and punctuation and folds final letters.
   So for `בננה`, both `בננות` and `הבננה` are refused — anything whose letters
   contain the word's letters in sequence.
5. **No two hints in the same pool may be duplicates.** Two hints are the same
   if they are equal after normalisation, or one is the other with 1–3 Hebrew
   prefix letters (`ו ה ב כ ל מ ש`) in front leaving at least two letters. So
   `בית` and `הבית` cannot both be in one pool, but `בית` and `לבית` can.
6. **A fallback hint may not be a secret word in its own category**, or a
   prefixed form of one, or contain one. The impostor's hint is never checked
   against the word, so a fallback that collides means an impostor bot can say
   the answer out loud. `תיק` and `שולחן` did exactly this before this file
   existed.

## What makes a good citizen hint

The engine cannot check these. They are the difference between a bot that
passes validation and one that reads like a person.

- **Related enough to land, loose enough to survive.** Another citizen should
  think "that fits" while the impostor still has work to do.
- **Not a synonym.** `מכונית` for `רכב` is not a hint, it is the word again.
- **Not a definition.** `עגול` for `כדורגל` gives it away in one move.
- **Not true of half the category.** `טעים` under `אוכל` says nothing; it
  belongs in the fallback pool, which is exactly what the fallback pool is for.
- **Vary the angle.** Six hints about how a thing tastes is one hint written
  six times. Spread them across appearance, use, place, time, who does it, what
  it is made of, the feeling it carries, the cultural association.
- **Prefer a hint that could belong to two or three words in the category.** A
  hint that fits exactly one word hands the impostor the answer once the
  derivation step starts reading the board.

## What the fallback pool is for

The impostor bot acting first has nothing but the category, and a human
impostor in that seat writes something broad and hopes. That is what these are:
broad enough to fit many words in the category, specific enough not to be
noise. `טעים`, `חם`, `ארוחה` — never `דבר` or `משהו`.

## Checking your work

```
cd server && go test ./internal/content/
```

The failure names the word and the hint, and says which rule it broke.

Until every word has a pool, `TestEveryWordHasCitizenHints` fails and says how
many are left. That is deliberate: the branch is not mergeable until the
dataset is complete, so half a dataset cannot reach players.

## How the vote reads the round

One reading serves every bot at the table. It is given the board and nothing
else — the category, who said what, in what order — and has no parameter for
the secret word, for who the impostor is, or for who is a person. Each hint is
judged against the round built without it.

Two things count against a hint: **standing apart** from every other hint on
the board, and being one of the category's broad fallbacks — and never both at
once. A hint the category calls broad was always going to reach nothing in
particular; that is what makes it broad, so charging it for standing apart as
well charges it twice for one fact. Saying little is not the same as saying
something that does not belong, and it reads as the lesser of the two.

Standing apart is binary, never a matter of degree. Two bots drawing on the
same curated pool are joined by direct evidence and would out-weigh any
outsider, so measuring strength would measure who shares a vocabulary rather
than who fits the round.

A hint reaches the round if the graph pairs it with another hint played, or if
it shares a stem with one — `גבינות` reaches `גבינה`, `איטלקי` reaches
`איטליה`. The stem rule is the only thing that speaks for a word nobody
curated, which is to say for most of what a person writes. The graph is keyed
the way the game reads a word, so `גונגל` reaches the curated `ג'ונגל`:
spelling decides nothing.

**Silence is not evidence.** A word the graph has never heard of, which reaches
nothing on the board through its shape either, is a word we know nothing about,
and it sits exactly where the round sits — neither accused nor cleared. The one
person at a table of bots is the one player whose words are guaranteed to be
missing from a graph built out of what bots say, so reading that silence as
guilt would hunt them by construction.

What that buys, measured over 30,000 rounds. The person is voted for in
proportion to how badly their hint fits, and never to who they are:

| the person's hint | as a citizen | as the impostor |
|---|---|---|
| their own words, outside the graph | 32% | 50% |
| a broad category word | 49% | 69% |
| a word belonging to another round | 64% | 82% |
| *chance* | *33%* | *50%* |

The middle and bottom rows are the point: a hint that does not fit draws votes
whoever wrote it. The top row is the honest limit — there is no semantic model
here, only this graph, and a word outside it cannot be judged by anyone.

Which is the other reason to prefer hints that overlap across a category.
Every curated pair is a pair the round can be read by.

## Why a hint that fits only one word is wasted on the impostor

The impostor's candidates are the hints **two or more words in the category
share**. A hint used by exactly one word is that word's signature, and letting
the impostor reach for it would make a bot better at the game than a person in
the same seat.

So a pool of six hints that are each unique to their word validates perfectly
and contributes nothing to the impostor — the bot falls back to the broad pool
and the round reads like the one before it. Hints that overlap across two or
three words in the category are what give an impostor something to read.
