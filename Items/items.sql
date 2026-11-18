-- cv_kasippu_system items for vorp_inventory (`items` table).
-- INSERT IGNORE skips any item that already exists, so it is safe to run again.
-- `id` is left out on purpose: the database gives each row its own id, so nothing clashes with items you already have.
-- Item pictures: copy Items/Images/*.png to vorp_inventory/html/img/items/

INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`, `groupId`, `rarityId`, `metadata`, `desc`, `degradation`, `weight`, `durability`, `instructions`) VALUES
    -- Tools and containers
    ('climb_rope',            'Pol Walalla',        1,   1, 'item_standard', 1, 1, 1, '{}', 'nice item', 0, 0.15, NULL, NULL),
    ('empty_pot',             'Muttiya',            10,  1, 'item_standard', 1, 1, 1, '{}', 'A clay pot for coconut flower sap. Take it up a coconut tree to fill it. Holds up to 1000ml.', 0, 0.15, NULL, NULL),
    ('filled_pot',            'Coconut Flower Sap', 10,  1, 'item_standard', 1, 1, 1, '{}', 'A pot of fresh coconut flower sap. Bring a full pot (1000ml) to your still for Pol Raa.', 0, 0.50, NULL, NULL),
    ('kassippu_barrel_kit',   'Kassippu Barrel',    10,  1, 'item_standard', 1, 1, 1, '{}', 'nice item', 0, 0.25, NULL, NULL),
    ('barrel_repair_kit',     'Barrel Repair Kit',  3,   1, 'item_standard', 0, 1, 1, '{}', 'Mends a worn still. Several uses.', 0, 0.15, NULL, NULL),
    ('kassippu_aging_crate',  'Aging Crate',        5,   1, 'item_standard', 1, 1, 1, '{}', 'A wooden crate that holds 12 bottles. Set it down and leave bottles in it to age into Rested, Mellow and Fine.', 0, 1.00, NULL, NULL),
    ('empty_bottle',          'Empty Bottle',       15,  1, 'item_standard', 1, 1, 1, '{}', 'Empty Bottle', 0, 0.15, NULL, NULL),
    ('lockpick',              'Lockpick',           5,   1, 'item_standard', 1, 1, 1, '{}', 'A handy tool used for picking locks', 0, 0.15, NULL, NULL),
    ('wood',                  'Wood',               20,  1, 'item_standard', 1, 1, 1, '{}', 'A type of wood that is soft and easy to work with.', 0, 0.10, NULL, NULL),
    ('hwood',                 'Hard Wood',          20,  1, 'item_standard', 0, 1, 1, '{}', 'Durable and strong wood used in various applications.', 0, 0.15, NULL, NULL),
    ('still_tarp',            'Still Tarp',         2,   1, 'item_standard', 1, 1, 1, '{}', 'Rig it over a still to keep the rain off its fire.', 0, 1.00, NULL, NULL),
    ('bucketwater',           'Water Bucket',       20,  1, 'item_standard', 1, 1, 1, '{}', 'A Water bucket', 0, 0.15, NULL, NULL),
    ('bucket',                'Bucket',             100, 1, 'item_standard', 1, 1, 1, '{}', 'nice item', 0, 0.15, NULL, NULL),
    ('tasting_cup',           'Tasting Cup',        5,   1, 'item_standard', 1, 1, 1, '{}', 'A small tin cup. Sample a bottle to learn its true grade, its notes and its flaws.', 0, 0.25, NULL, NULL),
    ('kassippu_water_barrel', 'Water Barrel',       2,   1, 'item_standard', 1, 1, 1, '{}', 'Set it down beside your still and fill it: it cools the still while you hold the heat.', 0, 1.00, NULL, NULL),
    ('kassippu_log_rack',     'Log Rack',           2,   1, 'item_standard', 1, 1, 1, '{}', 'Set it down beside your still and stack logs on it: you stoke the fire from it while you hold the heat.', 0, 1.00, NULL, NULL),

    -- Barrel upgrades
    ('copper_coil',           'Copper Coil',        5,   1, 'item_standard', 1, 1, 1, '{}', 'A better condenser for your still. Every batch scores higher, and Perfect or Good spirit still comes out of a more worn barrel.', 0, 0.45, NULL, NULL),
    ('iron_hoops',            'Iron Hoops',         5,   1, 'item_standard', 1, 1, 1, '{}', 'Holds the staves of your still tight. The barrel wears 40% slower, so it keeps its condition and top grades longer.', 0, 0.65, NULL, NULL),
    ('gauge',                 'Pressure Gauge',     10,  1, 'item_standard', 0, 1, 1, '{}', 'A device used to measure pressure.', 0, 0.50, NULL, NULL),

    -- Recipe cards
    ('recipe_kasippu',        'Kasippu Recipe',     1,   1, 'item_standard', 1, 1, 1, '{}', 'A worn recipe card. Keep it in your satchel to brew Kasippu at your still. Use it to read the recipe.', 0, 0.50, NULL, NULL),

    -- What a batch leaves behind
    ('spent_mash',            'Spent Mash',         10,  1, 'item_standard', 1, 1, 1, '{}', 'The leftover grain and fruit from a still.', 0, 0.30, NULL, NULL),

    -- Found searching the coconut trees
    ('coconut',               'Coconut',            20,  1, 'item_standard', 1, 1, 1, '{}', 'nice item', 0, 0.15, NULL, NULL),

    -- What a still bottles
    ('local_kasippu',         'Local Kasippu',      10,  1, 'item_standard', 1, 1, 1, '{}', 'nice item', 0, 0.50, NULL, NULL),
    ('ra_packet',             'Pol Raa',            10,  1, 'item_standard', 1, 1, 1, '{}', 'nice item', 0, 0.20, NULL, NULL),

    -- Aged Kassippu
    ('kasippu_rested',        'Rested Kassippu',    10,  1, 'item_standard', 0, 1, 1, '{}', 'Kassippu rested in a crate. Smoother than fresh.', 0, 0.35, NULL, NULL),
    ('kasippu_mellow',        'Mellow Kassippu',    10,  1, 'item_standard', 0, 1, 1, '{}', 'Kassippu aged until mellow.', 0, 0.35, NULL, NULL),
    ('kasippu_fine',          'Fine Kassippu',      10,  1, 'item_standard', 0, 1, 1, '{}', 'The finest aged Kassippu.', 0, 0.35, NULL, NULL);
