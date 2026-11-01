# Ashrift

An original two-warden card duel for Godot 4.7. You play one premade deck. Rook, a deterministic rules bot, plays the other. There is no network play.

Factions: Emberline (rush and life costs), Mirevault (tribute and death chains), Glassward (traps, silence, bounce, tax), plus shared Wayline tools. The pool is 100 cards: 96 unique cards and 4 tokens. Each 32-card deck is one faction plus eight Wayline cards, and every non-token card appears in exactly one deck.

## Run

Open the project in Godot 4.7 (GL Compatibility) and press Play, or from a shell:

```
godot --path .
```

The main scene is `res://scenes/main.tscn`. Pick a faction and a seed. Gold marks a legal card. Click it, confirm the extra costs and targets, then confirm the play. Pass gives priority back. End phase asks to leave the current phase. Space passes, Enter confirms, Esc cancels. Skip flashes drops the bursts without changing the duel.

Headless rules and scene tests:

```
godot --headless --path . -s res://tests/run_tests.gd
```

A passing run prints `PASS` and exits 0.

## Rules the engine executes

Spark is the growing resource. The cap starts at 0, grows by 1 at the start of each of your turns, to a maximum of 10, and refills to the cap. Some cards also cost life (you cannot pay below 1), a tribute, or cards shed from hand. Both wardens start at 30 life. Healing stops at 30.

A turn is draw, main, combat, end. The first warden does not draw on the first turn. Drawing from an empty deck loses. Life at 0 loses.

Zones are deck, hand (end the turn with at most 7, hard cap 10), five lanes, graveyard, and the veil (up to 3 set traps). A trap cannot be revealed on the turn it was set. A declared play, attack, or trap sits on a chain. The other warden may answer with an instant or a matching trap before it resolves. Two passes resolve the chain from the top. Costs are paid when the play is declared and are not refunded if the play is negated.

Units have attack, health, keywords, and hooks (`on_play`, `on_attack`, `on_death`, `while_board`, `on_spell`). Keywords are Rush, Guard, Ward, Venom, Pierce, Siphon, Breach, and Twinstrike. Silence clears keywords, hooks, and bonus stats. Damage already taken stays.

The view only changes the duel by calling the rules API.

## Layout

```
rules/        state machine, no nodes
data/cards/   card definitions
data/decks/   the three premade decks
tests/        headless suite
scenes/       menu and table
scripts/      view
vfx/          flashes
```

Card frames are drawn in code. No imported art.

## Limits

- Solo only. Rook plays legal lines from a fixed heuristic.
- Three premade decks. No deck builder.
- A shed printed on a card is chosen by you. A shed caused by an effect discards the cheapest cards in hand (lowest printed cost, then id).
- A summon created by an effect enters immediately. It can still queue its on-play trigger, and it does not open a summon-negate window.
- Life costs cannot reduce you below 1, and life does not rise above 30.
