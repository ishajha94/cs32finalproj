"""
HUDS Meal Planner — CS32 Final Project
Authors: Ana Marcela, Dino, Isha

Fetches today's menu live from the CS50 Dining API (no key required):
  https://api.cs50.io/dining/menus
  https://api.cs50.io/dining/locations
  https://api.cs50.io/dining/recipes/{id}

Routes:
  GET  /              → preference form
  POST /save          → save preferences to preferences.json
  GET  /menu          → fetch today's menu from HUDS API + score it
  GET  /suggestions   → return personalised meal combo suggestions
  GET  /results       → results page (rendered by JS)
"""

import json
import os
from datetime import date

import requests
from flask import Flask, jsonify, render_template, request

app = Flask(__name__)

PREFERENCES_FILE = "preferences.json"
HUDS_BASE        = "https://api.cs50.io/dining"

# Location ID for the user's house (default: Dunster/Mather = 7)
# Students can change this to their own house ID.
DEFAULT_LOCATION = 7


# ═══════════════════════════════════════════════════════════════════════════════
#  Routes
# ═══════════════════════════════════════════════════════════════════════════════

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/results")
def results():
    return render_template("results.html")


@app.route("/save", methods=["POST"])
def save():
    """
    Receive preference form data from the frontend and persist it.
    Returns the saved dict so the frontend can display it as confirmation.
    """
    data = request.get_json()

    preferences = {
        "name":         data.get("name", ""),
        "location_id":  int(data.get("location_id", DEFAULT_LOCATION)),
        "cuisines":     data.get("cuisines", []),
        "proteins":     data.get("proteins", []),
        "sides":        data.get("sides", []),
        "restrictions": data.get("restrictions", []),
        "spice_level":  int(data.get("spice_level", 3)),
        "adventurous":  int(data.get("adventurous", 3)),
        # Liked/disliked recipe IDs collected over time (for suggestions)
        "liked_ids":    data.get("liked_ids", []),
        "disliked_ids": data.get("disliked_ids", []),
    }

    with open(PREFERENCES_FILE, "w") as f:
        json.dump(preferences, f, indent=2)

    return jsonify({"status": "saved", "preferences": preferences})


@app.route("/menu")
def get_menu():
    """
    Fetch today's menu from the HUDS API for the user's location,
    score every dish, and return a go/skip verdict plus top picks.

    Query param:
      meal  (optional) — "breakfast", "lunch", or "dinner"
              If omitted, returns all meals.
    """
    prefs       = _load_prefs()
    location_id = prefs.get("location_id", DEFAULT_LOCATION)
    meal_filter = request.args.get("meal", "").lower()

    # ── 1. Fetch today's menu from the HUDS API ───────────────────────────────
    today    = date.today().isoformat()          # e.g. "2025-04-08"
    menu_url = f"{HUDS_BASE}/menus"
    params   = {"location": location_id, "date": today}
    if meal_filter:
        # API accepts meal names directly as a filter
        params["meal"] = meal_filter

    try:
        resp = requests.get(menu_url, params=params, timeout=8)
        resp.raise_for_status()
        menu_items = resp.json()   # list of menu objects
    except requests.RequestException as e:
        return jsonify({"error": f"Could not reach HUDS API: {e}"}), 502

    # ── 2. Resolve recipe names (the menu item only has a recipe id) ──────────
    dishes = _resolve_recipes(menu_items)

    # ── 3. Score dishes against user preferences ──────────────────────────────
    scored  = score_menu(dishes, prefs)
    verdict = recommend(scored)

    return jsonify({
        "date":    today,
        "meal":    meal_filter or "all",
        "dishes":  scored,
        "verdict": verdict,
    })


@app.route("/suggestions")
def suggestions():
    """
    Generate personalised meal combo suggestions based on:
      - The user's saved preference keywords
      - Dishes available in today's menu that scored positively

    Returns up to 3 suggested meal combos, each with a name,
    component dishes, and a short reason.
    """
    prefs       = _load_prefs()
    location_id = prefs.get("location_id", DEFAULT_LOCATION)
    today       = date.today().isoformat()

    try:
        resp = requests.get(
            f"{HUDS_BASE}/menus",
            params={"location": location_id, "date": today},
            timeout=8,
        )
        resp.raise_for_status()
        menu_items = resp.json()
    except requests.RequestException as e:
        return jsonify({"error": f"Could not reach HUDS API: {e}"}), 502

    dishes  = _resolve_recipes(menu_items)
    scored  = score_menu(dishes, prefs)
    combos  = build_suggestions(scored, prefs)

    return jsonify({"suggestions": combos})


# ═══════════════════════════════════════════════════════════════════════════════
#  HUDS API helpers
# ═══════════════════════════════════════════════════════════════════════════════

def _resolve_recipes(menu_items):
    """
    The /menus endpoint returns objects like:
      { "recipe": 22011, "category": 32, "meal": 1, "location": 7 }

    This function fetches the recipe name for each unique recipe ID
    and returns a list of dicts ready for scoring:
      { "id": 22011, "name": "grilled chicken", "meal": 1, "category": 32 }

    We batch unique IDs to avoid redundant requests.
    """
    unique_ids = {item["recipe"] for item in menu_items}
    recipe_map = {}

    for rid in unique_ids:
        try:
            r = requests.get(f"{HUDS_BASE}/recipes/{rid}", timeout=5)
            if r.status_code == 200:
                recipe_map[rid] = r.json().get("name", f"Recipe {rid}")
        except requests.RequestException:
            recipe_map[rid] = f"Recipe {rid}"

    dishes = []
    for item in menu_items:
        rid  = item["recipe"]
        name = recipe_map.get(rid, f"Recipe {rid}").lower()
        dishes.append({
            "id":       rid,
            "name":     name,
            "meal":     item.get("meal"),
            "category": item.get("category"),
        })
    return dishes


def _load_prefs():
    """Load saved preferences, returning an empty dict if not yet saved."""
    if os.path.exists(PREFERENCES_FILE):
        with open(PREFERENCES_FILE) as f:
            return json.load(f)
    return {}


# ═══════════════════════════════════════════════════════════════════════════════
#  Scoring — keyword maps
# ═══════════════════════════════════════════════════════════════════════════════

CUISINE_KEYWORDS = {
    "american":      ["burger", "mac", "bbq", "meatloaf", "sandwich",
                      "grilled cheese", "hot dog", "chili"],
    "italian":       ["pasta", "pizza", "lasagna", "risotto", "gnocchi",
                      "marinara", "pesto", "parmesan"],
    "mexican":       ["taco", "burrito", "quesadilla", "enchilada",
                      "salsa", "guacamole", "fajita", "carnitas"],
    "asian":         ["stir fry", "fried rice", "noodle", "dumpling",
                      "ramen", "soy", "teriyaki", "miso", "lo mein"],
    "mediterranean": ["hummus", "falafel", "shawarma", "pita",
                      "tzatziki", "couscous", "kebab", "tahini"],
    "indian":        ["curry", "tikka", "dal", "naan", "samosa",
                      "biryani", "masala", "chutney", "paneer"],
}

PROTEIN_KEYWORDS = {
    "chicken": ["chicken"],
    "beef":    ["beef", "steak", "burger", "brisket"],
    "fish":    ["fish", "salmon", "cod", "tilapia", "tuna", "shrimp"],
    "pork":    ["pork", "bacon", "ham", "sausage"],
    "tofu":    ["tofu"],
    "eggs":    ["egg", "omelette", "frittata", "quiche"],
}

RESTRICTION_EXCLUDE = {
    "vegetarian":  ["chicken", "beef", "fish", "pork", "bacon",
                    "ham", "sausage", "meat", "turkey"],
    "vegan":       ["chicken", "beef", "fish", "pork", "dairy",
                    "cheese", "milk", "egg", "butter", "cream"],
    "gluten-free": ["pasta", "bread", "wheat", "flour",
                    "noodle", "pizza", "wrap", "roll"],
    "halal":       ["pork", "bacon", "ham"],
    "kosher":      ["pork", "bacon", "ham", "shellfish", "shrimp"],
}


def score_menu(dishes, prefs):
    """
    Score each dish against the user's preferences.

    Points:
      +2  for each cuisine keyword match
      +2  for each protein match
      +1  if previously liked (by recipe ID)
      -5  for each dietary restriction violation
      -3  if previously disliked

    Returns a sorted list of scored dish dicts.
    """
    cuisines     = [c.lower() for c in prefs.get("cuisines", [])]
    proteins     = [p.lower() for p in prefs.get("proteins", [])]
    restrictions = [r.lower() for r in prefs.get("restrictions", [])]
    liked_ids    = set(prefs.get("liked_ids", []))
    disliked_ids = set(prefs.get("disliked_ids", []))

    scored = []
    for dish in dishes:
        name  = dish["name"]
        score = 0

        for cuisine in cuisines:
            if any(kw in name for kw in CUISINE_KEYWORDS.get(cuisine, [])):
                score += 2

        for protein in proteins:
            if any(kw in name for kw in PROTEIN_KEYWORDS.get(protein, [protein])):
                score += 2

        for restriction in restrictions:
            if any(w in name for w in RESTRICTION_EXCLUDE.get(restriction, [])):
                score -= 5

        if dish["id"] in liked_ids:
            score += 1
        if dish["id"] in disliked_ids:
            score -= 3

        scored.append({**dish, "score": score, "match": score > 0})

    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored


def recommend(scored_dishes):
    """
    Produce a human-readable go/skip recommendation from scored dishes.
    """
    top_picks   = [d["name"] for d in scored_dishes if d["match"]]
    match_count = len(top_picks)

    if match_count >= 3:
        verdict, message = "go", (
            f"{match_count} of your favorites are on the menu — definitely worth going!"
        )
    elif match_count >= 1:
        verdict, message = "go", (
            f"{match_count} dish(es) you like are being served. Might be worth a trip."
        )
    else:
        verdict, message = "skip", (
            "Nothing matches your preferences today. Might be a good day to eat out."
        )

    return {
        "verdict":   verdict,
        "message":   message,
        "top_picks": top_picks[:5],
    }


# ═══════════════════════════════════════════════════════════════════════════════
#  Meal Suggestions
# ═══════════════════════════════════════════════════════════════════════════════

def build_suggestions(scored_dishes, prefs):
    """
    Build up to 3 personalised meal combo suggestions from today's menu.

    A suggestion is a curated combination of dishes (protein + side + extra)
    pulled from the highest-scoring items, with a short reason string.

    Design decision: we bucket dishes by category concept (protein, carb,
    vegetable, dessert) using simple keyword heuristics, then assemble
    combos that hit the user's top preferences.
    """
    proteins  = [d for d in scored_dishes if d["match"] and _is_protein(d["name"])]
    carbs     = [d for d in scored_dishes if d["match"] and _is_carb(d["name"])]
    veggies   = [d for d in scored_dishes if d["match"] and _is_veggie(d["name"])]
    extras    = [d for d in scored_dishes if d["match"]
                 and not _is_protein(d["name"])
                 and not _is_carb(d["name"])
                 and not _is_veggie(d["name"])]

    combos = []

    # Combo 1: best protein + best carb
    if proteins and carbs:
        combos.append({
            "title":      "Power Plate",
            "components": [proteins[0]["name"], carbs[0]["name"]],
            "reason":     f"Your top protein pick paired with a carb you like.",
        })

    # Combo 2: protein + veggie (lighter option)
    if proteins and veggies:
        combos.append({
            "title":      "Light & Balanced",
            "components": [proteins[0]["name"], veggies[0]["name"]],
            "reason":     "A lighter combo that matches your preferences.",
        })

    # Combo 3: top 3 highest-scoring dishes regardless of category
    top3 = [d["name"] for d in scored_dishes if d["match"]][:3]
    if len(top3) >= 2:
        combos.append({
            "title":      "Today's Best",
            "components": top3,
            "reason":     "The highest-scoring dishes on the menu today.",
        })

    # If nothing scored positively, suggest the least-bad options
    if not combos:
        fallback = [d["name"] for d in scored_dishes[:3]]
        combos.append({
            "title":      "Best Available",
            "components": fallback,
            "reason":     "Not your usual favorites, but the closest matches today.",
        })

    return combos[:3]


# Simple keyword bucketing helpers for suggestion building
def _is_protein(name):
    return any(kw in name for kws in PROTEIN_KEYWORDS.values() for kw in kws)

def _is_carb(name):
    carb_words = ["rice", "pasta", "bread", "noodle", "potato", "fries",
                  "roll", "wrap", "quinoa", "grain"]
    return any(w in name for w in carb_words)

def _is_veggie(name):
    veggie_words = ["salad", "vegetable", "broccoli", "spinach", "kale",
                    "carrot", "zucchini", "squash", "roasted veg", "greens"]
    return any(w in name for w in veggie_words)


# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    app.run(debug=True)
