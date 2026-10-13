from etl.derive import taxonomy as t


def classify(**kw):
    base = dict(protein=None, fat=None, carbs=None, fiber=None, sugars=None, starch=None)
    base.update(kw)
    return t.macro_dominant(**base)


def test_honey_like_profile_is_carb_sugar():
    assert classify(protein=0.3, fat=0.0, carbs=82.4, fiber=0.2, sugars=82.1) == "carb_sugar"


def test_chia_like_profile_is_fiber():
    assert classify(protein=16.5, fat=30.7, carbs=42.1, fiber=34.4) == "fiber"


def test_fiber_threshold_is_15_g():
    assert classify(protein=1, fat=1, carbs=40, fiber=14.9, sugars=1, starch=20) == "carb_starch"
    assert classify(protein=1, fat=1, carbs=40, fiber=15.0, sugars=1, starch=20) == "fiber"


def test_protein_and_fat_dominance():
    assert classify(protein=22.5, fat=2.6, carbs=0.0) == "protein"
    assert classify(protein=25.8, fat=49.2, carbs=16.1, fiber=8.5, sugars=4.7) == "fat"


def test_no_majority_is_mixed():
    assert classify(protein=3.2, fat=3.3, carbs=4.8, fiber=0, sugars=4.8) == "mixed"


def test_sugar_versus_starch():
    assert classify(protein=1, fat=0.3, carbs=23, fiber=2.6, sugars=12.2, starch=5.4) == "carb_sugar"
    assert classify(protein=2, fat=0.3, carbs=28, fiber=0.4, sugars=0.1) == "carb_starch"
    assert classify(protein=2, fat=0.3, carbs=28, fiber=0.4, starch=25) == "carb_starch"


def test_unknown_sugar_and_starch_is_mixed_not_guessed():
    # Plantains keep sugars/starch NULL until an analytical source exists.
    assert classify(protein=1.3, fat=0.4, carbs=32, fiber=2.3) == "mixed"


def test_missing_macros_are_not_zero():
    assert classify() == "mixed"
    assert classify(protein=20) == "protein"


def test_food_group_and_iron_flags():
    assert t.food_group_es("Legumes and Legume Products") == "Leguminosas"
    assert t.food_group_es(None) == "Sin grupo"
    assert t.iron_heme("Beef Products") == 1
    assert t.iron_heme("Legumes and Legume Products") == 0
    assert t.iron_heme("Fast Foods") is None


def test_polyphenol_inhibitors():
    assert t.inhibits_nonheme_iron("Beverages, coffee, brewed, prepared with tap water") == 1
    assert t.inhibits_nonheme_iron("Beverages, tea, black, brewed") == 1
    assert t.inhibits_nonheme_iron("Beef, steak, raw") == 0
    assert t.inhibits_nonheme_iron("Spices, teaspoon size") == 0


def test_allergens_from_name():
    assert t.allergens("Peanuts, all types, raw") == "maní"
    assert t.allergens("Milk, whole, 3.25% milkfat") == "leche"
    assert t.allergens("Fish, tilapia, raw") == "pescado"
    assert t.allergens("Bananas, raw") is None


def test_notes():
    assert "fitohemaglutinina" in t.antinutrient_note("Beans, kidney, red, mature seeds, raw")
    assert "cianog" in t.antinutrient_note("Cassava, raw")
    assert t.resistant_starch_note("Plantains, green, raw") is not None


def test_limiting_amino_acid_uses_fao_pattern():
    # Synthetic cereal-like profile with low lysine (grams per 100 g food, 10 g protein).
    aa = {1210: 0.12, 1211: 0.30, 1212: 0.35, 1213: 0.75, 1214: 0.25, 1215: 0.18, 1216: 0.20,
          1217: 0.45, 1218: 0.30, 1219: 0.45, 1221: 0.22}
    nutrients = {1003: 10.0, **aa}
    assert t.limiting_amino_acid(nutrients) == "Lisina"
    complete = {**nutrients, 1214: 0.6}
    assert t.limiting_amino_acid(complete) is None
    assert t.limiting_amino_acid({1003: 10.0}) is None


def test_fat_energy_share_and_confidence():
    assert t.fat_energy_share({1004: 10.0}, 180.0) == 0.5
    assert t.fat_energy_share({}, 100.0) is None
    assert t.confidence({1003: 1, 1004: 1, 1005: 1}, nrf_missing=2, proxy=False) == "alta"
    assert t.confidence({1003: 1, 1004: 1, 1005: 1}, nrf_missing=8, proxy=False) == "media"
    assert t.confidence({1003: 1, 1005: 1}, nrf_missing=0, proxy=False) == "baja"
    assert t.confidence({1003: 1, 1004: 1, 1005: 1}, nrf_missing=0, proxy=True) == "baja"
