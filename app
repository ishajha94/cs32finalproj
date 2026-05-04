"""
HUDS Meal Planner — CS32 Final Project
Authors: Ana Marcela, Dino, Isha

Fetches today's menu live from the CS50 Dining API (no key required):
  https://api.cs50.io/dining/menus
  https://api.cs50.io/dining/recipes/{id}

New for final submission:
- Fuzzy string matching (thefuzz) replaces exact keyword matching
- Meal filtering by breakfast, lunch, and dinner
- Sample data fallback if the API returns nothing for today
"""

import json
import os
from datetime import date

import requests
from flask import Flask, jsonify, render_template, request
from thefuzz import fuzz

app = Flask(__name__)

PREFERENCES_FILE = "preferences.json"
HUDS_BASE        = "https://api.cs50.io/dining"
DEFAULT_LOCATION = 7   # Dunster & Mather

# Sample fallback menu
# Used when the HUDS API returns no items
SAMPLE_MENU = [
    {"id": 1,  "name": "grilled chicken breast",  "meal": "lunch",    "category": "proteins"},
    {"id": 2,  "name": "pasta primavera",          "meal": "lunch",    "category": "pasta"},
    {"id": 3,  "name": "caesar salad",             "meal": "lunch",    "category": "salads"},
    {"id": 4,  "name": "beef stir fry with rice",  "meal": "dinner",   "category": "entrees"},
    {"id": 5,  "name": "vegetable fried rice",     "meal": "dinner",   "category": "sides"},
    {"id": 6,  "name": "salmon fillet",            "meal": "dinner",   "category": "proteins"},
    {"id": 7,  "name": "scrambled eggs",           "meal": "breakfast","category": "proteins"},
    {"id": 8,  "name": "french toast",             "meal": "breakfast","category": "bread"},
    {"id": 9,  "name": "oatmeal",                  "meal": "breakfast","category": "grains"},
    {"id": 10, "name": "tomato soup",              "meal": "lunch",    "category": "soups"},
    {"id": 11, "name": "cheese quesadilla",        "meal": "lunch",    "category": "entrees"},
    {"id": 12, "name": "roasted broccoli",         "meal": "dinner",   "category": "vegetables"},
    {"id": 13, "name": "pork carnitas",            "meal": "dinner",   "category": "proteins"},
    {"id": 14, "name": "hummus and pita",          "meal": "lunch",    "category": "sides"},
    {"id": 15, "name": "chicken tikka masala",     "meal": "dinner",   "category": "entrees"},
]


#  Routes

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/results")
def results():
    return render_template("results.html")


@app.route("/save", methods=["POST"])
def save():
    """
    Receive preference form data and save it to preferences.json.
    Returns the saved dict so the frontend can display it as confirmation.
    """
    data = request.get_json()

    prefs = {
        "name":         data.get("name", ""),
        "location_id":  int(data.get("location_id", DEFAULT_LOCATION)),
        "cuisines":     data.get("cuisines", []),
        "proteins":     data.get("proteins", []),
        "sides":        data.get("sides", []),
        "restrictions": data.get("restrictions", []),
        "spice_level":  int(data.get("spice_level", 3)),
        "adventurous":  int(data.get("adventurous", 3)),
        "liked_ids":    data.get("liked_ids", []),
        "disliked_ids": data.get("disliked_ids", []),
    }

    with open(PREFERENCES_FILE, "w") as f:
        json.dump(prefs, f, indent=2)

    return jsonify({"status": "saved", "preferences": prefs})


@app.route("/menu")
def get_menu():
    """
    Fetch today's menu from the HUDS API for the user's dining hall.
    Supports optional meal=breakfast|lunch|dinner filtering.
    Falls back to sample data if the API returns nothing.
    """
    prefs       = load_prefs()
    location_id = prefs.get("location_id", DEFAULT_LOCATION)
    meal_filter = request.args.get("meal", "").lower()
    today       = date.today().isoformat()

    # Try the live HUDS API first
    dishes       = fetch_dishes(location_id, today)
    using_sample = False

    # Fall back to sample menu if API returned nothing
    if not dishes:
        dishes       = SAMPLE_MENU
        using_sample = True

    # Filter by meal if requested
    if meal_filter and meal_filter != "all":
        dishes = [d for d in dishes if d.get("meal", "").lower() == meal_filter]

    # Score every dish against user preferences using fuzzy matching
    scored  = score_menu(dishes, prefs)
    verdict = recommend(scored)

    return jsonify({
        "date":         today,
        "meal":         meal_filter or "all",
        "dishes":       scored,
        "verdict":      verdict,
        "using_sample": using_sample,
    })


@app.route("/suggestions")
def suggestions():
    """
    Generate personalised meal combo suggestions from today's
    highest-scoring dishes.
    """
    prefs       = load_prefs()
    location_id = prefs.get("location_id", DEFAULT_LOCATION)
    today       = date.today().isoformat()

    dishes = fetch_dishes(location_id, today)
    if not dishes:
        dishes = SAMPLE_MENU

    scored = score_menu(dishes, prefs)
    combos = build_suggestions(scored)

    return jsonify({"suggestions": combos})


#  HUDS API helpers

def fetch_dishes(location_id, today):
    """
    Call the CS50 Dining API and resolve recipe IDs to dish names.
    The /menus endpoint only returns recipe IDs, so we make a second
    call to /recipes/{id} for each unique dish to get the actual name.
    Returns a list of dish dicts, or empty list on any failure.
    """
    try:
        resp = requests.get(
            f"{HUDS_BASE}/menus",
            params={"location": location_id, "date": today},
            timeout=8,
        )
        resp.raise_for_status()
        menu_items = resp.json()
    except Exception:
        return []

    if not menu_items:
        return []

    # Collect unique recipe IDs to avoid duplicate API calls
    unique_ids = {item["recipe"] for item in menu_items}
    recipe_map = {}

    for rid in unique_ids:
        try:
            r = requests.get(f"{HUDS_BASE}/recipes/{rid}", timeout=5)
            if r.status_code == 200:
                recipe_map[rid] = r.json().get("name", f"Recipe {rid}")
        except Exception:
            recipe_map[rid] = f"Recipe {rid}"

    dishes = []
    for item in menu_items:
        rid = item["recipe"]
        dishes.append({
            "id":       rid,
            "name":     recipe_map.get(rid, f"Recipe {rid}").lower(),
            "meal":     item.get("meal", ""),
            "category": item.get("category", ""),
        })

    return dishes


def load_prefs():
    """Load saved preferences from disk, returning empty dict if not found."""
    if os.path.exists(PREFERENCES_FILE):
        with open(PREFERENCES_FILE) as f:
            return json.load(f)
    return {}


#  Fuzzy Matching & Scoring

# Reference terms for each preference category.
# We use fuzzy matching so "chkn tikka" still matches "chicken tikka masala"
CUISINE_TERMS = {
    "american":      ["burger", "mac and cheese", "bbq", "meatloaf", "grilled cheese", "chili"],
    "italian":       ["pasta", "pizza", "lasagna", "risotto", "gnocchi", "marinara", "pesto"],
    "mexican":       ["taco", "burrito", "quesadilla", "enchilada", "fajita", "carnitas"],
    "asian":         ["stir fry", "fried rice", "noodle", "dumpling", "ramen", "teriyaki", "miso"],
    "mediterranean": ["hummus", "falafel", "shawarma", "pita", "tzatziki", "couscous", "kebab"],
    "indian":        ["curry", "tikka", "dal", "naan", "biryani", "masala", "paneer", "samosa"],
}

PROTEIN_TERMS = {
    "chicken": ["chicken"],
    "beef":    ["beef", "steak", "burger", "brisket"],
    "fish":    ["fish", "salmon", "cod", "tilapia", "tuna", "shrimp"],
    "pork":    ["pork", "bacon", "ham", "sausage"],
    "tofu":    ["tofu"],
    "eggs":    ["egg", "eggs", "omelette", "frittata"],
}

RESTRICTION_TERMS = {
    "vegetarian":  ["chicken", "beef", "fish", "pork", "bacon", "ham", "sausage", "meat", "turkey"],
    "vegan":       ["chicken", "beef", "fish", "pork", "cheese", "milk", "egg", "butter", "cream"],
    "gluten-free": ["pasta", "bread", "wheat", "flour", "noodle", "pizza", "wrap"],
    "halal":       ["pork", "bacon", "ham"],
    "kosher":      ["pork", "bacon", "ham", "shrimp", "shellfish"],
}

# Minimum fuzzy similarity score to count as a match (0-100).
# 75 is loose enough to catch typos and partial names, tight enough
# to avoid false positives like "rice" matching "licorice".
FUZZY_THRESHOLD = 75


def fuzzy_matches(dish_name, terms):
    """
    Return True if any term in the list fuzzy-matches the dish name
    above the threshold. Uses partial_ratio so "chicken" matches
    "herb roasted chicken thigh" even though it's not the full string.
    """
    for term in terms:
        if fuzz.partial_ratio(term, dish_name) >= FUZZY_THRESHOLD:
            return True
    return False


def score_menu(dishes, prefs):
    """
    Score each dish against the user's saved preferences.

    Scoring:
      +2  for each cuisine category match (fuzzy)
      +2  for each protein match (fuzzy)
      -5  for each dietary restriction violation (fuzzy) — hard penalty
      +1  if the user previously liked this dish (by recipe ID)
      -3  if the user previously disliked this dish

    Dishes are returned sorted best-first.
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

        # Cuisine bonus
        for cuisine in cuisines:
            if fuzzy_matches(name, CUISINE_TERMS.get(cuisine, [])):
                score += 2

        # Protein bonus
        for protein in proteins:
            if fuzzy_matches(name, PROTEIN_TERMS.get(protein, [protein])):
                score += 2

        # Override positive matches
        for restriction in restrictions:
            if fuzzy_matches(name, RESTRICTION_TERMS.get(restriction, [])):
                score -= 5

        # Personal history bonus/penalty
        if dish["id"] in liked_ids:
            score += 1
        if dish["id"] in disliked_ids:
            score -= 3

        scored.append({**dish, "score": score, "match": score > 0})

    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored


def recommend(scored):
    """
    Produce a go/skip verdict from the scored dish list.
    """
    top_picks   = [d["name"] for d in scored if d["match"]]
    match_count = len(top_picks)

    if match_count >= 3:
        return {
            "verdict":   "go",
            "message":   f"{match_count} of your favorites are on the menu — definitely worth going!",
            "top_picks": top_picks[:5],
        }
    elif match_count >= 1:
        return {
            "verdict":   "go",
            "message":   f"{match_count} dish(es) you like are being served. Might be worth a trip.",
            "top_picks": top_picks[:5],
        }
    else:
        return {
            "verdict":   "skip",
            "message":   "Nothing matches your preferences today. Might be a good day to eat out.",
            "top_picks": [],
        }


#  Meal Suggestions

def build_suggestions(scored):
    """
    Build up to 3 named meal combo suggestions from today's top-scoring dishes.
    Buckets dishes into proteins, carbs, and vegetables, then assembles recommendations.
    """
    def is_protein(name):
        return fuzzy_matches(name, [kw for kws in PROTEIN_TERMS.values() for kw in kws])

    def is_carb(name):
        return fuzzy_matches(name, ["rice", "pasta", "bread", "noodle",
                                     "potato", "fries", "roll", "wrap", "quinoa", "oatmeal"])

    def is_veggie(name):
        return fuzzy_matches(name, ["salad", "vegetable", "broccoli", "spinach",
                                     "kale", "carrot", "zucchini", "squash", "greens"])

    proteins = [d for d in scored if d["match"] and is_protein(d["name"])]
    carbs    = [d for d in scored if d["match"] and is_carb(d["name"])]
    veggies  = [d for d in scored if d["match"] and is_veggie(d["name"])]
    combos   = []

    # Combo 1: protein + carb
    if proteins and carbs:
        combos.append({
            "title":      "Power Plate",
            "components": [proteins[0]["name"], carbs[0]["name"]],
            "reason":     "Your top protein pick paired with a carb you like.",
        })

    # Combo 2: protein + veggie
    if proteins and veggies:
        combos.append({
            "title":      "Light & Balanced",
            "components": [proteins[0]["name"], veggies[0]["name"]],
            "reason":     "A lighter combo that still hits your preferences.",
        })

    # Combo 3: top 3 highest-scoring dishes regardless of category
    top3 = [d["name"] for d in scored if d["match"]][:3]
    if len(top3) >= 2:
        combos.append({
            "title":      "Today's Best",
            "components": top3,
            "reason":     "The highest-scoring dishes on the menu today.",
        })

    # Fallback: if nothing scored positively, show the least-bad options
    if not combos:
        combos.append({
            "title":      "Best Available",
            "components": [d["name"] for d in scored[:3]],
            "reason":     "Not your usual favorites, but the closest matches today.",
        })

    return combos[:3]


# ═══════════════════════════════════════════════════════════════════════════════

if __name__ == "__main__":
    app.run(debug=True)

