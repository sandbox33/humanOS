from etl.derive import nova_rules as n


def test_peanut_butter_with_hydrogenated_oil_is_nova_4():
    nova, reason = n.classify_ingredients("Maní, aceite vegetal hidrogenado, azúcar, sal")
    assert nova == 4
    assert "hidrogenad" in reason


def test_pure_peanut_is_nova_1():
    assert n.classify_ingredients("maní 100%")[0] == 1
    assert n.classify_ingredients("Ingredientes: Maní tostado.")[0] == 1


def test_single_culinary_ingredient_is_nova_2():
    assert n.classify_ingredients("Sal")[0] == 2
    assert n.classify_ingredients("aceite de oliva")[0] == 2


def test_markers():
    for text in (
        "azúcar, jarabe de maíz de alta fructosa",
        "leche, maltodextrina",
        "cacao, emulsionante (E471)",
        "chocolate, lecitina de soya",
        "agua, sucralosa",
        "agua, edulcorantes: acesulfame K",
        "harina, saborizante artificial",
        "harina, aroma de vainilla",
        "water, high fructose corn syrup",
        "sugar, natural flavor",
        "azúcar, INS 322",
    ):
        assert n.classify_ingredients(text)[0] == 4, text


def test_no_false_positive_on_aromatic_herbs():
    nova, _ = n.classify_ingredients("tomate, cebolla, hierbas aromáticas")
    assert nova is None


def test_unknown_without_evidence():
    assert n.classify_ingredients("harina de trigo, agua, sal")[0] is None
    assert n.classify_ingredients(None)[0] is None
    assert n.classify_ingredients("   ")[0] is None


def test_split_respects_parentheses():
    parts = n.split_ingredients("chocolate (cacao, azúcar), leche; sal")
    assert parts == ["chocolate (cacao, azucar)", "leche", "sal"]


def test_fdc_plain_foods():
    assert n.classify_fdc_food("Bananas, raw", "Fruits and Fruit Juices") == 1
    assert n.classify_fdc_food("Lentils, mature seeds, cooked, boiled, without salt",
                               "Legumes and Legume Products") == 1
    assert n.classify_fdc_food("Peaches, canned, heavy syrup pack", "Fruits and Fruit Juices") is None
    assert n.classify_fdc_food("Cookies, chocolate chip", "Baked Products") is None
