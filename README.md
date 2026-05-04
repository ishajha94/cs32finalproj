# 🍽️ HUDS Meal Planner

**CS32 Final Project - Harvard University**
Ana Marcela, Dino, Isha

## What It Does

The HUDS Meal Planner answers one question every Harvard student asks at 11:58am: *is it worth going to the dining hall today?*

You fill out a quick preference form — your house, favorite cuisines, proteins, and dietary restrictions — and the app automatically fetches today's live HUDS menu, scores every dish against your preferences using **fuzzy string matching**, and gives you:

- A **go / skip verdict** with a reason
- Your **top matching dishes** highlighted
- **Personalized meal combo suggestions** (e.g. "Power Plate: grilled chicken + jasmine rice")
- A **breakfast / lunch / dinner filter** to see only the meal you care about

No manual menu entry needed — it pulls from real HUDS data automatically.

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
flask run
```

Then open the URL printed in the terminal (e.g. `https://your-codespace-5000.app.github.dev`).

---

## Project Structure

```
huds-meal-planner/
├── app.py                  # Flask backend: API calls, fuzzy scoring, suggestions
├── preferences.json        # Auto-generated when you save preferences
├── requirements.txt        # Python dependencies
├── templates/
│   ├── index.html          # Preference form
│   └── results.html        # Live menu, verdict, suggestions
└── README.md
```

---

## How It Works — The Pipeline

```
[Preference Form] → [preferences.json] → [HUDS API] → [Fuzzy Scoring] → [Suggestions]
    index.html         /save route       /dining/menus   score_menu()   build_suggestions()
```

1. **Preference Form** (`index.html`): User selects house, cuisines, proteins, restrictions, and sliders. Saved via POST to `/save`.
2. **HUDS API** (`fetch_dishes()` in `app.py`): Calls `https://api.cs50.io/dining/menus` with today's date and the user's house location ID. Resolves each recipe ID via `/dining/recipes/{id}`. No API key required.
3. **Fuzzy Scoring** (`score_menu()`): Uses the `thefuzz` library to compare each dish name against preference keywords. `partial_ratio` scoring means "herb roasted chicken thigh" still matches "chicken" — no exact substring needed. Dishes score +2 per cuisine/protein match, −5 per restriction violation.
4. **Suggestions** (`build_suggestions()`): Buckets top-scoring dishes into proteins, carbs, and vegetables, then assembles named combos.
5. **Fallback**: If the HUDS API returns no data (weekend, holiday, outage), the app falls back to a built-in sample menu so the app always works.

---

## New Concepts Learned

- **CS50 Dining API** (`https://api.cs50.io/dining/`) — live HUDS menu data over HTTP, no key required
- **Fuzzy string matching** (`thefuzz` library) — `fuzz.partial_ratio()` lets us match dish names that contain a keyword anywhere in the string, and handles minor spelling variations

---

## Testing

We tested by:
- Submitting different preference combinations and verifying `preferences.json` was saved correctly
- Confirming vegetarian users see −5 scores for meat dishes, which sort to the bottom
- Testing the fuzzy threshold: "chiken" (typo) scores above 75 and matches chicken dishes; "rice" does not falsely match "licorice"
- Testing the fallback by temporarily disconnecting from the API and confirming sample data appeared
- Testing meal filtering: selecting "dinner" returns only dinner dishes

---

## What's Next

- Caching the day's menu locally so we don't re-fetch on every page load
- A history view showing your go/skip decisions over the past week
- Public deployment so any Harvard student can use it without running locally

---

## External Contributors & Citations

- **CS50 Dining API** — `https://api.cs50.io/dining/`
- **Flask** — `https://flask.palletsprojects.com`
- **Requests** — `https://docs.python-requests.org`
- **thefuzz** — `https://github.com/seatgeek/thefuzz`

### Use of Generative AI

We used Claude (Anthropic) throughout this project to help with:
- Structuring the Flask app's route layout and suggesting the `/suggestions` endpoint
- Drafting the initial keyword/term lists used in `score_menu()`
- CSS styling for the chip-select UI and results page layout
- Debugging the `TemplateNotFound` error during setup

The project architecture, scoring rubric, fuzzy matching integration, suggestion logic, and all API integration were written and reasoned through by the team. We reviewed, tested, and modified all AI-assisted code before including it.

