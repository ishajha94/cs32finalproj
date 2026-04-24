# 🍽️ HUDS Meal Planner

**CS32 Final Project — Harvard University**
Ana Marcela · Dino · Isha

---

## What It Does

The HUDS Meal Planner answers one question every Harvard student asks at 11:58am: *is it worth going to the dining hall today?*

You fill out a quick preference form — your house, favorite cuisines, proteins, dietary restrictions, and a spice slider — and we save it. The app then **automatically fetches today's live menu from the HUDS API**, scores every dish against your preferences, and gives you:

- A **go / skip verdict** with a reason
- Your **top matching dishes** highlighted
- **Personalized meal combo suggestions** (e.g. "Power Plate: grilled chicken + jasmine rice")
- A **thumbs up / thumbs down** button on each dish so your ratings improve future recommendations

No manual menu entry needed — it pulls from the real HUDS data automatically.

---

## How to Run It

### Prerequisites

- Python 3.x
- pip

### Setup

```bash
# 1. Clone the repo
git clone https://github.com/YOUR-USERNAME/huds-meal-planner.git
cd huds-meal-planner

# 2. Install dependencies
pip install -r requirements.txt

# 3. Run the app
python app.py
```

Then open your browser and go to: [http://127.0.0.1:5000](http://127.0.0.1:5000)

> **CS50 IDE note:** Run `flask run` instead of `python app.py`, and open the CS50 IDE browser preview.

---

## How It Works — The Pipeline

```
[Preference Form]  →  [preferences.json]  →  [HUDS API]  →  [Scoring]  →  [Suggestions]
    index.html          /save route          /dining/menus   score_menu()  build_suggestions()
```

1. **Preference Form** (`index.html`): User selects house, cuisines, proteins, restrictions, sliders. Saved to `preferences.json` via POST `/save`.

2. **HUDS API** (`app.py`, `/menu` route): Calls `https://api.cs50.io/dining/menus` with today's date and the user's house location. Then resolves each recipe ID via `/dining/recipes/{id}` to get the actual dish name. No API key required.

3. **Scoring** (`score_menu()`): Each dish gets +2 per cuisine keyword match, +2 per protein match, −5 per dietary restriction violation. Dishes the user previously liked get +1; disliked dishes get −3.

4. **Suggestions** (`build_suggestions()`): Buckets top-scoring dishes into proteins, carbs, and vegetables, then assembles 3 named combos (e.g. "Light & Balanced," "Today's Best") with a short reason.

5. **Like/Dislike feedback**: Clicking 👍 or 👎 on a dish updates `preferences.json` and improves future scores — a simple feedback loop.

---

## Project Structure

```
huds-meal-planner/
├── app.py                  # Flask backend: API calls, scoring, suggestions
├── preferences.json        # Saved user preferences (auto-generated)
├── requirements.txt        # Python dependencies
├── templates/
│   ├── index.html          # Preference form
│   └── results.html        # Live menu, verdict, suggestions
└── README.md
```

---

## New Concept: The CS50 Dining API

As a new skill for this project, we learned to use the **CS50 Dining API** (`https://api.cs50.io/dining/`), which provides live HUDS menu data over HTTP — no API key required. Key endpoints we use:

- `GET /dining/menus?location={id}&date={YYYY-MM-DD}` — today's menu items for a house
- `GET /dining/recipes/{id}` — recipe name and details for a given dish
- `GET /dining/locations` — list of all dining hall location IDs

This replaced our original approach (manually pasting in the menu), making the app fully automatic.

---

## What's Left

- [ ] Improve recipe name matching with fuzzy matching (`thefuzz` library) to handle typos and variations
- [ ] Add a history view showing go/skip decisions over the past week
- [ ] Let users rate dishes directly from past menus to build a richer taste profile
- [ ] Deploy to a public URL (e.g. via Render or Railway) so anyone at Harvard can use it

---

## Testing

We tested the app by:
- Submitting various preference combinations and verifying the correct JSON was written to `preferences.json`
- Hitting `/menu` directly and confirming dishes were returned and scored correctly
- Checking that a vegetarian user sees −5 for chicken dishes and that those dishes sort to the bottom
- Verifying the suggestions logic with sample menus where proteins, carbs, and vegetables were all present vs. absent

---

## External Contributors & Citations

- **CS50 Dining API** — `https://api.cs50.io/dining/` — live HUDS menu data
- **Flask** — Python web framework — `https://flask.palletsprojects.com`
- **Requests** — HTTP library for Python — `https://docs.python-requests.org`

### Use of Generative AI

We used Claude (Anthropic) to help with the following:
- Structuring the initial Flask route layout and suggesting the `/suggestions` endpoint
- Drafting the keyword maps used in `score_menu()` (we reviewed and extended them)
- CSS styling for the chip-select UI and results page layout

The project architecture, scoring rubric, suggestion logic, and all API integration code were written and reasoned through by the team. We reviewed, tested, and modified all AI-assisted code before including it.
