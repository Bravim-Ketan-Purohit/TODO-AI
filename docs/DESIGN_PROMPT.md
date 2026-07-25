# Claude Design Prompt — TODO_AI

> Paste below the line into Claude Design. **Attach `DESIGN.md`** (the full design
> system) and, optionally, `spec.md` (the product spec).

---

Design a **minimal, native iOS + iPadOS app** called **TODO_AI**.

## What it is
An **AI-native day planner**. The user only types — any chat message becomes a
scheduled, color-coded event on their connected Google Calendar. The AI reads
existing events so it never double-books, asks before guessing unclear times, and
proposes a plan the user approves. The **calendar is the history, not the chat**.
Events are color-coded by **category** and by **completion status**.

## Design system
Use the attached **`DESIGN.md`** (Linear "midnight" — dark, near-black canvas,
Inter, a single acid-lime action, hairline borders over shadows). Apply it as a
**native mobile app, not a website**: no 1200px container, no top nav bar, no
48–72px hero type — mobile type sizes, a bottom tab bar, and iOS safe areas.

## Screens to design
- **Onboarding:** welcome · connect Google Calendar · role picker (Developer /
  Student) · daily-rhythm questions · role-specific questions
- **Chat** (home)
- **History** (30-day list of days → opens that day's calendar)
- **Settings**

## Before you design
**Ask me questions first** — about layout, hierarchy, the category color mapping,
components, navigation, and anything ambiguous — then design once we've aligned.
Don't assume; interview me.
