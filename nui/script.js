let kassippuConfig = {};
let recipeOrder = [];
let itemImagePath = "";
let currentRecipe = "";

function recipeKeys() {
  return recipeOrder.filter((id) => kassippuConfig[id]);
}
let activeBarrelId = null;

let currentStage = "IDLE";
let stageNames = {};
let readOnlyBook = false;
let mashPreview = null;
let currentAmbientSound = null;
let lootTimer = null;

const JOURNAL_CLOSE_MS = 1150;
let journalCloseTimer = null;

function setJournalVisible(visible) {
  const journal = document.getElementById("journal");
  const book = document.getElementById("book");
  if (!journal) return;

  if (visible) {
    if (journalCloseTimer) {
      clearTimeout(journalCloseTimer);
      journalCloseTimer = null;
    }
    journal.classList.remove("is-open", "is-closing");
    if (book) book.classList.remove("turning-page", "landed");
    document.body.classList.add("journal-open");

    void journal.offsetWidth;
    journal.classList.add("is-open");
    paperSound("open");
    return;
  }

  if (!document.body.classList.contains("journal-open") || journal.classList.contains("is-closing")) return;

  journal.classList.remove("is-open");
  void journal.offsetWidth;
  journal.classList.add("is-closing");
  paperSound("close");

  journalCloseTimer = setTimeout(() => {
    document.body.classList.remove("journal-open");
    journal.classList.remove("is-closing");
    journalCloseTimer = null;
  }, JOURNAL_CLOSE_MS);
}

/* The rustle of paper */
let paperAudio = null;

function paperSound(kind) {
  try {
    paperAudio = paperAudio || new (window.AudioContext || window.webkitAudioContext)();
    const ctx = paperAudio;
    const dur = kind === "open" ? 0.75 : kind === "turn" ? 0.45 : 0.55;
    const buffer = ctx.createBuffer(1, Math.floor(ctx.sampleRate * dur), ctx.sampleRate);
    const data = buffer.getChannelData(0);

    for (let i = 0; i < data.length; i++) {
      const t = i / data.length;
      const crackle = Math.random() < 0.025 ? 3.2 : 1;
      data[i] = (Math.random() * 2 - 1) * crackle * Math.pow(Math.sin(Math.PI * t), 1.6);
    }

    const source = ctx.createBufferSource();
    source.buffer = buffer;
    const filter = ctx.createBiquadFilter();
    filter.type = "bandpass";
    filter.frequency.value = kind === "open" ? 1700 : 2500;
    filter.Q.value = 0.8;
    const gain = ctx.createGain();
    gain.gain.value = kind === "turn" ? 0.05 : 0.065;

    source.connect(filter).connect(gain).connect(ctx.destination);
    source.start(ctx.currentTime + (kind === "open" ? 0.45 : 0));
  } catch (e) {
    /* no audio is no reason to break the book */
  }
}

/* I, II, III ... for the plates */
function roman(n) {
  const table = [[10, "X"], [9, "IX"], [5, "V"], [4, "IV"], [1, "I"]];
  let out = "";
  for (const [value, glyph] of table) {
    while (n >= value) {
      out += glyph;
      n -= value;
    }
  }
  return out || "I";
}

function showLoot(payload) {
  const toast = document.getElementById("loot-toast");
  const list = document.getElementById("loot-items");
  const title = document.getElementById("loot-title");
  if (!toast || !list) return;

  if (title) title.innerText = payload.title || "FOUND";
  toast.classList.toggle("empty", !!payload.empty);

  list.innerHTML = "";
  (payload.items || []).forEach((entry) => {
    const li = document.createElement("li");
    li.className = "loot-item";

    if (entry.amount) {
      const amount = document.createElement("span");
      amount.className = "loot-amount";
      amount.innerText = entry.amount + "x";
      li.appendChild(amount);
    }

    li.appendChild(document.createTextNode(entry.label || entry.item || ""));
    list.appendChild(li);
  });

  toast.classList.add("show");

  if (lootTimer) clearTimeout(lootTimer);
  lootTimer = setTimeout(() => {
    toast.classList.remove("show");
    lootTimer = null;
  }, payload.duration || 4000);
}

setJournalVisible(false);

function initJournal() {
  const tabContainer = document.querySelector(".category-tabs");
  if (!tabContainer) return;
  tabContainer.innerHTML = "";

  const keys = recipeKeys();

  keys.forEach((id) => {
    const data = kassippuConfig[id];
    const tab = document.createElement("div");
    tab.className = `tab-btn ${id === currentRecipe ? "active" : ""}`;
    tab.innerText = data.tab || data.label;
    tab.onclick = () => switchCategory(id, tab);
    tabContainer.appendChild(tab);
  });

  if (keys.length > 0) {
    if (!kassippuConfig[currentRecipe]) currentRecipe = keys[0];
    loadRecipe(currentRecipe);
  }
}

function switchCategory(id, element) {
  if (id === currentRecipe) return;
  currentRecipe = id;
  document
    .querySelectorAll(".tab-btn")
    .forEach((btn) => btn.classList.remove("active"));
  element.classList.add("active");
  turnPage(() => loadRecipe(id));
}

/* Turn a leaf from the right page over to the left */
let leafTimer = null;

function turnPage(swap) {
  const leaf = document.getElementById("leaf");
  const book = document.getElementById("book");
  if (!leaf || !book) return swap();

  if (leafTimer) clearTimeout(leafTimer);
  leaf.classList.remove("turning");
  book.classList.remove("landed");
  void leaf.offsetWidth;

  book.classList.add("turning-page");
  leaf.classList.add("turning");
  paperSound("turn");
  swap();

  leafTimer = setTimeout(() => {
    book.classList.remove("turning-page");
    book.classList.add("landed");
    leaf.classList.remove("turning");
    leafTimer = null;
  }, 740);
}

/* One ingredient on the receipt */
function receiptLine(line) {
  const li = document.createElement("li");
  li.className = "receipt-line";

  const icons = document.createElement("span");
  icons.className = "receipt-icons";
  (line.icons || []).forEach((item) => {
    if (!item || !itemImagePath) return;
    const img = document.createElement("img");
    img.src = itemImagePath.replace("%s", item);
    img.alt = "";
    img.onerror = () => img.remove();
    icons.appendChild(img);
  });

  const words = document.createElement("span");
  words.className = "receipt-words";
  const name = document.createElement("span");
  name.className = "receipt-name";
  name.innerText = line.name || "";
  words.appendChild(name);
  if (line.note) {
    const note = document.createElement("span");
    note.className = "receipt-note";
    note.innerText = line.note;
    words.appendChild(note);
  }

  const dots = document.createElement("span");
  dots.className = "ledger-dots";

  const amount = document.createElement("span");
  amount.className = "receipt-amount";
  amount.innerText = line.amount || "";

  li.append(icons, words, dots, amount);
  return li;
}

function loadRecipe(id) {
  const data = kassippuConfig[id];
  if (!data) return;

  const keys = recipeKeys();
  const index = Math.max(0, keys.indexOf(id));

  /* Running head (the receipt's own title) and the name in capitals */
  const pageTitle = document.querySelector(".page-title");
  if (pageTitle) pageTitle.innerText = data.title || data.label || "";

  const recipeTitle = document.getElementById("recipe-title");
  if (recipeTitle) recipeTitle.innerText = data.label || "";

  /* Page numbers: every receipt is a spread further into the book */
  const folioLeft = document.getElementById("folio-left");
  const folioRight = document.getElementById("folio-right");
  if (folioLeft) folioLeft.innerText = String(12 + index * 2);
  if (folioRight) folioRight.innerText = String(13 + index * 2);

  /* The receipt */
  const ingredientsList = document.querySelector(".ingredients-list");
  if (ingredientsList) {
    ingredientsList.innerHTML = "";
    (data.receipt || []).forEach((line) => {
      ingredientsList.appendChild(receiptLine(line));
    });
    (data.notes || []).forEach((item) => {
      const li = document.createElement("li");
      li.className = "receipt-extra";
      li.innerText = item;
      ingredientsList.appendChild(li);
    });
  }

  const instructions = document.getElementById("recipe-instructions");
  if (instructions) instructions.innerText = data.instructions || "";

  /* The plate and its caption */
  const displayImage = document.getElementById("display_img");
  if (displayImage) displayImage.src = data.displayImage || "";

  const caption = document.getElementById("plate-caption");
  if (caption) caption.innerText = "Plate " + roman(index + 1) + ". \u2014 " + (data.label || "");

  const titleImage = document.getElementById("title_img");
  if (titleImage) {
    titleImage.src = data.titleImage || "";
    titleImage.style.visibility = data.titleImage ? "visible" : "hidden";
  }

  requestMashPreview(id);
}

/* ------------------------------------------------------------------ */
/*  The mash slip                                                      */
/*                                                                     */
/*  Pinned beside the book while the barrel is waiting for a mix: the  */
/*  server reads the barrel for the recipe on screen and says, in      */
/*  plain words, what is in it, what it will make and what to fix.     */
/*  START MIXING stays struck through until the reading says ready.    */
/* ------------------------------------------------------------------ */
function canMixNow() {
  if (readOnlyBook) return false;
  return currentStage === "IDLE" || currentStage === "FREEZE";
}

function requestMashPreview(id) {
  mashPreview = null;
  renderMashSlip(null);
  refreshStartButton();

  if (!canMixNow() || !id) return;

  fetch(`https://${GetParentResourceName()}/previewMix`, {
    method: "POST",
    body: JSON.stringify({ recipeId: id }),
  });
}

function renderMashSlip(p) {
  const slip = document.getElementById("mash-slip");
  if (!slip) return;

  if (!p) {
    slip.classList.remove("visible");
    return;
  }
  slip.classList.add("visible");

  setText("mash-title", p.title || "IN THE BARREL");

  const lines = document.getElementById("mash-lines");
  lines.innerHTML = "";
  (p.lines || []).forEach((line) => {
    if (!line) return;
    const row = document.createElement("div");
    row.className = "mash-line";

    const label = document.createElement("span");
    label.className = "mash-line-label";
    label.innerText = line[0] || "";

    const value = document.createElement("span");
    value.className = "mash-line-value";
    value.innerText = line[1] || "";

    row.appendChild(label);
    row.appendChild(value);
    lines.appendChild(row);
  });

  document.querySelector(".mash-outcome").style.display = p.outcome ? "flex" : "none";
  setText("mash-outcome-label", p.outcomeLabel || "");
  setText("mash-outcome", p.outcome || "");
  setText("mash-note", p.note || "");
  document.getElementById("mash-outcome").className =
    "mash-outcome-text " + (p.ok ? "good" : "faded");

  /* What to fix, then what will go wrong anyway - or that it is ready */
  const fix = document.getElementById("mash-fix");
  const list = document.getElementById("mash-fix-list");
  list.innerHTML = "";

  const problems = p.problems || [];
  const warnings = p.warnings || [];

  problems.forEach((text) => {
    const li = document.createElement("li");
    li.className = "bad";
    li.innerText = text;
    list.appendChild(li);
  });
  warnings.forEach((text) => {
    const li = document.createElement("li");
    li.className = "warn";
    li.innerText = text;
    list.appendChild(li);
  });

  if (problems.length === 0 && warnings.length === 0) {
    const li = document.createElement("li");
    li.className = "good";
    li.innerText = p.readyText || "Ready to mix";
    list.appendChild(li);
  }

  setText("mash-fix-title", problems.length > 0 ? p.fixTitle || "TO FIX" : "");
  fix.classList.toggle("has-problems", problems.length > 0);

  setText("mash-legend", p.legend || "");
}

/* ------------------------------------------------------------------ */
/*  The crew slip                                                      */
/*                                                                     */
/*  The owner's only, under the mash slip: who is cooking with them,   */
/*  and the players standing by the barrel with an ASK beside each.    */
/*  Lua asks the server again every few seconds while the book is      */
/*  open; a null roster (not the owner) keeps the slip off the page.   */
/* ------------------------------------------------------------------ */
function crewLine(label, value) {
  const row = document.createElement("div");
  row.className = "mash-line";

  const name = document.createElement("span");
  name.className = "mash-line-label";
  name.innerText = label;
  row.appendChild(name);

  if (value) row.appendChild(value);
  return row;
}

function crewEmpty(text) {
  const line = document.createElement("div");
  line.className = "crew-empty";
  line.innerText = text || "";
  return line;
}

function renderCrewSlip(roster, text) {
  const slip = document.getElementById("crew-slip");
  if (!slip) return;

  if (!roster) {
    slip.classList.remove("visible");
    return;
  }
  slip.classList.add("visible");
  text = text || {};

  const crew = Array.isArray(roster.crew) ? roster.crew : [];
  const max = roster.max || 0;
  const full = crew.length >= max;

  setText("crew-title", text.Title || "THE CREW");
  setText("crew-count", (text.Count || "%d of %d").replace("%d", crew.length).replace("%d", max));

  const members = document.getElementById("crew-members");
  members.innerHTML = "";
  if (crew.length === 0) members.appendChild(crewEmpty(text.NoCrew));
  crew.forEach((name) => members.appendChild(crewLine(name)));

  setText("crew-nearby-title", text.Nearby || "Standing by");

  const nearby = document.getElementById("crew-nearby");
  nearby.innerHTML = "";

  if (full) {
    nearby.appendChild(crewEmpty(text.Full));
    return;
  }

  const players = Array.isArray(roster.nearby) ? roster.nearby : [];
  if (players.length === 0) nearby.appendChild(crewEmpty(text.NoOneNearby));

  players.forEach((player) => {
    const ask = document.createElement("button");
    ask.className = "crew-ask";
    ask.innerText = player.asked ? text.Asked || "Asked" : text.Invite || "Ask";
    ask.disabled = !!player.asked;
    ask.onclick = () => {
      ask.disabled = true;
      ask.innerText = text.Asked || "Asked";
      fetch(`https://${GetParentResourceName()}/crewInvite`, {
        method: "POST",
        body: JSON.stringify({ target: player.id }),
      });
    };
    nearby.appendChild(crewLine(player.name, ask));
  });
}

/* The fittings slip */
function renderFittingsSlip(fittings) {
  const slip = document.getElementById("fittings-slip");
  if (!slip) return;

  const list = fittings && Array.isArray(fittings.list) ? fittings.list : [];
  if (list.length === 0) {
    slip.classList.remove("visible");
    return;
  }
  slip.classList.add("visible");
  const text = fittings.text || {};

  const fitted = list.filter((up) => up.fitted).length;
  setText("fittings-title", text.Title || "FITTINGS");
  setText("fittings-count", (text.Count || "%d of %d").replace("%d", fitted).replace("%d", list.length));
  setText("fittings-hint", text.Hint || "");

  const box = document.getElementById("fittings-list");
  box.innerHTML = "";
  list.forEach((up) => {
    const item = document.createElement("div");
    item.className = "fitting";

    let end;
    if (up.fitted) {
      end = document.createElement("span");
      end.className = "fitting-done";
      end.innerText = text.Fitted || "Fitted";
    } else {
      end = document.createElement("button");
      end.className = "crew-ask";
      end.innerText = text.Fit || "Fit";
      end.onclick = () => {
        end.disabled = true;
        setTimeout(() => (end.disabled = false), 1500);
        fetch(`https://${GetParentResourceName()}/fitUpgrade`, {
          method: "POST",
          headers: { "Content-Type": "application/json; charset=UTF-8" },
          body: JSON.stringify({ key: up.key }),
        });
      };
    }
    item.appendChild(crewLine(up.label || up.key, end));

    if (up.desc) {
      const desc = document.createElement("div");
      desc.className = "fitting-desc";
      desc.innerText = up.desc;
      item.appendChild(desc);
    }
    box.appendChild(item);
  });
}

function refreshStartButton() {
  const btn = document.getElementById("start-mixing-btn");
  if (!btn) return;

  if (currentStage === "FREEZE" && (!mashPreview || mashPreview.ok)) {
    btn.disabled = false;
    btn.innerText = "Commence Mixing";
  } else {
    btn.disabled = true;
    btn.innerText =
      currentStage === "FREEZE"
        ? "Fix the Mash"
        : (stageNames[currentStage] && stageNames[currentStage].label) || currentStage;
  }
}
function updateStatus(data) {
  if (readOnlyBook) return;
  if (data.heat !== undefined)
    document.getElementById("heat-text").innerText =
      Math.floor(data.heat) + "%";
  if (data.progress !== undefined)
    document.getElementById("progress-text").innerText =
      Math.floor(data.progress) + "%";
  if (data.bottles !== undefined) {
    document.getElementById("bottle-text").innerText = data.bottles;
    updateBottleIcons(data.bottles);
  }

  const stage = data.currentStage || data.stage;
  if (stage) {
    const wasMixable = canMixNow();
    currentStage = stage;

    document.getElementById("stage-text").innerText =
      (stageNames[stage] && stageNames[stage].label) || stage;

    const hint = document.getElementById("journal-hint");
    if (hint) hint.innerText = (stageNames[stage] && stageNames[stage].hint) || "";

    if (wasMixable !== canMixNow()) {
      if (canMixNow()) requestMashPreview(currentRecipe);
      else {
        mashPreview = null;
        renderMashSlip(null);
      }
    }

    refreshStartButton();
  }
}

function updateBottleIcons(count) {
  const container = document.querySelector(".bottles-display");
  if (!container) return;
  container.innerHTML = "";
  for (let i = 0; i < count; i++) {
    const bottle = document.createElement("div");
    bottle.className = "bottle-icon";
    container.appendChild(bottle);
  }
}

/* ------------------------------------------------------------------ */
/*  At-the-barrel gauge                                                */
/*                                                                     */
/*  Everything here is driven by the server's heat tick, so it only    */
/*  ever renders numbers it was actually given: target, score and the  */
/*  run timer are absent outside the graded push, and their rows hide  */
/*  rather than showing stale values.                                  */
/* ------------------------------------------------------------------ */
function pctOfScale(value, maxHeat) {
  return Math.max(0, Math.min(100, (value / maxHeat) * 100));
}

function clampPct(value) {
  return Math.max(0, Math.min(100, value || 0));
}

/* A core ring: its fill is a percent of the ring (pathLength 100) */
function setRing(fillId, pct) {
  document.getElementById(fillId).style.strokeDashoffset = 100 - clampPct(pct);
}

/* A core's fixed tick, turned to its percent round the ring; hidden at 0 */
function setRingTick(tickId, pct) {
  const tick = document.getElementById(tickId);
  tick.style.display = pct ? "" : "none";
  tick.style.transform = "rotate(" + clampPct(pct) * 3.6 + "deg)";
}

/* Show a part of the gauge with its stylesheet display, or hide it */
function showPart(el, on) {
  el.style.display = on ? "" : "none";
}

/* Where the needle sat last tick */
let lastGaugeHeat = null;

function showGauge(data) {
  const root = document.getElementById("barrel-gauge");
  if (!root) return;

  const wasVisible = root.classList.contains("visible");
  root.classList.add("visible");
  if (!wasVisible) radialHintPlace(); /* the F2 tag moves on top of it */

  const maxHeat = data.maxHeat || 105;
  const heat = data.heat || 0;
  const hasTarget = data.target !== undefined && data.target !== null;
  const half = data.band || 0;
  const inBand = hasTarget && heat >= data.target - half && heat <= data.target + half;

  /* What the still is doing: tints the rule under the title */
  let state = "idle";
  if (data.incident) state = "trouble";
  else if (hasTarget) state = inBand ? "mark" : "push";
  else if (data.cut) state = "drip";
  else if (data.ferment) state = data.ferment.turning ? "trouble" : "ferment";
  else if (data.fire && (data.fire.fuel || 0) > 0) state = "fire";
  root.dataset.state = state;

  document.getElementById("gauge-stage").innerText = data.stage || "IDLE";

  /* What to do now, and what is cooking */
  const hint = document.getElementById("gauge-hint");
  hint.innerText = data.hint || "";
  hint.style.display = data.hint ? "block" : "none";

  const mix = document.getElementById("gauge-mix");
  if (data.mix && data.mix.product) {
    mix.innerText = data.mix.product + (data.mix.batch > 1 ? "  ×" + data.mix.batch : "");
    mix.style.display = "block";
  } else {
    mix.style.display = "none";
  }

  /* Trouble at the still, red and counting down */
  const trouble = document.getElementById("gauge-incident");
  if (data.incident) {
    trouble.classList.add("visible");
    setText("gi-label", "! " + (data.incidentTitle || "TROUBLE") + " — " + (data.incident.label || ""));
    setText("gi-left", clock(data.incident.left));
    setText("gi-due", data.incident.due || "");
    trouble.classList.toggle("urgent", (data.incident.left || 0) <= 10);
  } else {
    trouble.classList.remove("visible", "urgent");
  }

  /* The heat scale */
  const heatPct = pctOfScale(heat, maxHeat);
  const dial = document.getElementById("gauge-dial");
  setText("gauge-heat-value", Math.floor(heat) + "%");
  document.getElementById("gauge-heat-fill").style.clipPath = "inset(0 " + (100 - heatPct) + "% 0 0)";
  document.getElementById("gauge-needle").style.left = heatPct + "%";
  dial.classList.toggle("critical", heat >= maxHeat * 0.92);

  /* Rising or falling since the last tick */
  const trend = document.getElementById("gauge-heat-trend");
  const delta = lastGaugeHeat === null ? 0 : heat - lastGaugeHeat;
  lastGaugeHeat = heat;
  trend.innerText = delta > 0.4 ? "▲" : delta < -0.4 ? "▼" : "";
  trend.className = "rd-trend" + (delta > 0.4 ? " up" : delta < -0.4 ? " down" : "");

  /* The band and the drifting mark */
  const band = document.getElementById("gauge-band");
  const marker = document.getElementById("gauge-target");
  if (hasTarget) {
    const left = pctOfScale(data.target - half, maxHeat);
    const right = pctOfScale(data.target + half, maxHeat);
    band.style.display = "block";
    band.style.left = left + "%";
    band.style.width = Math.max(0, right - left) + "%";
    marker.style.display = "block";
    marker.style.left = pctOfScale(data.target, maxHeat) + "%";
    dial.dataset.zone = inBand ? "in" : heat > data.target ? "over" : "under";
  } else {
    band.style.display = "none";
    marker.style.display = "none";
    dial.dataset.zone = "";
  }

  /* Running score + time left in the push */
  const run = document.getElementById("gauge-run");
  if (data.score !== undefined && data.score !== null) {
    run.classList.add("visible");
    const score = Math.floor(data.score);
    const scoreEl = document.getElementById("gauge-score");
    scoreEl.innerText = "QUALITY " + score + "%";
    scoreEl.className = score >= 82 ? "good" : score >= 60 ? "ok" : "bad";
    setText("gauge-timer",
      data.pushLeft !== undefined && data.pushLeft !== null ? Math.ceil(data.pushLeft) + "s" : "--s");
  } else {
    run.classList.remove("visible");
  }

  /* ---- the cores ---- */

  /* The fire */
  const fireRow = document.getElementById("gauge-fire-row");
  const fireRain = document.getElementById("gauge-fire-rain");
  if (data.fire) {
    const f = data.fire;
    const ft = data.fireText || {};
    const fuel = Math.max(0, f.fuel || 0);

    showPart(fireRow, true);
    setText("gauge-fire-label", ft.Label || "FIRE");
    setRing("gauge-fire-fill", (fuel / Math.max(1, f.max || 1)) * 100);
    fireRow.classList.toggle("critical", fuel > 0 && fuel <= 10);
    fireRow.classList.toggle("out", fuel <= 0);
    setText("gauge-fire-value", fuel > 0 ? clock(fuel) : ft.Out || "OUT");

    const smokeText = f.smoke > 0 && ft.Smoke ? ft.Smoke[f.smoke - 1] || "" : "";
    let note = smokeText;
    let noteCls = " smoke-" + (f.smoke || 0);
    if (f.rain) {
      note = ft.Rain || "";
      noteCls = " rain";
    } else if (f.cooling) {
      note = ft.Cooling || "Cooling down - put more wood on!";
      noteCls = " cooling";
    } else if (f.coolIn > 0) {
      note = (ft.Holding || "Embers holding the heat - cools in %ds").replace("%d", f.coolIn);
      noteCls = " holding";
    }
    fireRain.innerText = note;
    fireRain.className = "rd-note gauge-fire-rain" + noteCls;
    fireRain.style.display = note ? "block" : "none";
  } else {
    showPart(fireRow, false);
    fireRain.style.display = "none";
  }

  /* Pressure */
  const pressureRow = document.getElementById("gauge-pressure-row");
  if (data.pressure !== undefined && data.pressure !== null) {
    showPart(pressureRow, true);
    setRing("gauge-pressure-fill", data.pressure);
    pressureRow.classList.toggle("critical", data.pressure >= (data.pressureWarn || 70));
    setText("gauge-pressure-value", Math.floor(data.pressure) + "%");
  } else {
    showPart(pressureRow, false);
  }

  /* The barrel itself, rather than the batch */
  const conditionRow = document.getElementById("gauge-condition-row");
  if (data.condition !== undefined && data.condition !== null) {
    showPart(conditionRow, true);
    setRing("gauge-condition-fill", data.condition);
    conditionRow.classList.toggle("critical", data.condition <= (data.conditionWarn || 30));
    setText("gauge-condition-value", Math.floor(data.condition) + "%");
  } else {
    showPart(conditionRow, false);
  }

  const residueRow = document.getElementById("gauge-residue-row");
  if (data.residue !== undefined && data.residue !== null && data.residue > 0) {
    showPart(residueRow, true);
    setRing("gauge-residue-fill", data.residue);
    setText("gauge-residue-value", Math.floor(data.residue) + "%");
  } else {
    showPart(residueRow, false);
  }

  /* The fermenting wash */
  const fermentRow = document.getElementById("gauge-ferment-row");
  const fermentNote = document.getElementById("gauge-ferment-note");
  if (data.ferment) {
    const f = data.ferment;
    const strength = clampPct(f.strength);

    showPart(fermentRow, true);
    fermentNote.classList.add("visible");
    setRing("gauge-ferment-fill", strength);
    setRingTick("gauge-ferment-min", f.minStrength || 0);
    fermentRow.classList.toggle("critical", !!f.turning);
    fermentRow.classList.toggle("good", !f.turning && strength >= 100);
    setText("gauge-ferment-value", Math.floor(strength) + "%");

    const state = document.getElementById("gauge-ferment-state");
    const timer = document.getElementById("gauge-ferment-timer");
    if (f.turning) {
      state.innerText = "TURNING";
      state.className = "bad";
      timer.innerText = "LOST IN " + clock(f.spoilIn);
    } else if (strength >= 100) {
      state.innerText = "READY";
      state.className = "good";
      timer.innerText = "TURNS IN " + clock(f.turnIn);
    } else {
      state.innerText = "FERMENTING" + (f.climate ? " - " + String(f.climate).toUpperCase() : "");
      state.className = "ok";
      timer.innerText = "";
    }
  } else {
    showPart(fermentRow, false);
    fermentNote.classList.remove("visible");
  }

  /* The condenser */
  const condRow = document.getElementById("gauge-cond-row");
  const condHot = document.getElementById("gauge-cond-hot");
  if (data.condenser) {
    const c = data.condenser;
    const ct = data.condenserText || {};

    showPart(condRow, true);
    setText("gauge-cond-label", ct.Label || "COOLER");
    setRing("gauge-cond-fill", c.level);
    setRingTick("gauge-cond-min", c.hotBelow || 0);
    condRow.classList.toggle("critical", !!c.hot);
    setText("gauge-cond-value", Math.floor(clampPct(c.level)) + "%");

    condHot.innerText = c.hot ? ct.Hot || "" : "";
    condHot.style.display = c.hot ? "block" : "none";
  } else {
    showPart(condRow, false);
    condHot.style.display = "none";
  }

  /* Hold The Heat as a game */
  const waterRow = document.getElementById("gauge-water-row");
  const splitsRow = document.getElementById("gauge-splits-row");
  const pushWarn = document.getElementById("gauge-push-warn");
  const game = data.game;
  const gt = data.gameText || {};
  if (game && game.water !== undefined && game.water !== null) {
    showPart(waterRow, true);
    setText("gauge-water-label", game.tap ? gt.TapOn || "TAP OPEN" : gt.Water || "WATER");
    setRing("gauge-water-fill", (game.water / Math.max(1, game.waterMax || 1)) * 100);
    setText("gauge-water-value", Math.floor(game.water) + "L");
    waterRow.classList.toggle("tap", !!game.tap);
    waterRow.classList.toggle("critical", game.water <= 0);
  } else {
    showPart(waterRow, false);
  }
  if (game && game.splits !== undefined && game.splits !== null) {
    showPart(splitsRow, true);
    setText("gauge-splits-label", gt.Logs || "SPLITS");
    setRing("gauge-splits-fill", (game.splits / Math.max(1, game.splitsMax || 1)) * 100);
    setText("gauge-splits-value", String(game.splits));
    splitsRow.classList.toggle("critical", game.splits <= 0);
  } else {
    showPart(splitsRow, false);
  }
  if (game && game.warn && gt[game.warn]) {
    pushWarn.innerText = gt[game.warn];
    pushWarn.className = "rd-note gauge-push-warn " + game.warn;
    pushWarn.style.display = "block";
  } else {
    pushWarn.style.display = "none";
  }

  /* The drip while the spirit is caught */
  const cutRow = document.getElementById("gauge-cut-row");
  const cutNote = document.getElementById("gauge-cut-note");
  if (data.cut && data.cutText) {
    const c = data.cut;
    const t = data.cutText;

    showPart(cutRow, true);
    cutNote.classList.add("visible");

    const fill = document.getElementById("gauge-cut-fill");
    fill.style.width = clampPct(c.progress) + "%";
    fill.className = "rd-bar-fill cut-fill phase-" + c.phase;

    const jar = document.getElementById("gauge-cut-jar");
    jar.innerText = c.keeping ? t.Keeping : t.NotKeeping;
    jar.className = "rd-line-val" + (c.keeping ? " keeping" : "");

    const smell = document.getElementById("gauge-cut-smell");
    smell.innerText = c.soon ? (t.Soon || {})[c.soon] || "" : (t.Smell || {})[c.phase] || "";
    smell.className = "gauge-cut-smell phase-" + (c.soon || c.phase);

    setText("gauge-cut-do", !c.started ? t.DoStart || "" : c.keeping ? t.DoStop || "" : "");
  } else {
    showPart(cutRow, false);
    cutNote.classList.remove("visible");
  }

  /* The cooking crew, and the still's fittings */
  const crewRow = document.getElementById("gauge-crew");
  const hasCrew = Array.isArray(data.crew) && data.crew.length > 0;
  crewRow.classList.toggle("visible", hasCrew);
  if (hasCrew) setText("gauge-crew-names", data.crew.join("  ·  "));

  const upgradesRow = document.getElementById("gauge-upgrades");
  const hasUpgrades = Array.isArray(data.upgrades) && data.upgrades.length > 0;
  upgradesRow.classList.toggle("visible", hasUpgrades);
  if (hasUpgrades) setText("gauge-upgrades-names", data.upgrades.join("  ·  "));
}

function hideGauge() {
  const root = document.getElementById("barrel-gauge");
  if (root) root.classList.remove("visible");
  lastGaugeHeat = null;
  radialHintPlace(); /* the F2 tag back to its own corner */
}

/* ------------------------------------------------------------------ */
/*  At-the-crate gauge                                                 */
/*                                                                     */
/*  The barrel gauge's black brush plate, worn by the crate. Drawn     */
/*  with no NUI focus: Lua reads the arrow keys and prompts and sends  */
/*  the server's reading (once a second) plus the picked slot; this    */
/*  only draws it.                                                     */
/*                                                                     */
/*  The rack is the crate: a bottle per slot, its spirit the colour of */
/*  the tier it has reached, a hairline under it for how close it is   */
/*  to the next. The picked bottle lifts out of the crate (as its prop */
/*  does in the world) and is read out in the ledger: a track from Raw */
/*  to the richest tier, when it comes on, when it turns, shelf life.  */
/*  A bottle that comes on flares gold; one that turns, red.           */
/*  Words: Config.Text.CrateGauge, sent with the first reading.        */
/* ------------------------------------------------------------------ */
function clock(seconds) {
  const s = Math.max(0, Math.ceil(seconds || 0));
  const m = Math.floor(s / 60);
  return m + ":" + String(s % 60).padStart(2, "0");
}

function rate(value) {
  return "×" + (value || 1).toFixed(2);
}

function setText(id, text) {
  document.getElementById(id).innerText = text;
}

/* A bottle's life runs to hours: h:mm:ss once past the hour */
function longClock(seconds) {
  const s = Math.max(0, Math.ceil(seconds || 0));
  if (s < 3600) return clock(s);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h + ":" + String(m).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
}

/* Lua-style %s / %d, in order */
function crateFmt(template, ...args) {
  let i = 0;
  return String(template).replace(/%[sd]/g, () => {
    const v = args[i++];
    return v === undefined || v === null ? "" : v;
  });
}

function signed(n) {
  const r = Math.round(n || 0);
  return (r > 0 ? "+" : "") + r;
}

function clamp01(v) {
  return Math.max(0, Math.min(1, v || 0));
}

/* Only used if Config.Text.CrateGauge is missing a key */
const CRATE_TEXT = {
  Title: "AGING CRATE",
  Locked: "LOCKED",
  Best: "BEST",
  Empty: "EMPTY",
  EmptyHint: "Lay a fresh bottle down and let the crate do its work.",
  Raw: "Raw",
  Turned: "Turned",
  Peak: "At its best - take it before it turns",
  NextIn: "%s in %s",
  NoFurther: "Won't come on further",
  TurnsIn: "Turns in %s",
  Turning: "Turning! %s",
  Sour: "Comes out as plain spirit",
  Aged: "Down %d min",
  Care: "Care %s",
  Cellar: "%s cellar",
  Indoors: "indoors",
  CareCore: "CARE",
  AgesCore: "AGES",
  KeepsCore: "KEEPS",
  RhythmCore: "RHYTHM",
  Shelf: "SHELF LIFE",
  NextCheck: "NEXT CHECK",
};

const crateUI = {
  text: {},
  limits: {},
  tiers: [],
  lastRank: {},
  lastSelected: null,
  flares: {},      /* bottle id -> timeout */
};

function ct(key) {
  const v = crateUI.text && crateUI.text[key];
  return v !== undefined && v !== null && v !== "" ? v : CRATE_TEXT[key];
}

/* Raw is 0, the tiers count up from the poorest; turned is -1 */
function crateRank(slot) {
  if (!slot) return null;
  if (slot.sour) return -1;
  if (!slot.tier) return 0;
  const i = crateUI.tiers.findIndex((t) => t.key === slot.tier);
  return i < 0 ? 0 : i + 1;
}

/* The spirit darkens as it comes on */
const CRATE_LIQUOR = [
  [228, 216, 172],  /* raw */
  [214, 160, 74],
  [176, 102, 34],
  [118, 50, 18],    /* the richest */
];

function liquorFor(rank) {
  if (rank < 0) return "rgb(98, 100, 56)"; /* turned: murky */
  const n = Math.max(1, crateUI.tiers.length);
  const f = Math.max(0, Math.min(1, rank / n)) * (CRATE_LIQUOR.length - 1);
  const a = CRATE_LIQUOR[Math.floor(f)];
  const b = CRATE_LIQUOR[Math.min(CRATE_LIQUOR.length - 1, Math.floor(f) + 1)];
  const t = f - Math.floor(f);
  const mix = (i) => Math.round(a[i] + (b[i] - a[i]) * t);
  return "rgb(" + mix(0) + ", " + mix(1) + ", " + mix(2) + ")";
}

const CRATE_BOTTLE =
  '<svg class="cg2-bottle" viewBox="0 0 24 60" aria-hidden="true">' +
  '<path class="b-glass" d="M9.4 6.5h5.2v11.4c2 2 5.4 4.6 5.4 9.1v26a3.5 3.5 0 0 1-3.5 3.5h-9A3.5 3.5 0 0 1 4 53V27c0-4.5 3.4-7.1 5.4-9.1z"/>' +
  '<path class="b-liquor" d="M5.4 27.4c0-3.6 2.8-5.8 5.4-8.3V13h2.4v6.1c2.6 2.5 5.4 4.7 5.4 8.3v25.3a2.2 2.2 0 0 1-2.2 2.2H7.6a2.2 2.2 0 0 1-2.2-2.2z"/>' +
  '<rect class="b-label" x="6.4" y="28.5" width="11.2" height="8.5" rx="0.6"/>' +
  '<path class="b-shine" d="M7.4 28.5v19"/>' +
  '<rect class="b-cork" x="9" y="1.5" width="6" height="6.5" rx="1.2"/>' +
  '<path class="b-cross" d="M2.5 24l19 30 M21.5 24l-19 30"/>' +
  "</svg>";

function buildCrateRack(rack, capacity) {
  const cols = Math.min(6, capacity);
  const rows = Math.ceil(capacity / cols);
  rack.innerHTML = "";
  rack.style.setProperty("--cg2-cols", cols);

  for (let r = 0; r < rows; r++) {
    const row = document.createElement("div");
    row.className = "cg2-row";
    for (let c = 0; c < cols && r * cols + c < capacity; c++) {
      const slot = document.createElement("div");
      slot.className = "cg2-slot empty";
      slot.innerHTML =
        '<div class="cg2-lift">' + CRATE_BOTTLE + '<span class="cg2-badge">!</span></div>' +
        '<div class="cg2-prog"><i></i></div>';
      row.appendChild(slot);
    }
    rack.appendChild(row);
  }
  rack.dataset.capacity = capacity;
}

function buildCrateTrack() {
  const nodes = document.getElementById("cg2-track-nodes");
  const all = [{ label: ct("Raw") }].concat(crateUI.tiers);
  const sig = all.map((t) => t.label).join("|");
  if (nodes.dataset.sig === sig) return;

  nodes.innerHTML = "";
  all.forEach((tier, i) => {
    const node = document.createElement("span");
    node.className = "cg2-node";
    node.style.left = (all.length > 1 ? (i / (all.length - 1)) * 100 : 0) + "%";
    node.innerHTML = "<i></i><b></b>";
    node.lastChild.innerText = tier.label || tier.key;
    nodes.appendChild(node);
  });
  nodes.dataset.sig = sig;
}

/* Restart a one-shot CSS animation */
function replay(el, cls) {
  el.classList.remove(cls);
  void el.offsetWidth;
  el.classList.add(cls);
}

function flare(cell, id, cls) {
  if (crateUI.flares[id]) clearTimeout(crateUI.flares[id]);
  replay(cell, cls);
  crateUI.flares[id] = setTimeout(() => {
    cell.classList.remove(cls);
    delete crateUI.flares[id];
  }, 1700);
}

function setCrateRing(id, fraction) {
  const ring = document.getElementById(id);
  if (ring) ring.style.strokeDashoffset = 100 - clamp01(fraction) * 100;
}

function setCore(id, cls) {
  const core = document.getElementById(id);
  core.classList.remove("good", "poor", "critical", "cold", "off");
  if (cls) cls.split(" ").forEach((c) => c && core.classList.add(c));
}

function showCrateLedger(slot, climate) {
  const ledger = document.getElementById("cg2-ledger");
  if (!slot) {
    ledger.style.display = "none";
    return;
  }
  ledger.style.display = "block";

  const rank = crateRank(slot);
  const n = crateUI.tiers.length;
  ledger.classList.toggle("sour", !!slot.sour);
  ledger.classList.toggle("target", !!slot.target);
  ledger.style.setProperty("--liquor", liquorFor(rank));

  setText("cg2-name", slot.name || "");
  setText("cg2-grade", slot.grade || "");
  setText("cg2-tier", slot.sour ? ct("Turned") : slot.tierLabel || ct("Raw"));

  /* The track */
  buildCrateTrack();
  const nodes = document.getElementById("cg2-track-nodes").children;
  let pos = 0;
  if (!slot.sour) {
    pos = slot.peak || rank >= n ? 1 : n > 0 ? (rank + clamp01(slot.progress)) / n : 0;
    pos = clamp01(pos);
  }
  for (let i = 0; i < nodes.length; i++) {
    nodes[i].classList.toggle("lit", !slot.sour && i <= rank);
    nodes[i].classList.toggle("here", !slot.sour && i === rank);
    nodes[i].classList.toggle("next", !slot.sour && !slot.peak && i === rank + 1 && !!slot.nextLabel);
  }
  document.getElementById("cg2-track").classList.toggle("sour", !!slot.sour);
  document.getElementById("cg2-track-fill").style.width = pos * 100 + "%";
  document.getElementById("cg2-track-needle").style.left = pos * 100 + "%";

  /* When it comes on, when it turns */
  const next = document.getElementById("cg2-next");
  const turn = document.getElementById("cg2-turn");
  next.className = "";
  turn.className = "";
  if (slot.sour) {
    next.innerText = ct("Sour");
    turn.innerText = "";
  } else {
    if (slot.peak) {
      next.innerText = ct("Peak");
      next.className = "gold";
    } else if (slot.nextLabel) {
      next.innerText = crateFmt(ct("NextIn"), slot.nextLabel, longClock(slot.nextIn));
    } else {
      next.innerText = ct("NoFurther");
      next.className = "dim";
    }
    turn.innerText = slot.turning
      ? crateFmt(ct("Turning"), longClock(slot.turnsIn))
      : crateFmt(ct("TurnsIn"), longClock(slot.turnsIn));
    if (slot.turning) turn.className = "warn";
  }

  /* Shelf life: what is left of the time before it turns */
  const lim = crateUI.limits || {};
  let shelf = 0;
  if (!slot.sour) {
    const total = lim.spoilMinutes
      ? lim.spoilMinutes * 60 * ((climate && climate.keep) || 1)
      : (slot.aged || 0) * 60 + (slot.turnsIn || 0);
    shelf = total > 0 ? clamp01((slot.turnsIn || 0) / total) : 0;
  }
  const shelfFill = document.getElementById("cg2-shelf-fill");
  shelfFill.style.width = shelf * 100 + "%";
  shelfFill.classList.toggle("warn", !!slot.turning || !!slot.sour);

  setText("cg2-aged", crateFmt(ct("Aged"), slot.aged || 0));
  const careOne = document.getElementById("cg2-care-one");
  careOne.innerText = crateFmt(ct("Care"), signed(slot.care));
  careOne.className =
    lim.goodCare !== undefined && slot.care >= lim.goodCare ? "gold"
      : lim.poorCare !== undefined && slot.care <= lim.poorCare ? "warn" : "";
}

function showCrateGauge(data) {
  const root = document.getElementById("crate-gauge");
  const g = data.gauge;
  if (!root || !g) return;

  /* Sent with the first reading after the card comes up */
  if (data.text || !crateUI.labelled) {
    if (data.text) crateUI.text = data.text;
    crateUI.labelled = true;
    setText("cg2-title", ct("Title"));
    setText("cg2-lock-text", ct("Locked"));
    setText("cg2-best-cap", ct("Best"));
    setText("cg2-care-lbl", ct("CareCore"));
    setText("cg2-age-lbl", ct("AgesCore"));
    setText("cg2-keep-lbl", ct("KeepsCore"));
    setText("cg2-rhythm-lbl", ct("RhythmCore"));
    setText("cg2-shelf-cap", ct("Shelf"));
    setText("cg2-wait-cap", ct("NextCheck"));
    setText("cg2-empty", ct("EmptyHint"));
  }
  if (data.limits) crateUI.limits = data.limits;
  if (Array.isArray(data.tiers)) crateUI.tiers = data.tiers.slice().reverse();
  const lim = crateUI.limits || {};

  const capacity = g.capacity || 12;
  const slots = Array.isArray(g.slots) ? g.slots : [];
  const count = g.count || slots.length;
  const selected = data.selected; /* 1-based, from Lua */

  /* Head */
  setText("cg2-count", count);
  setText("cg2-capacity", "/" + capacity);
  document.getElementById("cg2-lock").classList.toggle("on", !!g.locked);
  const best = g.best || (slots.length ? ct("Raw") : ct("Empty"));
  setText("cg2-best", best);
  document.getElementById("cg2-best-wrap").classList.toggle("gold", !!g.best);

  /* The rack */
  const rack = document.getElementById("cg2-rack");
  if (Number(rack.dataset.capacity) !== capacity) buildCrateRack(rack, capacity);
  const cells = rack.querySelectorAll(".cg2-slot");

  let anyPeak = false;
  let anyTurning = false;
  const seen = {};

  for (let i = 0; i < cells.length; i++) {
    const cell = cells[i];
    const slot = slots[i];
    const flaring = cell.classList.contains("tier-up") || cell.classList.contains("souring");
    let cls = "cg2-slot";

    if (!slot) {
      cls += " empty";
    } else {
      const rank = crateRank(slot);
      cell.style.setProperty("--liquor", liquorFor(rank));
      if (slot.sour) cls += " sour";
      else cls += " rank-" + rank;
      if (slot.peak && !slot.sour) { cls += " peak"; anyPeak = true; }
      if (slot.turning && !slot.sour) { cls += " turning"; anyTurning = true; }
      if (slot.target) cls += " target";
      if (selected === i + 1 && count > 0) cls += " selected";

      const id = slot.id !== undefined ? slot.id : "i" + i;
      seen[id] = true;
      const before = crateUI.lastRank[id];
      crateUI.lastRank[id] = rank;

      cell.className = cls + (flaring ? (cell.classList.contains("tier-up") ? " tier-up" : " souring") : "");
      if (before !== undefined && rank !== before) {
        if (rank < 0) flare(cell, id, "souring");
        else if (rank > before) flare(cell, id, "tier-up");
      }

      const progress = slot.sour || slot.peak ? (slot.sour ? 0 : 1) : clamp01(slot.progress);
      cell.lastChild.firstChild.style.width = Math.round(progress * 100) + "%";
      continue;
    }

    cell.className = cls;
    cell.style.removeProperty("--liquor");
    cell.lastChild.firstChild.style.width = "0%";
  }
  Object.keys(crateUI.lastRank).forEach((id) => { if (!seen[id]) delete crateUI.lastRank[id]; });

  /* Picking a bottle: the chevron that was pressed kicks, the ledger slides */
  const picker = document.getElementById("cg2-picker");
  picker.style.display = count > 1 ? "flex" : "none";
  if (count > 1 && selected) setText("cg2-pick", selected + " / " + count);

  const ledger = document.getElementById("cg2-ledger");
  if (selected && crateUI.lastSelected && selected !== crateUI.lastSelected) {
    const forward =
      selected === crateUI.lastSelected + 1 || (crateUI.lastSelected === count && selected === 1);
    replay(picker.querySelector(forward ? ".right" : ".left"), "kick");
    ledger.classList.remove("from-left", "from-right");
    replay(ledger, forward ? "from-right" : "from-left");
  }
  crateUI.lastSelected = selected || null;

  const climate = g.climate || {};
  showCrateLedger(selected && count > 0 ? slots[selected - 1] : null, climate);
  document.getElementById("cg2-empty").style.display = count > 0 ? "none" : "block";

  /* Where it stands */
  const climateRow = document.getElementById("cg2-climate");
  if (climate.label) {
    climateRow.style.display = "flex";
    climateRow.dataset.band = String(climate.label).toLowerCase();
    setText(
      "cg2-climate-text",
      crateFmt(ct("Cellar"), climate.label) +
        (climate.temp !== undefined && climate.temp !== null ? "  ·  " + Math.round(climate.temp) + "°C" : "") +
        (climate.sheltered ? "  ·  " + ct("Indoors") : "")
    );
  } else {
    climateRow.style.display = "none";
  }

  /* Cores */
  const careMax = Math.max(1, Math.abs(lim.careMax || 40));
  if (g.care !== undefined && g.care !== null) {
    setText("cg2-care", signed(g.care));
    setCrateRing("cg2-care-ring", Math.abs(g.care) / careMax);
    setCore(
      "cg2-core-care",
      lim.goodCare !== undefined && g.care >= lim.goodCare ? "good"
        : lim.poorCare !== undefined && g.care <= lim.poorCare ? "critical"
        : g.care < 0 ? "poor" : ""
    );
  } else {
    setText("cg2-care", "–");
    setCrateRing("cg2-care-ring", 0);
    setCore("cg2-core-care", "off");
  }

  const ageMax = lim.ageMax || 1.5;
  const keepMax = lim.keepMax || 1.5;
  const age = climate.age || 1;
  const keep = climate.keep || 1;
  setText("cg2-age", rate(age));
  setCrateRing("cg2-age-ring", age / ageMax);
  setCore("cg2-core-age", age > 1.001 ? "good" : age < 0.999 ? "cold" : "");
  setText("cg2-keep", rate(keep));
  setCrateRing("cg2-keep-ring", keep / keepMax);
  setCore("cg2-core-keep", keep > 1.001 ? "good" : keep < 0.999 ? "poor" : "");

  const rhythm = g.rhythm || 1;
  const rhythmMax = Math.max(1.01, lim.rhythmMax || 2);
  setText("cg2-rhythm", rate(rhythm));
  setCrateRing("cg2-rhythm-ring", (rhythm - 1) / (rhythmMax - 1));
  setCore("cg2-core-rhythm", rhythm > 1.001 ? "good" : "off");

  /* What it wants */
  const call = document.getElementById("cg2-call");
  const wait = document.getElementById("cg2-wait");
  if (g.tendDue) {
    call.style.display = "block";
    wait.style.display = "none";
    call.classList.toggle("hazard", !!g.hazard);
    call.classList.toggle("urgent", (g.windowLeft || 0) <= 10);
    setText("cg2-call-what", (g.hazard ? "! " : "") + String(g.activityLabel || g.activity || "").toUpperCase());
    setText("cg2-call-time", clock(g.windowLeft));
    const windowSecs = lim.window || 60;
    document.getElementById("cg2-call-fill").style.width = clamp01((g.windowLeft || 0) / windowSecs) * 100 + "%";
  } else {
    call.style.display = "none";
    if (g.nextIn !== undefined && g.nextIn !== null) {
      wait.style.display = "block";
      setText("cg2-wait-time", clock(g.nextIn));
      const every = lim.every || 150;
      document.getElementById("cg2-wait-fill").style.width = clamp01(1 - g.nextIn / every) * 100 + "%";
    } else {
      wait.style.display = "none";
    }
  }

  /* The rule under the title follows the crate's mood */
  root.dataset.state =
    g.tendDue && g.hazard ? "hazard"
      : g.tendDue ? "tend"
      : anyTurning ? "turning"
      : anyPeak ? "peak"
      : "idle";

  const wasVisible = root.classList.contains("visible");
  root.classList.add("visible");
  if (!wasVisible) radialHintPlace(); /* the F2 tag moves on top of it */
}

function hideCrateGauge() {
  const root = document.getElementById("crate-gauge");
  if (root) root.classList.remove("visible");
  radialHintPlace(); /* the F2 tag back to its own corner */
  crateUI.lastSelected = null;
  crateUI.lastRank = {};
}

/* ------------------------------------------------------------------ */
/*  Notifications (GSC.Notify)                                         */
/*                                                                     */
/*  Paper notes stacked top right, newest on top. The same text while  */
/*  it is still up gets a counter instead of a second note, so a still */
/*  telling everyone at it the same thing cannot bury the screen.      */
/* ------------------------------------------------------------------ */
const NOTIFY_FADE_MS = 360;
const notifyLive = [];

/* The wax seals */
const NOTIFY_SEALS = {
  fire: "M12 3c1.2 3.2 4.5 4.6 4.5 9a4.5 4.5 0 0 1-9 0c0-1.9.8-3.1 1.8-4.1.2 1.9 1.1 2.9 2.2 2.9C11.2 8.2 11 5.6 12 3z",
  water: "M12 3.5s-6 6.6-6 10.7a6 6 0 0 0 12 0c0-4.1-6-10.7-6-10.7z M9.4 14.6a2.7 2.7 0 0 0 2.4 2.6",
  wash: "M4 10.5h16 M5.2 10.5v4.2a6.8 4.3 0 0 0 13.6 0v-4.2 M8.5 7.6c0-1.4 1.1-1.8 1.1-3.1 M12.2 7.6c0-1.4 1.1-1.8 1.1-3.1 M15.9 7.6c0-1.4 1.1-1.8 1.1-3.1",
  bottle: "M10.2 3h3.6v3.6l2.2 3.2v9.6a1.1 1.1 0 0 1-1.1 1.1H9.1A1.1 1.1 0 0 1 8 19.4V9.8l2.2-3.2z M8 13.2h8",
  tree: "M12.3 21c.2-3.4-.4-6.6-1.2-9.6 M11.1 11.4C9 8.5 5.6 8.6 3.6 10.4 M11.1 11.4c2.5-3 6.1-2.6 8.4-.6 M11.1 11.4C10.4 8 7.6 5.9 4.9 5.7 M11.1 11.4c1.2-3.5 4.4-5.3 7.4-5",
  crate: "M4 7.5h16v11.5H4z M4 7.5l2.6-3h10.8l2.6 3 M4 13.2h16 M9.3 7.5V19 M14.7 7.5V19",
  crew: "M9 11.2a3 3 0 1 0 0-6 3 3 0 0 0 0 6z M3.5 19.8c0-3.3 2.5-5.6 5.5-5.6s5.5 2.3 5.5 5.6 M16 11a2.5 2.5 0 1 0 0-5 M16.2 14.2c2.6.1 4.6 2.2 4.6 5.4",
  guard: "M12 3.2l7 2.8v5.6c0 4.3-2.9 7.5-7 9.2-4.1-1.7-7-4.9-7-9.2V6z M12 8v5.5 M12 16v.4",
  law: "M12 3.2l2.5 5.3 5.8.7-4.3 4 1.1 5.8L12 16.2 6.9 19l1.1-5.8-4.3-4 5.8-.7z",
  danger: "M12 3.4l9.3 16.4H2.7z M12 9.6v4.6 M12 17v.4",
  still: "M7.2 4h9.6c1.6 3.1 1.6 12.9 0 16H7.2c-1.6-3.1-1.6-12.9 0-16z M5.9 9h12.2 M5.9 15h12.2",
  note: "M19.5 4.5C13.8 5.3 9.6 9.4 7.8 15.6L6.2 19.5 M7.8 15.6c2.9-1 5.1-3.2 6.4-6.1 M5 19.5h7.5",
};

function notifySeal(icon) {
  const seal = document.createElement("div");
  seal.className = "notify-seal";
  const ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  const path = document.createElementNS(ns, "path");
  path.setAttribute("d", NOTIFY_SEALS[icon] || NOTIFY_SEALS.note);
  svg.appendChild(path);
  seal.appendChild(svg);
  return seal;
}

/* The text, with its figures set bold in the seal's colour */
const NOTIFY_FIGURE = /(\d+\/\d+|\d+[x×](?=\s)|[x×]\d+(?:[.,]\d+)?|[+\-−]?\d+(?:[.,]\d+)?(?:%|\s?(?:ml|s|m)\b)?)/g;

function notifyRichText(target, text) {
  let last = 0;
  String(text).replace(NOTIFY_FIGURE, (match, _g, offset) => {
    if (offset > last) target.appendChild(document.createTextNode(text.slice(last, offset)));
    const b = document.createElement("b");
    b.className = "notify-figure";
    b.textContent = match;
    target.appendChild(b);
    last = offset + match.length;
    return match;
  });
  if (last < text.length) target.appendChild(document.createTextNode(text.slice(last)));
}

/* Light (or relight) the fuse: it burns down over the note's time */
function notifyLightFuse(entry, ms) {
  const fuse = entry.el.querySelector(".notify-fuse");
  if (!fuse) return;
  const old = fuse.firstChild;
  const flame = document.createElement("i");
  if (old) fuse.replaceChild(flame, old); else fuse.appendChild(flame);
  entry.el.style.setProperty("--life", Math.max(1200, ms || 4000) + "ms");
}

function notifyRemove(entry) {
  const i = notifyLive.indexOf(entry);
  if (i !== -1) notifyLive.splice(i, 1);
  if (entry.timer) clearTimeout(entry.timer);
  entry.timer = null;

  /* lift away, and let the notes below slide up into the room it leaves */
  const el = entry.el;
  el.style.height = el.offsetHeight + "px";
  void el.offsetHeight;
  el.classList.remove("show");
  el.classList.add("leaving");
  setTimeout(() => el.remove(), NOTIFY_FADE_MS);
}

function notifyArm(entry, ms) {
  if (entry.timer) clearTimeout(entry.timer);
  entry.timer = setTimeout(() => notifyRemove(entry), Math.max(1200, ms || 4000));
}

function showNotify(data) {
  const stack = document.getElementById("notify-stack");
  if (!stack || !data.text) return;

  const kind = data.kind === "warning" || data.kind === "alert" ? data.kind : "info";
  const icon = NOTIFY_SEALS[data.icon] ? data.icon : kind === "alert" ? "law" : "note";
  const key = kind + "|" + (data.title || "") + "|" + data.text;

  /* Already on screen: count it, relight its fuse, give it fresh time */
  const same = notifyLive.find((e) => e.key === key);
  if (same) {
    same.count += 1;
    const badge = same.el.querySelector(".notify-count");
    badge.innerText = "×" + same.count;
    badge.classList.add("on");
    cgPulse(badge, "pop");
    cgPulse(same.el, "bump");
    if (data.fuse !== false) notifyLightFuse(same, data.ms);
    notifyArm(same, data.ms);
    return;
  }

  const el = document.createElement("div");
  const black = data.style !== "paper";
  el.className = "notify-note kind-" + kind + " seal-" + icon + (black ? " style-black" : "");

  if (!black) cgEl("span", "notify-tack", el); /* the brass tack is the paper's */
  el.appendChild(notifySeal(icon));

  const body = cgEl("div", "notify-body", el);
  if (data.title) cgEl("div", "notify-title", body).innerText = data.title;
  notifyRichText(cgEl("div", "notify-text", body), data.text);

  cgEl("span", "notify-count", el);
  if (data.fuse !== false) cgEl("div", "notify-fuse", el);

  stack.prepend(el);
  const entry = { el, key, count: 1, timer: null };
  notifyLive.unshift(entry);
  if (data.fuse !== false) notifyLightFuse(entry, data.ms);

  /* Oldest go first once the stack is full */
  const max = Math.max(1, data.maxVisible || 4);
  while (notifyLive.length > max) notifyRemove(notifyLive[notifyLive.length - 1]);

  /* (a note pushed out by a burst before it ever showed stays gone) */
  requestAnimationFrame(() => { if (!el.classList.contains("leaving")) el.classList.add("show"); });
  notifyArm(entry, data.ms);
}

/* ---o[ The Kasippu radial menu (GSC.Radial) - the menu itself is vendor/radialmenu.js (ez_radialmenu, GPL-3.0) ]o--- */
let gscRadial = null;
let gscRadialObserver = null;
let gscRadialText = {};    /* { place, hint } from Lua */
let gscRadialSound = true; /* Config.Radial.Sound */
let gscRadialAudio = null;
let gscRadialTickAt = 0;
const GSC_SVGNS = "http://www.w3.org/2000/svg";

function postRadialSelect(id) {
  return fetch(`https://${GetParentResourceName()}/radialSelect`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({ id: id }),
  }).catch(() => {});
}

/* a soft wooden tick when the pick moves (made here: no sound file) */
function radialTick() {
  if (!gscRadialSound) return;
  const now = performance.now();
  if (now - gscRadialTickAt < 35) return;
  gscRadialTickAt = now;
  try {
    gscRadialAudio = gscRadialAudio || new (window.AudioContext || window.webkitAudioContext)();
    const ctx = gscRadialAudio;
    const t = ctx.currentTime;
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.type = "triangle";
    osc.frequency.setValueAtTime(1400, t);
    osc.frequency.exponentialRampToValueAtTime(620, t + 0.05);
    gain.gain.setValueAtTime(0.03, t);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.07);
    osc.connect(gain).connect(ctx.destination);
    osc.start(t);
    osc.stop(t + 0.08);
  } catch (e) { /* no audio here: stay silent */ }
}

function radialEl(tag, attrs, parent) {
  const el = document.createElementNS(GSC_SVGNS, tag);
  for (const k in attrs) el.setAttribute(k, attrs[k]);
  if (parent) parent.appendChild(el);
  return el;
}

/* a wedge's direction in degrees (SVG: 0 = right, clockwise), from its label at the wedge's middle */
function radialAngle(g) {
  const t = g && g.querySelector("text");
  if (!t) return null;
  return Math.atan2(parseFloat(t.getAttribute("y")), parseFloat(t.getAttribute("x"))) * 180 / Math.PI;
}

function radialArc(r, a0, a1) {
  const p = (a) => [(r * Math.cos(a * Math.PI / 180)).toFixed(2), (r * Math.sin(a * Math.PI / 180)).toFixed(2)];
  const [x0, y0] = p(a0);
  const [x1, y1] = p(a1);
  return `M${x0} ${y0}A${r} ${r} 0 0 1 ${x1} ${y1}`;
}

/* every ring the menu builds */
/* A wedge's name, readable */
const RADIAL_FONT = 3.3;
const RADIAL_CHAR = 0.74;
function radialWrapLabel(label, svg) {
  const text = (label.textContent || "").trim();
  const x = parseFloat(label.getAttribute("x")) || 0, y = parseFloat(label.getAttribute("y")) || 0;
  const count = Math.max(3, svg.querySelectorAll("g.sector, g.dummy").length);
  const room = Math.hypot(x, y) * (2 * Math.PI / count) * 0.82;
  const fits = Math.max(4, Math.floor(room / (RADIAL_FONT * RADIAL_CHAR)));
  let parts = [text];
  if (text.length > fits && text.includes(" ")) {
    let best = -1;
    for (let i = 0; i < text.length; i++) {
      if (text[i] === " " && (best < 0 || Math.abs(i - text.length / 2) < Math.abs(best - text.length / 2))) best = i;
    }
    parts = [text.slice(0, best), text.slice(best + 1)];
  }
  const longest = Math.max(...parts.map((p) => p.length));
  if (longest > fits) label.style.fontSize = (RADIAL_FONT * fits / longest).toFixed(2) + "px";
  if (parts.length > 1) {
    label.textContent = "";
    parts.forEach((part, i) => {
      const span = document.createElementNS("http://www.w3.org/2000/svg", "tspan");
      span.setAttribute("x", String(x));
      if (i > 0) span.setAttribute("dy", "1.15em");
      span.textContent = part;
      label.appendChild(span);
    });
  }
  return parts.length;
}

function radialDecorate(svg) {
  if (svg.dataset.gsc) return;
  svg.dataset.gsc = "1";

  const slots = svg.querySelectorAll("g.sector, g.dummy").length || 3;
  const step = 360 / slots;

  const bezel = radialEl("g", { class: "gsc-bezel" });
  svg.insertBefore(bezel, svg.firstChild);
  radialEl("circle", { r: 56.5, class: "ring" }, bezel);
  radialEl("circle", { r: 59, class: "ring faint" }, bezel);
  let ticks = "";
  for (let a = 0; a < 360; a += 6) {
    const r1 = a % 30 === 0 ? 59 : 57.6;
    const c = Math.cos(a * Math.PI / 180), s = Math.sin(a * Math.PI / 180);
    ticks += `M${(56.5 * c).toFixed(2)} ${(56.5 * s).toFixed(2)}L${(r1 * c).toFixed(2)} ${(r1 * s).toFixed(2)}`;
  }
  radialEl("path", { d: ticks, class: "ticks" }, bezel);
  radialEl("path", { class: "gsc-pointer", d: radialArc(57.75, -step * 0.38, step * 0.38) }, bezel);

  const badges = radialEl("g", { class: "gsc-badges" }, svg);
  svg.querySelectorAll("g.sector").forEach((g, n) => {
    g.style.setProperty("--i", n);

    /* centre icon + label as one block on the wedge's middle point */
    const label = g.querySelector(":scope > text");
    const icon = g.querySelector(":scope > svg");
    const lines = label ? radialWrapLabel(label, svg) : 1;
    if (label && icon) {
      const cx = parseFloat(label.getAttribute("x")), cy = parseFloat(label.getAttribute("y"));
      const lift = lines > 1 ? 2.2 : 0;
      icon.removeAttribute("transform");
      icon.setAttribute("x", (cx - 5).toFixed(2));
      icon.setAttribute("y", (cy - 7.4 - lift).toFixed(2)); /* the 10 x 10 icon box */
      label.setAttribute("transform", `translate(0,${(6 - lift).toFixed(2)})`);
    } else if (icon) { /* an icon with no label: dead centre */
      icon.removeAttribute("transform");
    }

    const idx = parseInt(g.getAttribute("data-index"));
    const ang = radialAngle(g);
    if (ang === null || isNaN(idx) || idx > 8) return; /* keys 1 - 9 only */
    const rad = ang * Math.PI / 180;
    const b = radialEl("text", {
      x: (62.5 * Math.cos(rad)).toFixed(2), y: (62.5 * Math.sin(rad) + 0.9).toFixed(2),
      "text-anchor": "middle", class: "gsc-badge", "data-for": idx,
    }, badges);
    b.textContent = String(idx + 1);
  });
}

/* the pointer swings to its new wedge the short way round */
function radialSwing(ptr, target) {
  let from = parseFloat(ptr.dataset.angle);
  if (isNaN(from)) from = target;
  const to = from + ((((target - from) % 360) + 540) % 360 - 180);
  ptr.dataset.angle = to;
  const started = performance.now();
  const run = (now) => {
    const k = Math.min(1, (now - started) / 170);
    const e = 1 - Math.pow(1 - k, 3);
    ptr.setAttribute("transform", `rotate(${(from + (to - from) * e).toFixed(2)})`);
    if (k < 1 && ptr.dataset.angle == String(to)) requestAnimationFrame(run);
  };
  requestAnimationFrame(run);
}

/* caption, badges and pointer follow whatever the current ring has picke */
function radialSync() {
  const m = gscRadial;
  if (!m || !m.currentMenu) return;
  const svg = m.currentMenu;
  const sel = svg.querySelector("g.sector.selected");
  const idx = sel ? parseInt(sel.getAttribute("data-index")) : -1;
  const item = (m.levelItems || [])[idx];

  const cap = m.holder && m.holder.querySelector(".gsc-caption");
  if (cap) {
    cap.querySelector(".place").textContent = svg.dataset.place || gscRadialText.place || "";
    const title = cap.querySelector(".title");
    const text = item ? item.title : "";
    if (title.textContent !== text) {
      title.textContent = text;
      title.classList.remove("swap");
      void title.offsetWidth; /* restart the little swap animation */
      title.classList.add("swap");
    }
  }

  svg.querySelectorAll(".gsc-badge").forEach((b) => b.classList.toggle("on", parseInt(b.dataset.for) === idx));

  const ptr = svg.querySelector(".gsc-pointer");
  const ang = radialAngle(sel);
  if (ptr && ang !== null) radialSwing(ptr, ang);
}

function radialOpen(data) {
  const root = document.getElementById("gsc-radial");
  if (gscRadial) radialClose();
  root.classList.add("open");
  gscRadialText = data.text || {};
  gscRadialSound = data.sound !== false;

  const size = data.size || 375;
  gscRadial = new RadialMenu({
    parent: root,
    size: size,
    menuItems: data.items || [],
    onClick: (item) => {
      if (!item) return;
      if (item.items) {
        if (gscRadial.currentMenu) gscRadial.currentMenu.dataset.place = item.title || "";
        radialSync();
        return;
      }
      const sel = gscRadial.currentMenu && gscRadial.currentMenu.querySelector("g.sector.selected");
      if (sel) sel.classList.add("fired");
      postRadialSelect(item.id);
      gscRadial.close(true); /* tells Lua radialClose: focus off */
    },
  });
  const m = gscRadial;

  /* the caption over the centre plate */
  const cap = document.createElement("div");
  cap.className = "gsc-caption";
  cap.style.setProperty("--rs", String(size / 375));
  cap.innerHTML = '<div class="place"></div><div class="title"></div><div class="rule"></div><div class="hint"></div>';
  cap.querySelector(".hint").textContent = gscRadialText.hint || "";
  m.holder.appendChild(cap);

  /* every pick, by mouse, wheel or key, moves the caption, pointer and num */
  const pick = m.setSelectedIndex.bind(m);
  m.setSelectedIndex = (index) => {
    const before = m.getSelectedIndex();
    pick(index);
    if (m.getSelectedIndex() !== before) radialTick();
    radialSync();
  };
  /* back to the ring before: it becomes current once its fade is over */
  const back = m.returnToParentMenu.bind(m);
  m.returnToParentMenu = () => { back(); setTimeout(radialSync, 260); };

  /* closing: Lua answers with radialClose; if that answer never comes, take it off the screen anyway */
  const shut = m.close.bind(m);
  m.close = (bool) => {
    shut(bool);
    setTimeout(() => { if (gscRadial === m) radialClose(); }, 400);
  };

  /* hover picks: aim with the mouse, click to do it */
  m.holder.addEventListener("mouseover", (event) => {
    const g = event.target.closest && event.target.closest("g.sector");
    if (!g || !m.currentMenu || !m.currentMenu.contains(g)) return;
    const index = parseInt(g.getAttribute("data-index"));
    if (!isNaN(index) && index !== m.getSelectedIndex()) m.setSelectedIndex(index);
  });

  gscRadialObserver = new MutationObserver((records) => {
    for (const r of records) {
      r.addedNodes.forEach((node) => {
        if (node.tagName && node.tagName.toLowerCase() === "svg" && node.classList.contains("menu")) radialDecorate(node);
      });
    }
    requestAnimationFrame(radialSync);
  });
  gscRadialObserver.observe(m.holder, { childList: true });

  m.open();
}

/* Lua closed it (picked, Esc, or the player can no longer use it): no post back */
function radialClose() {
  document.getElementById("gsc-radial").classList.remove("open");
  if (gscRadialObserver) { gscRadialObserver.disconnect(); gscRadialObserver = null; }
  if (gscRadial) { gscRadial.destroy(); gscRadial = null; }
}

/* A timed pick (seize, pour, pick up): a bar that fills over data.ms */
function radialHold(data) {
  const box = document.getElementById("gsc-radial-hold");
  const fill = document.getElementById("gsc-radial-hold-fill");
  document.getElementById("gsc-radial-hold-label").textContent = data.label || "";
  fill.style.transition = "none";
  fill.style.width = "0%";
  box.classList.add("show");
  requestAnimationFrame(() => requestAnimationFrame(() => {
    fill.style.transition = `width ${Math.max(0, data.ms || 0)}ms linear`;
    fill.style.width = "100%";
  }));
}

/* the "F2  Kasippu Menu" tag: only while the player stands at a still, crate or buyer (GSC.Radial.Hint) */
function radialHint(data) {
  const box = document.getElementById("gsc-radial-hint");
  if (data.show) {
    document.getElementById("gsc-radial-hint-key").textContent = data.key || "";
    document.getElementById("gsc-radial-hint-label").textContent = data.label || "";
  }
  box.classList.toggle("show", !!data.show);
  if (data.show) radialHintPlace();
}

/* At a still or a crate the tag sits right on top of its gauge, lit gold */
function radialHintPlace() {
  const box = document.getElementById("gsc-radial-hint");
  if (!box || !box.classList.contains("show")) return;
  let gauge = null;
  for (const id of ["barrel-gauge", "crate-gauge"]) {
    const el = document.getElementById(id);
    if (el && el.classList.contains("visible")) { gauge = el; break; }
  }
  box.classList.toggle("on-gauge", !!gauge);
  if (!gauge) {
    box.style.left = "";
    box.style.top = "";
    return;
  }
  /* offsetLeft / offsetTop: where the gauge stands, not where its slide-in transform has it this frame */
  const h = box.offsetHeight || 32;
  box.style.left = Math.round(gauge.offsetLeft + 10) + "px";
  box.style.top = Math.max(8, Math.round(gauge.offsetTop - h - 4)) + "px";
}

function radialHoldEnd() {
  document.getElementById("gsc-radial-hold").classList.remove("show");
}

/* GSC.UiGuard */
function uiReset(all) {
  const step = (fn) => { try { fn(); } catch (e) { } };
  step(() => { setJournalVisible(false); renderMashSlip(null); renderCrewSlip(null); });
  step(() => radialClose());
  step(() => radialHoldEnd());
  step(() => cgStop());
  step(() => pushPanelMessage({ open: false }));
  step(() => hideLedger());
  step(() => hideTastePicker());
  step(() => document.body.classList.remove("mouse-game", "journal-open"));
  if (all) {
    step(() => hideGauge());
    step(() => hideCrateGauge());
  }
}

window.addEventListener("message", (event) => {
  const data = event.data;

  if (data.action === "notify") {
    showNotify(data);
    return;
  } else if (data.action === "radialOpen") {
    radialOpen(data);
    return;
  } else if (data.action === "radialClose") {
    radialClose();
    return;
  } else if (data.action === "radialHold") {
    radialHold(data);
    return;
  } else if (data.action === "radialHint") {
    radialHint(data);
    return;
  } else if (data.action === "radialHoldEnd") {
    radialHoldEnd();
    return;
  } else if (data.action === "pushPanel") {
    pushPanelMessage(data);
  } else if (data.action === "showGauge") {
    showGauge(data);
    return;
  } else if (data.action === "hideGauge") {
    hideGauge();
    return;
  } else if (data.action === "showCrateGauge") {
    showCrateGauge(data);
    return;
  } else if (data.action === "hideCrateGauge") {
    hideCrateGauge();
    return;
  } else if (data.action === "startMinigame") {
    cgStart(data);
    return;
  } else if (data.action === "cancelMinigame") {
    cgStop();
    return;
  } else if (data.action === "tastePicker") {
    showTastePicker(data);
    return;
  } else if (data.action === "tastePickerClose") {
    hideTastePicker();
    return;
  } else if (data.action === "tastingCard") {
    showTastingCard(data);
    return;
  } else if (data.action === "buyerLedger") {
    showLedger(data);
    return;
  } else if (data.action === "buyerLedgerDone") {
    ledgerDone(data);
    return;
  } else if (data.action === "buyerLedgerClose") {
    hideLedger();
    return;
  } else if (data.action === "uiReset") {
    uiReset(!!data.all);
    return;
  }

  if (data.action === "playSound") {
    playCustomSound(data.file, data.volume);
  } else if (data.action === "stopSound") {
    if (currentAmbientSound) {
      currentAmbientSound.pause();
      currentAmbientSound.src = "";
      currentAmbientSound = null;
    }
  }

  if (data.action === "openMyUI") {
    hideGauge();
    readOnlyBook = !!data.readOnly;
    document.body.classList.toggle("journal-readonly", readOnlyBook);
    activeBarrelId = data.barrelId;
    kassippuConfig = data.recipies || {};
    recipeOrder = Array.isArray(data.recipeOrder) ? data.recipeOrder : Object.keys(kassippuConfig);
    itemImagePath = data.itemImages || "";
    stageNames = data.stages || {};
    currentStage = data.stage || "IDLE";

    currentRecipe = data.defaultRecipe || recipeKeys()[0] || "";

    renderCrewSlip(null);
    renderTarp(data.tarp || null);
    renderFittingsSlip(data.fittings || null);
    setJournalVisible(true);
    initJournal();
    updateStatus(data);
  } else if (readOnlyBook && document.body.classList.contains("journal-open")
      && ["mixPreview", "tarpState", "crewRoster", "fittingsState"].includes(data.action)) {
  } else if (data.action === "updateStatus" || data.action === "updateHeatUI") {
    updateStatus(data);
  } else if (data.action === "mixPreview") {
    if (data.recipeId === currentRecipe && canMixNow()) {
      mashPreview = data.preview || null;
      renderMashSlip(mashPreview);
      refreshStartButton();
    }
  } else if (data.action === "tarpState") {
    renderTarp(data.tarp || null);
  } else if (data.action === "fittingsState") {
    renderFittingsSlip(data.fittings || null);
  } else if (data.action === "crewRoster") {
    renderCrewSlip(data.roster || null, data.text);
  } else if (data.action === "closeUI") {
    setJournalVisible(false);
    renderMashSlip(null);
    renderCrewSlip(null);
  } else if (data.action === "treeLoot") {
    showLoot(data);
  }
});

function closeMenu() {
  setJournalVisible(false);
  renderMashSlip(null);
  renderCrewSlip(null);

  const keys = recipeKeys();
  if (keys.length > 0) {
    currentRecipe = keys[0];
  }

  fetch(`https://${GetParentResourceName()}/closeUI`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=UTF-8",
    },
    body: JSON.stringify({}),
  });
}

/* The tarp's line in the ledger */
let tarpWait = null;

function renderTarp(tarp) {
  const row = document.getElementById("tarp-row");
  if (!row) return;
  row.hidden = !tarp;
  if (!tarp) return;

  const t = tarp.text || {};
  document.getElementById("tarp-label").innerText = t.Label || "Tarp";
  document.getElementById("tarp-text").innerText = tarp.up ? t.Up || "Rigged" : t.Down || "None";

  const btn = document.getElementById("tarp-btn");
  btn.innerText = tarp.up ? t.TakeDown || "Take Down" : t.Rig || "Rig Tarp";
  btn.disabled = false;
  clearTimeout(tarpWait);
}

function toggleTarp() {
  const btn = document.getElementById("tarp-btn");
  btn.disabled = true;
  /* Back on when the tarp changes, or after a moment if the server said no */
  clearTimeout(tarpWait);
  tarpWait = setTimeout(() => (btn.disabled = false), 1500);

  fetch(`https://${GetParentResourceName()}/toggleTarp`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({}),
  });
}

function startMixing() {
  fetch(`https://${GetParentResourceName()}/startMixingNUI`, {
    method: "POST",
    body: JSON.stringify({
      recipeId: currentRecipe,
      barrelId: activeBarrelId,
    }),
  });
  closeMenu();
}

document.onkeyup = (e) => {
  if (e.key === "Escape" && ledger) {
    buyerCancel();
    return;
  }
  if (e.key === "Escape" && tastePickerOpen) {
    hideTastePicker();
    tasteCancel();
    return;
  }
  /* only the journal's own Esc */
  if (e.key === "Escape" && !skillGame && !gscRadial && document.body.classList.contains("journal-open")) closeMenu();
};

function playCustomSound(fileName, volume) {
  if (currentAmbientSound) {
    currentAmbientSound.pause();
    currentAmbientSound.src = "";
    currentAmbientSound = null;
  }

  let soundPath = `./assets/audio/${fileName}`;
  currentAmbientSound = new Audio(soundPath);

  currentAmbientSound.volume = volume || 0.5;
  currentAmbientSound.loop = true;

  currentAmbientSound.play().catch((error) => {
    console.error("Audio Error:", error);
    console.log("Failed Path:", soundPath);
  });
}

/* ------------------------------------------------------------------ */
/*  Minigames                                                          */
/*                                                                     */
/*  The script's own minigames, in place of syn_minigame and           */
/*  legends-keypress, for the crate and the trees alike. GSC.Minigame  */
/*  opens one with keyboard focus and no cursor, waits on              */
/*  minigameResult, then takes focus back. One engine, six games       */
/*  ("Minigames" in config/crates.lua has every setting):            */
/*    dial      a mark sweeps round a dial - SPACE inside the gilt arc */
/*    bar       the same along a straight bar, swinging back and forth */
/*    pins      lockpick - lift each pin to its line in turn           */
/*    hold      hold SPACE to keep the level inside a drifting band    */
/*    sequence  press the keys shown, in order, against the clock     */
/*    reach     hand over hand - A / D as the swing passes each hold   */
/*    taste     nose (hold SPACE, let go in the gold), then the palate */
/*              (three letters in time) - reports a 0 - 1 score too    */
/*    bottle    pour each bottle to the chalk mark (hold SPACE), cork  */
/*              it (SPACE in the gold) - reports each bottle's outcome */
/*  ESC gives up, which counts as a failure.                           */
/* ------------------------------------------------------------------ */
let skillGame = null;

function cgEl(tag, cls, parent) {
  const el = document.createElement(tag);
  if (cls) el.className = cls;
  if (parent) parent.appendChild(el);
  return el;
}

function cgPct(v) {
  return Math.max(0, Math.min(100, v * 100)) + "%";
}

/* Restart a one-shot CSS animation on an element */
function cgPulse(el, cls) {
  el.classList.remove(cls);
  void el.offsetWidth;
  el.classList.add(cls);
}

function cgFlash(hit) {
  const stage = document.getElementById("cg-stage");
  stage.classList.remove("flash-hit", "flash-miss");
  cgPulse(stage, hit ? "flash-hit" : "flash-miss");
}

function cgBanner(text, cls) {
  const banner = document.getElementById("cg-banner");
  banner.className = "cg-banner" + (text ? " show " + (cls || "") : "");
  banner.innerText = text || "";
}

/* Swings v between 0 and 1, bouncing off the ends */
function cgSwing(g, dt) {
  g.pos += g.dir * g.speed * dt;
  if (g.pos > 1) { g.pos = 2 - g.pos; g.dir = -1; }
  if (g.pos < 0) { g.pos = -g.pos; g.dir = 1; }
}

/* A miss: a strike against the allowance, and the game is lost past it */
function cgStrike() {
  const g = skillGame;
  g.misses += 1;
  cgFlash(false);
  cgRenderFoot();
  if (g.misses > g.strikes) cgFinish(false);
}

function cgRenderFoot() {
  const g = skillGame;
  const pips = document.getElementById("cg-pips");
  const strikes = document.getElementById("cg-strikes");

  pips.innerHTML = "";
  if (g.total > 1) {
    for (let i = 0; i < g.total; i++) cgEl("i", i < g.done ? "on" : "", pips);
  }

  strikes.innerHTML = "";
  if (g.strikes > 0) {
    cgEl("span", "", strikes).innerText = (g.text.misses || "Misses") + " ";
    for (let i = 0; i < g.strikes; i++) cgEl("i", i < g.misses ? "used" : "", strikes);
  }
}

/* ---------------------------------------------------------------- */
/*  The games. Each has init (build the stage), update (per frame),  */
/*  render, and press (SPACE down) or key (any other key down).      */
/* ---------------------------------------------------------------- */
const CG_MODES = {
  /* ---- A mark sweeping round a dial ---- */
  dial: {
    init(g, stage) {
      g.total = g.spec.rounds || 3;
      g.width = g.spec.zone || 0.16;
      g.speed = g.spec.speed || 0.5;
      g.pos = Math.random();
      g.dir = 1;
      const face = cgEl("div", "cg-dial", stage);
      g.zoneEl = cgEl("div", "cg-dial-zone", face);
      cgEl("div", "cg-dial-ticks", face);
      g.needleEl = cgEl("div", "cg-dial-needle", face);
      cgEl("div", "cg-dial-hub", face);
      this.newZone(g);
    },
    /* at least a quarter turn ahead of the mark, so a round is never free */
    newZone(g) {
      g.zone = (g.pos + 0.25 + Math.random() * (0.5 - g.width)) % 1;
    },
    update(g, dt) {
      g.pos = (g.pos + g.dir * g.speed * dt + 1) % 1;
    },
    render(g) {
      const from = g.zone * 360;
      const arc = g.width * 360;
      g.zoneEl.style.background =
        `conic-gradient(from ${from}deg, var(--cg-zone) 0deg ${arc}deg, transparent ${arc}deg 360deg)`;
      g.needleEl.style.transform = `rotate(${g.pos * 360}deg)`;
    },
    press(g) {
      if ((g.pos - g.zone + 1) % 1 <= g.width) {
        g.done += 1;
        cgFlash(true);
        cgRenderFoot();
        if (g.done >= g.total) return cgFinish(true);

        g.width *= g.spec.shrink || 0.85;
        g.speed *= g.spec.speedUp || 1.15;
        if (g.spec.reverse !== false) g.dir *= -1;
        this.newZone(g);
      } else {
        cgStrike();
      }
    },
  },

  /* ---- The same, along a straight bar ---- */
  bar: {
    init(g, stage) {
      g.total = g.spec.rounds || 1;
      g.width = g.spec.zone || 0.14;
      g.speed = g.spec.speed || 1.0;
      g.pos = 0;
      g.dir = 1;
      const track = cgEl("div", "cg-bar", stage);
      g.zoneEl = cgEl("div", "cg-bar-zone", track);
      g.markEl = cgEl("div", "cg-bar-mark", track);
      this.newZone(g);
    },
    /* well clear of where the mark is now */
    newZone(g) {
      for (let i = 0; i < 20; i++) {
        g.zone = 0.05 + Math.random() * (0.9 - g.width);
        if (Math.abs(g.zone + g.width / 2 - g.pos) > 0.3) break;
      }
    },
    update(g, dt) {
      cgSwing(g, dt);
    },
    render(g) {
      g.zoneEl.style.left = cgPct(g.zone);
      g.zoneEl.style.width = cgPct(g.width);
      g.markEl.style.left = cgPct(g.pos);
    },
    press(g) {
      if (g.pos >= g.zone && g.pos <= g.zone + g.width) {
        g.done += 1;
        cgFlash(true);
        cgRenderFoot();
        if (g.done >= g.total) return cgFinish(true);

        g.width *= g.spec.shrink || 0.85;
        g.speed *= g.spec.speedUp || 1.15;
        this.newZone(g);
      } else {
        cgStrike();
      }
    },
  },

  /* ---- Lockpick: lift each pin to the shear line ---- */
  pins: {
    init(g, stage) {
      g.total = g.spec.pins || 4;
      g.width = g.spec.zone || 0.14;
      g.speed = g.spec.speed || 1.2;
      g.pos = 0;
      g.dir = 1;
      g.cols = [];
      const lock = cgEl("div", "cg-lock", stage);
      for (let i = 0; i < g.total; i++) {
        const col = cgEl("div", "cg-pin", lock);
        const line = cgEl("div", "cg-pin-line", col);
        const pin = cgEl("div", "cg-pin-body", col);
        /* each pin sets at its own height, in the upper half */
        const at = 0.5 + Math.random() * (0.42 - g.width);
        g.cols.push({ col, line, pin, at, height: 0 });
      }
    },
    update(g, dt) {
      if (g.done < g.total) {
        cgSwing(g, dt);
        g.cols[g.done].height = g.pos;
      }
    },
    render(g) {
      g.cols.forEach((c, i) => {
        c.line.style.bottom = cgPct(c.at);
        c.line.style.height = cgPct(g.width);
        c.pin.style.height = cgPct(i < g.done ? c.at + g.width / 2 : i === g.done ? c.height : 0);
        c.col.className = "cg-pin" + (i < g.done ? " set" : i === g.done ? " active" : "");
      });
    },
    press(g) {
      const c = g.cols[g.done];
      if (g.pos >= c.at && g.pos <= c.at + g.width) {
        g.done += 1;
        cgFlash(true);
        cgRenderFoot();
        if (g.done >= g.total) return cgFinish(true);
        g.speed *= g.spec.speedUp || 1.1;
      } else {
        c.height = 0;
        /* a slip drops the last pin that was set as well */
        if (g.spec.dropOnMiss && g.done > 0) {
          g.done -= 1;
          g.cols[g.done].height = 0;
        }
        cgStrike();
        cgRenderFoot();
      }
      g.pos = 0;
      g.dir = 1;
    },
  },

  /* ---- Hold the lid inside a drifting band ---- */
  hold: {
    init(g, stage) {
      g.total = 1;
      g.level = 0;
      g.filled = 0;
      g.goal = g.spec.goal || 3;
      g.band = g.spec.band || 0.24;
      g.phase = Math.random() * Math.PI * 2;
      g.centre = 0.5;
      g.holding = false;

      const wrap = cgEl("div", "cg-hold", stage);
      const track = cgEl("div", "cg-hold-track", wrap);
      g.bandEl = cgEl("div", "cg-hold-band", track);
      g.lidEl = cgEl("div", "cg-hold-lid", track);
      const side = cgEl("div", "cg-hold-side", wrap);
      g.readEl = cgEl("div", "cg-hold-read", side);
      const meter = cgEl("div", "cg-hold-meter", side);
      g.meterEl = cgEl("div", "cg-hold-meter-fill", meter);
    },
    update(g, dt) {
      const s = g.spec;
      g.level += (g.holding ? s.rise || 0.9 : -(s.fall || 0.7)) * dt;

      /* a gust under the lid, now and then */
      if (Math.random() < (s.gusts || 0) * dt) g.level += (Math.random() - 0.5) * 0.3;
      g.level = Math.max(0, Math.min(1, g.level));

      const swing = Math.sin((g.elapsed * Math.PI * 2) / (s.period || 4) + g.phase);
      const half = g.band / 2;
      g.centre = Math.max(half, Math.min(1 - half, 0.5 + (s.drift || 0.25) * swing));

      g.inside = Math.abs(g.level - g.centre) <= half;
      if (g.inside) g.filled += dt;
      else g.filled = Math.max(0, g.filled - dt * 0.5);

      if (g.filled >= g.goal) cgFinish(true);
    },
    render(g) {
      g.bandEl.style.bottom = cgPct(g.centre - g.band / 2);
      g.bandEl.style.height = cgPct(g.band);
      g.bandEl.classList.toggle("inside", !!g.inside);
      g.lidEl.style.bottom = cgPct(g.level);
      g.meterEl.style.width = cgPct(g.filled / g.goal);
      g.readEl.innerText = Math.round((g.filled / g.goal) * 100) + "%";
    },
    press() {
      /* held, not pressed: see the key handlers */
    },
  },

  /* ---- The keys shown, in order ---- */
  sequence: {
    init(g, stage) {
      const keys = (Array.isArray(g.spec.keys) && g.spec.keys.length ? g.spec.keys : ["W", "A", "S", "D"])
        .map((k) => String(k).toUpperCase());
      g.keySet = keys;
      g.total = 1;
      g.length = g.spec.length || 6;
      g.seq = [];
      for (let i = 0; i < g.length; i++) {
        let k;
        /* never three of a kind in a row - that is a stutter, not a pattern */
        do { k = keys[Math.floor(Math.random() * keys.length)]; }
        while (i >= 2 && k === g.seq[i - 1] && k === g.seq[i - 2]);
        g.seq.push(k);
      }
      g.index = 0;
      const row = cgEl("div", "cg-keys", stage);
      g.capEls = g.seq.map((k) => {
        const cap = cgEl("div", "cg-key", row);
        cap.innerText = g.spec.arrows ? CG_ARROW_GLYPHS[k] || k : k;
        return cap;
      });
    },
    update() {},
    render(g) {
      g.capEls.forEach((cap, i) => {
        cap.classList.toggle("done", i < g.index);
        cap.classList.toggle("current", i === g.index);
      });
    },
    press() {
      /* SPACE is not one of the keys */
    },
    key(g, code) {
      /* anything that is not one of this game's keys is ignored, not a miss */
      const pressed = CG_ARROW_KEYS[code] || (code.startsWith("Key") ? code.slice(3) : null);
      if (!pressed || !g.keySet.includes(pressed)) return;

      if (pressed === g.seq[g.index]) {
        g.index += 1;
        if (g.index >= g.length) return cgFinish(true);
      } else {
        cgPulse(g.capEls[g.index], "wrong");
        cgStrike();
      }
    },
  },

  /* ---- Hand over hand: grab each hold as the swing carries you over it ---- */
  reach: {
    init(g, stage) {
      g.total = g.spec.reaches || 2;
      g.width = g.spec.zone || 0.24;
      g.speed = g.spec.speed || 0.75;
      g.pos = 0.5;
      g.dir = Math.random() < 0.5 ? 1 : -1;
      g.side = Math.random() < 0.5 ? "A" : "D"; /* the hand that reaches next */

      const wrap = cgEl("div", "cg-reach", stage);
      const track = cgEl("div", "cg-reach-trunk", wrap);
      g.holdEls = { A: cgEl("div", "cg-reach-hold", track), D: cgEl("div", "cg-reach-hold", track) };
      g.handEl = cgEl("div", "cg-reach-hand", track);
      const keys = cgEl("div", "cg-reach-keys", wrap);
      g.keyEls = { A: cgEl("div", "cg-key", keys), D: cgEl("div", "cg-key", keys) };
      g.keyEls.A.innerText = "A";
      g.keyEls.D.innerText = "D";

      g.holds = {};
      this.place(g, "A");
      this.place(g, "D");
    },
    /* each hold stays on its own side of the trunk */
    place(g, side) {
      const room = Math.max(0, 0.4 - g.width);
      g.holds[side] = (side === "A" ? 0.04 : 0.56) + Math.random() * room;
    },
    update(g, dt) {
      cgSwing(g, dt);
    },
    render(g) {
      ["A", "D"].forEach((side) => {
        const hold = g.holdEls[side];
        hold.style.left = cgPct(g.holds[side]);
        hold.style.width = cgPct(g.width);
        hold.classList.toggle("next", g.side === side);
        g.keyEls[side].classList.toggle("current", g.side === side);
      });
      g.handEl.style.left = cgPct(g.pos);
    },
    press() {
      /* A and D, not SPACE: see key */
    },
    key(g, code) {
      const side = CG_ARROW_KEYS[code] || (code.startsWith("Key") ? code.slice(3) : null);
      if (side !== "A" && side !== "D") return;

      const at = g.holds[side];
      if (side === g.side && g.pos >= at && g.pos <= at + g.width) {
        g.done += 1;
        cgFlash(true);
        cgRenderFoot();
        if (g.done >= g.total) return cgFinish(true);

        this.place(g, side);
        g.side = side === "A" ? "D" : "A";
        g.speed *= g.spec.speedUp || 1.08;
      } else {
        /* wrong hand, or grabbing at bark */
        cgPulse(g.keyEls[side], "wrong");
        cgStrike();
      }
    },
  },

  /* Tend the wash */
  pot: {
    init(g, stage) {
      const s = g.spec;
      g.total = 1;
      g.mix = 0;
      g.froth = 0;
      g.at = 0;
      g.dir = 1;                /* +1 clockwise, -1 the other way */
      g.angle = 0;
      g.flipped = false;
      g.drop = null;            /* { pos, label, until } */
      g.nextDrop = (s.dropEvery || 3.5) * 0.6;
      g.callUntil = 0;
      g.ingredients = Array.isArray(s.ingredients) && s.ingredients.length ? s.ingredients : ["Jaggery", "Yeast"];
      g.lastLabel = -1;

      const labels = s.labels || {};
      const wrap = cgEl("div", "cg-pot", stage);
      const vessel = cgEl("div", "cg-pot-vessel", wrap);
      g.potEl = vessel;
      cgEl("div", "cg-pot-wash", vessel);
      g.swirlEl = cgEl("div", "cg-pot-swirl", vessel);
      g.frothEl = cgEl("div", "cg-pot-froth", vessel);
      g.paddleEl = cgEl("div", "cg-pot-paddle", vessel);
      cgEl("div", "cg-pot-hub", vessel);

      g.markEls = POT_KEYS.map((k, i) => {
        const mark = cgEl("div", "cg-key cg-pot-mark", vessel);
        mark.innerText = k;
        const a = (i * Math.PI) / 2;
        mark.style.left = 50 + 58 * Math.sin(a) + "%";
        mark.style.top = 50 - 58 * Math.cos(a) + "%";
        return mark;
      });

      g.chipEl = cgEl("div", "cg-pot-chip", vessel);
      g.callEl = cgEl("div", "cg-pot-call", wrap);
      g.callEl.innerText = s.call || "Now the other way!";

      const meters = cgEl("div", "cg-pot-meters", wrap);
      const row = (label, cls) => {
        const r = cgEl("div", "cg-pot-row " + cls, meters);
        cgEl("span", "cg-pot-label", r).innerText = label;
        const bar = cgEl("div", "cg-pot-meter", r);
        return cgEl("div", "cg-pot-meter-fill", bar);
      };
      g.mixEl = row(labels.mixed || "Mixed", "mixed");
      g.frothBarEl = row(labels.froth || "Froth", "froth");
    },
    update(g, dt) {
      const s = g.spec;
      g.froth = Math.max(0, g.froth - (s.frothFall || 0.32) * dt);

      /* an ingredient floats up, then sinks if nobody folds it in */
      if (g.drop && g.elapsed >= g.drop.until) {
        g.drop = null;
        g.nextDrop = g.elapsed + (s.dropEvery || 3.5);
      } else if (!g.drop && g.elapsed >= g.nextDrop) {
        let pos;
        do { pos = Math.floor(Math.random() * 4); } while (pos === g.at);
        let li;
        do { li = Math.floor(Math.random() * g.ingredients.length); }
        while (g.ingredients.length > 1 && li === g.lastLabel);
        g.lastLabel = li;
        g.drop = { pos, label: g.ingredients[li], until: g.elapsed + (s.dropLife || 2.6) };
        potPlaceChip(g);
      }
    },
    render(g) {
      const next = (g.at + g.dir + 4) % 4;
      g.markEls.forEach((m, i) => m.classList.toggle("current", i === next));

      g.paddleEl.style.transform = `translate(-50%, -100%) rotate(${g.angle}deg)`;
      g.swirlEl.style.transform = `rotate(${g.angle * 1.5}deg)`;
      g.frothEl.style.setProperty("--fw", (Math.min(1, g.froth) * 46).toFixed(1) + "%");

      g.mixEl.style.width = cgPct(g.mix);
      g.frothBarEl.style.width = cgPct(g.froth);
      g.frothBarEl.classList.toggle("high", g.froth >= 0.7);

      if (g.drop) {
        if (g.chipEl.dataset.key !== g.drop.pos + "|" + g.drop.label) potPlaceChip(g); /* a drop set from outside update */
        g.chipEl.classList.add("show");
        g.chipEl.classList.toggle("sinking", g.drop.until - g.elapsed < 0.8);
      } else {
        g.chipEl.classList.remove("show", "sinking");
      }

      g.callEl.classList.toggle("show", g.elapsed < g.callUntil);
    },
    press() {
      /* W A S D, not SPACE: see key */
    },
    key(g, code) {
      const letter = CG_ARROW_KEYS[code] || (code.startsWith("Key") ? code.slice(3) : null);
      const idx = POT_KEYS.indexOf(letter);
      if (idx < 0 || idx === g.at) return;

      const s = g.spec;
      const next = (g.at + g.dir + 4) % 4;
      if (idx !== next) {
        /* the wrong way round: wash over the side */
        cgPulse(g.markEls[idx], "wrong");
        return cgStrike();
      }

      /* the sweep */
      g.at = idx;
      g.angle += 90 * g.dir;
      g.mix += s.stirStep || 0.05;
      g.froth += s.frothPerStir || 0.16;

      /* swept onto what was floating there: folded in */
      if (g.drop && g.drop.pos === idx) {
        g.mix += s.dropBonus || 0.14;
        g.froth = Math.max(0, g.froth - 0.2);
        potPlaceChip(g); /* the fold plays where the tag was */
        g.drop = null;
        g.nextDrop = g.elapsed + (s.dropEvery || 3.5);
        cgPulse(g.chipEl, "folded");
        cgFlash(true);
      }

      /* worked it too hard: it boils over the rim */
      if (g.froth >= 1) {
        g.froth = 0.45;
        cgPulse(g.potEl, "boil");
        cgStrike();
        if (g.over) return;
      }

      /* (the small allowance: 20 sweeps of 0.05 add up to 0.9999999999999999) */
      if (g.mix >= 1 - POT_EPS) {
        g.mix = 1;
        return cgFinish(true);
      }

      /* halfway: the wash wants it the other way */
      if (s.reverse !== false && !g.flipped && g.mix >= 0.5 - POT_EPS) {
        g.flipped = true;
        g.dir = -g.dir;
        g.callUntil = g.elapsed + 1.8;
      }
    },
  },

  /* Tend the wash with a spoon */
  spoon: {
    init(g, stage) {
      const s = g.spec;
      const calls = s.calls || {};
      const labels = s.labels || {};

      g.mix = 0;
      g.froth = 0;
      g.dir = 1;             /* +1 = clockwise on screen */
      g.flipped = false;
      g.speed = 0;           /* turns a second, smoothed */
      g.turnAcc = 0;
      g.stirAngle = 0;
      g.washSpin = 0;
      g.lastAng = null;
      g.warn = null;         /* { text, until } */
      g.flipUntil = 0;
      g.calls = calls;
      g.streak = 0;          /* 0..1, steady stirring in the band */
      g.lumps = [];
      g.particles = [];
      g.bubbles = [];        /* { x, y, size, age, life } */
      g.wake = [];
      g.inks = [];
      g.spoonNorm = null;
      g.color = [138, 84, 33]; /* the wash: starts as plain amber */
      g.bubbleClock = 0;
      g.foam = [];
      for (let i = 0; i < 160; i++) {
        g.foam.push({ a: Math.random() * Math.PI * 2, depth: Math.random(), size: 0.018 + Math.random() * 0.03 });
      }
      g.foam.sort((x, y) => x.depth - y.depth);

      /* the tray: up to 4 of this batch's ingredients, shuffled; `steps` of them get called */
      const pool = (Array.isArray(s.tray) && s.tray.length ? s.tray : [{ label: "Yeast" }, { label: "Sugar" },
        { label: "Water" }, { label: "Fruit" }]).slice();
      for (let i = pool.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [pool[i], pool[j]] = [pool[j], pool[i]];
      }
      g.trayItems = pool.slice(0, Math.min(4, pool.length)).map((item, i) => ({
        ...item, rgb: spoonRgb(item.tint || SPOON_PALETTE[i % SPOON_PALETTE.length]),
      }));
      g.steps = Math.max(1, Math.min(s.steps || 3, g.trayItems.length));
      const order = g.trayItems.map((_, i) => i);
      for (let i = order.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [order[i], order[j]] = [order[j], order[i]];
      }
      g.needed = order.slice(0, g.steps);
      g.added = 0;
      g.waiting = true;
      g.callStart = 0;
      g.total = g.steps;
      g.done = 0;

      /* the pot: clay rim (CSS), the living wash (canvas), steam, the spoon */
      const wrap = cgEl("div", "cg-pot cg-spoon", stage);
      const vessel = cgEl("div", "cg-pot-vessel cg-spoon-vessel", wrap);
      g.potEl = vessel;
      for (let i = 0; i < 3; i++) cgEl("div", "cg-spoon-steam s" + i, vessel);
      g.canvas = cgEl("canvas", "cg-spoon-canvas", vessel);
      g.ctx = g.canvas.getContext("2d");
      g.spoonEl = cgEl("div", "cg-spoon-tool", vessel);
      cgEl("div", "cg-spoon-handle", g.spoonEl);
      cgEl("div", "cg-spoon-bowl", g.spoonEl);
      g.spoonPos = null;

      g.callEl = cgEl("div", "cg-pot-call", wrap);

      /* the tray of dishes */
      const tray = cgEl("div", "cg-tray", wrap);
      g.bowlEls = g.trayItems.map((item, i) => {
        const bowl = cgEl("div", "cg-tray-bowl", tray);
        const dish = cgEl("div", "cg-tray-dish", bowl);
        dish.style.setProperty("--tint", item.tint || SPOON_PALETTE[i % SPOON_PALETTE.length]);
        if (item.img) {
          const img = cgEl("img", "cg-tray-img", dish);
          img.src = item.img;
          img.alt = "";
          img.draggable = false;
          img.onerror = () => img.remove(); /* no picture: the name says it */
        }
        cgEl("div", "cg-tray-tick", dish).innerText = "✓";
        cgEl("div", "cg-tray-name", bowl).innerText = item.label;
        bowl.addEventListener("mousedown", (e) => this.grab(g, i, e));
        return bowl;
      });

      /* stir speed (with the Smooth streak), mixed and froth */
      const meters = cgEl("div", "cg-pot-meters", wrap);
      const row = (label, cls) => {
        const r = cgEl("div", "cg-pot-row " + cls, meters);
        cgEl("span", "cg-pot-label", r).innerText = label;
        const bar = cgEl("div", "cg-pot-meter", r);
        return { row: r, bar, fill: cgEl("div", "cg-pot-meter-fill", bar) };
      };
      const speed = row(labels.speed || "Stir", "speed");
      g.speedScale = (s.maxSpeed || 1.4) * 1.8;
      const band = cgEl("div", "cg-spoon-band", speed.bar);
      band.style.left = cgPct((s.minSpeed || 0.5) / g.speedScale);
      band.style.width = cgPct(((s.maxSpeed || 1.4) - (s.minSpeed || 0.5)) / g.speedScale);
      g.speedFill = speed.fill;
      g.streakEl = cgEl("div", "cg-spoon-streak", speed.row);
      g.mixEl = row(labels.mixed || "Mixed", "mixed").fill;
      g.frothBarEl = row(labels.froth || "Froth", "froth").fill;

      /* sound: made here, no files (Config: sound / volume) */
      g.audio = s.sound === false ? null : spoonAudio(s.volume == null ? 0.5 : s.volume);

      /* the mouse, on the whole page while this game runs */
      g.onMove = (e) => this.move(g, e);
      g.onUp = (e) => this.release(g, e);
      document.addEventListener("mousemove", g.onMove);
      document.addEventListener("mouseup", g.onUp);
      g.cleanup = () => {
        document.removeEventListener("mousemove", g.onMove);
        document.removeEventListener("mouseup", g.onUp);
        if (g.drag) g.drag.ghost.remove();
        g.drag = null;
        if (g.audio) g.audio.close();
        g.audio = null;
      };
    },

    /* where the cursor is, from the pot's centre, and the pot's radius (px) */
    local(g, e) {
      const r = g.potEl.getBoundingClientRect();
      return { x: e.clientX - (r.left + r.width / 2), y: e.clientY - (r.top + r.height / 2), R: r.width / 2 };
    },

    move(g, e) {
      if (skillGame !== g) return;

      if (g.drag) {
        g.drag.ghost.style.left = e.clientX + "px";
        g.drag.ghost.style.top = e.clientY + "px";
      }

      const p = this.local(g, e);
      const dist = Math.hypot(p.x, p.y);
      g.spoonPos = dist <= p.R * 1.35 ? p : null;

      /* only a spoon in the wash stirs it, and not while carrying an ingredien */
      const inWash = dist >= p.R * 0.18 && dist <= p.R * 0.95;
      const washR = p.R * SPOON_WASH;
      g.spoonNorm = inWash && !g.drag ? { x: p.x / washR, y: p.y / washR } : null;
      if (g.spoonNorm) {
        const k = Math.min(1, 0.92 / Math.max(0.0001, Math.hypot(g.spoonNorm.x, g.spoonNorm.y)));
        g.wake.push({ x: g.spoonNorm.x * k, y: g.spoonNorm.y * k, t: g.elapsed });
        if (g.wake.length > 40) g.wake.shift();
      }

      if (!g.live || g.over || g.drag || !inWash) {
        g.lastAng = null;
        return;
      }

      const ang = Math.atan2(p.y, p.x);
      if (g.lastAng !== null) {
        let d = ang - g.lastAng;
        if (d > Math.PI) d -= Math.PI * 2;
        if (d < -Math.PI) d += Math.PI * 2;
        g.turnAcc += d;
      }
      g.lastAng = ang;
    },

    grab(g, i, e) {
      if (skillGame !== g || !g.live || g.over || g.drag) return;
      const bowl = g.bowlEls[i];
      if (bowl.classList.contains("used")) return;
      e.preventDefault();
      if (g.audio) g.audio.wake();

      /* a copy of the dish follows the hand */
      const ghost = cgEl("div", "cg-tray-ghost", document.body);
      ghost.innerHTML = bowl.querySelector(".cg-tray-dish").innerHTML;
      if (!ghost.querySelector("img")) ghost.innerText = g.trayItems[i].label; /* no picture: carry the name */
      ghost.style.setProperty("--tint", g.trayItems[i].tint || SPOON_PALETTE[i % SPOON_PALETTE.length]);
      ghost.style.left = e.clientX + "px";
      ghost.style.top = e.clientY + "px";
      bowl.classList.add("lifted");
      g.drag = { i, ghost };
    },

    release(g, e) {
      if (skillGame !== g || !g.drag) return;
      const { i, ghost } = g.drag;
      g.drag = null;
      ghost.remove();
      g.bowlEls[i].classList.remove("lifted");
      if (!g.live || g.over) return;

      const p = this.local(g, e);
      if (Math.hypot(p.x, p.y) > p.R * 0.95) return; /* not over the pot: put it back */
      const washR = p.R * SPOON_WASH;
      this.drop(g, i, { x: p.x / washR, y: p.y / washR });
    },

    drop(g, i, at) {
      if (!g.waiting) return;
      const item = g.trayItems[i];
      const spot = at || { x: 0, y: -0.3 };

      if (i === g.needed[g.added]) {
        g.added += 1;
        g.done = g.added;
        g.waiting = false;
        g.bowlEls[i].classList.add("used");
        cgPulse(g.bowlEls[i], "ticked");
        cgFlash(true);
        cgRenderFoot();

        /* it goes in as lumps of its colour, and its colour starts to swirl in */
        const n = Math.max(0, Math.round(g.spec.lumps == null ? 4 : g.spec.lumps));
        for (let k = 0; k < n; k++) {
          const r0 = 0.38 + Math.random() * 0.34;
          g.lumps.push({
            a: Math.random() * Math.PI * 2, r0, r: r0,
            drift: Math.random() * Math.PI * 2, driftRate: 0.6 + Math.random() * 0.8, /* wanders in and out */
            born: g.elapsed, size: 0.085 + Math.random() * 0.04, rgb: item.rgb, wob: Math.random() * 6,
          });
        }
        g.inks.push({ rgb: item.rgb, amt: 1, a: Math.atan2(spot.y, spot.x) - g.stirAngle });
        spoonSplash(g, spot.x, spot.y, item.rgb, 18, 0.9);
        if (g.audio) g.audio.plop();
      } else {
        g.warn = { text: g.calls.spoiled || "Not that one!", until: g.elapsed + 1.4 };
        g.streak = 0;
        cgPulse(g.bowlEls[i], "wrong");
        if (g.audio) g.audio.tick();
        cgStrike();
      }
    },

    update(g, dt) {
      const s = g.spec;
      const turned = g.turnAcc;
      g.turnAcc = 0;

      /* how fast the spoon goes round, smoothed so a jerk does not count as a  */
      const inst = Math.abs(turned) / (Math.PI * 2) / Math.max(dt, 0.001);
      g.speed += (inst - g.speed) * Math.min(1, dt * 6);

      /* the wash follows the spoon round, and slows when it stops */
      g.washSpin += ((turned / Math.max(dt, 0.001)) * 0.7 - g.washSpin) * Math.min(1, dt * 3);
      g.stirAngle += g.washSpin * dt;

      const maxSpeed = s.maxSpeed || 1.4;
      const minSpeed = s.minSpeed || 0.5;
      const inBand = g.speed >= minSpeed && g.speed <= maxSpeed;

      /* froth: whipped up by a racing spoon, settling otherwise */
      if (g.speed > maxSpeed) {
        g.froth += (g.speed - maxSpeed) * (s.frothRate || 0.35) * dt;
        g.warn = { text: g.calls.fast || "Too fast!", until: g.elapsed + 0.5 };
        g.streak = 0;
      } else {
        g.froth = Math.max(0, g.froth - (s.frothFall || 0.3) * dt);
      }

      if (g.froth >= 1) {
        g.froth = 0.45;
        g.streak = 0;
        for (let k = 0; k < 26; k++) {
          const a = Math.random() * Math.PI * 2;
          spoonParticle(g, Math.cos(a) * 0.95, Math.sin(a) * 0.95, Math.cos(a) * 0.9, Math.sin(a) * 0.9,
            [250, 244, 228], 0.03 + Math.random() * 0.03, 0.7);
        }
        cgPulse(g.potEl, "boil");
        if (g.audio) g.audio.fizz();
        cgStrike();
        if (g.over) return;
      }

      /* the Smooth streak: steady stirring in the band mixes faster */
      const turns = (turned * g.dir) / (Math.PI * 2);
      if (inBand && turns > 0) g.streak = Math.min(1, g.streak + (s.streakBuild || 0.25) * dt);
      else if (g.speed < minSpeed) g.streak = Math.max(0, g.streak - dt * 0.6);
      const mult = 1 + ((s.streakMax || 1.6) - 1) * g.streak;

      /* lumps: drift with the wash (faster, dodging, when it is stirred too hard) */
      const dodge = g.speed > maxSpeed ? 1.8 : 1;
      for (const l of g.lumps) {
        l.a += g.washSpin * dt * dodge * (0.6 + 0.5 * l.r);
        l.drift += dt * l.driftRate;
        l.r = l.r0 + Math.sin(l.drift) * 0.1;
        l.wob += dt * 3;
      }

      /* a lump nobody breaks softens and goes by itself in the end (no bonus): never stuck */
      const soften = s.lumpSoften == null ? 8 : s.lumpSoften;
      for (let k = g.lumps.length - 1; k >= 0; k--) {
        const l = g.lumps[k];
        if (soften > 0 && g.elapsed - l.born > soften) {
          g.lumps.splice(k, 1);
          spoonSplash(g, Math.cos(l.a) * l.r, Math.sin(l.a) * l.r, l.rgb, 4, 0.3);
        }
      }

      /* ...and break under the spoon */
      if (g.spoonNorm && g.live && !g.over) {
        for (let k = g.lumps.length - 1; k >= 0; k--) {
          const l = g.lumps[k];
          const lx = Math.cos(l.a) * l.r, ly = Math.sin(l.a) * l.r;
          if (Math.hypot(g.spoonNorm.x - lx, g.spoonNorm.y - ly) < l.size + 0.12) {
            g.lumps.splice(k, 1);
            spoonSplash(g, lx, ly, l.rgb, 10, 0.6);
            g.mix += s.lumpBonus == null ? 0.02 : s.lumpBonus;
            if (g.audio) g.audio.crunch();
          }
        }
      }

      /* the mixing, in the right direction, up to what has been added and brok */
      const cap = g.added / g.steps;
      const held = cap - (s.lumpShare == null ? 0.04 : s.lumpShare) * g.lumps.length;
      if (turns > 0) {
        const rate = g.speed < minSpeed ? 0.5 : 1;
        g.mix = Math.min(Math.max(g.mix, held), g.mix + turns * (s.perTurn || 0.08) * rate * mult);
        for (const ink of g.inks) ink.amt = Math.max(0, ink.amt - turns * 0.9);
      } else if (turns < 0 && g.speed > 0.3) {
        /* going round the wrong way at a real stir (not a twitch): it does not mix */
        g.warn = { text: g.calls.wrongWay || "Other way round!", until: g.elapsed + 0.8 };
      }
      g.mix = Math.min(g.mix, cap);
      g.inks = g.inks.filter((ink) => ink.amt > 0.01);

      /* the wash takes on the colour of what has gone in, as it is mixed */
      const target = spoonTarget(g);
      const blend = Math.min(1, dt * (0.4 + g.speed * 0.8));
      for (let c = 0; c < 3; c++) g.color[c] += (target[c] - g.color[c]) * blend;

      /* it comes alive: bubbles, more as the mix comes together and when stirred hard */
      g.bubbleClock += dt * (2 + g.mix * 9 + Math.min(3, g.speed) * 2);
      while (g.bubbleClock > 1) {
        g.bubbleClock -= 1;
        const a = Math.random() * Math.PI * 2, r = Math.sqrt(Math.random()) * 0.82;
        g.bubbles.push({ x: Math.cos(a) * r, y: Math.sin(a) * r, size: 0.012 + Math.random() * 0.022,
          age: 0, life: 0.6 + Math.random() * 0.9 });
      }
      for (const b of g.bubbles) b.age += dt;
      g.bubbles = g.bubbles.filter((b) => b.age < b.life);

      for (const p of g.particles) {
        p.age += dt;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
        p.vx *= 1 - dt * 2.5;
        p.vy *= 1 - dt * 2.5;
      }
      g.particles = g.particles.filter((p) => p.age < p.life);
      g.wake = g.wake.filter((w) => g.elapsed - w.t < 0.6);

      if (g.audio) g.audio.swish(Math.min(1, g.speed / (maxSpeed * 1.4)));

      /* this stage is mixed and broken up: call for the next ingredient */
      if (!g.waiting && g.added < g.steps && g.lumps.length === 0 && g.mix >= cap - POT_EPS) {
        g.waiting = true;
        g.callStart = g.elapsed;
      }

      /* a call left too long: a miss, and it is called again */
      if (g.waiting && g.elapsed - g.callStart > (s.callTime || 6)) {
        g.callStart = g.elapsed;
        g.streak = 0;
        cgStrike();
        if (g.over) return;
      }

      /* halfway: the other way round */
      if (s.reverse !== false && !g.flipped && g.mix >= 0.5 - POT_EPS) {
        g.flipped = true;
        g.dir = -g.dir;
        g.flipUntil = g.elapsed + 1.8;
      }

      if (g.added >= g.steps && g.lumps.length === 0 && g.mix >= 1 - POT_EPS) {
        g.mix = 1;
        for (let k = 0; k < 40; k++) {
          const a = (k / 40) * Math.PI * 2;
          spoonParticle(g, Math.cos(a) * 0.3, Math.sin(a) * 0.3, Math.cos(a + 1) * 1.2, Math.sin(a + 1) * 1.2,
            [236, 201, 131], 0.03, 0.9);
        }
        if (g.audio) g.audio.chime();
        cgFinish(true);
      }
    },

    render(g) {
      /* the spoon: its bowl under the cursor, the handle pointing out over the rim */
      const R = g.potEl.offsetWidth / 2 || 1;
      let x, y;
      if (g.spoonPos) {
        const d = Math.hypot(g.spoonPos.x, g.spoonPos.y);
        const k = d > R * 0.82 ? (R * 0.82) / d : 1; /* the bowl stays inside the rim */
        x = g.spoonPos.x * k;
        y = g.spoonPos.y * k;
      } else {
        x = R * 0.45; /* resting against the side */
        y = -R * 0.3;
      }
      const deg = (Math.atan2(y, x) * 180) / Math.PI;
      g.spoonEl.style.transform = `translate(${R + x}px, ${R + y}px) rotate(${deg}deg)`;

      spoonDraw(g);

      g.mixEl.style.width = cgPct(g.mix);
      g.frothBarEl.style.width = cgPct(g.froth);
      g.frothBarEl.classList.toggle("high", g.froth >= 0.7);
      g.potEl.classList.toggle("heaving", g.froth >= 0.7);
      g.speedFill.style.width = cgPct(Math.min(1, g.speed / g.speedScale));
      const sp = g.spec;
      g.speedFill.classList.toggle("fast", g.speed > (sp.maxSpeed || 1.4));
      g.speedFill.classList.toggle("good", g.speed >= (sp.minSpeed || 0.5) && g.speed <= (sp.maxSpeed || 1.4));

      /* the Smooth streak tag */
      const mult = 1 + ((sp.streakMax || 1.6) - 1) * g.streak;
      const streakText = g.streak > 0.05 ? (g.calls.smooth || "Smooth") + " ×" + mult.toFixed(1) : "";
      if (g.streakEl.innerText !== streakText) g.streakEl.innerText = streakText;
      g.streakEl.style.opacity = Math.min(1, g.streak * 1.5).toFixed(2);

      /* the called dish breathes once the player has had a while to find it */
      const hintAt = (sp.callTime || 6) * (sp.hintAfter == null ? 0.5 : sp.hintAfter);
      const hintSlot = g.waiting && sp.hintAfter !== false && g.elapsed - g.callStart > hintAt ? g.needed[g.added] : -1;
      g.bowlEls.forEach((b, i) => b.classList.toggle("hint", i === hintSlot));

      /* the line under the pot: a warning, the flip, the lumps, or what the wash wants */
      let text = "";
      let cls = "";
      if (g.warn && g.elapsed < g.warn.until) {
        text = g.warn.text;
        cls = "warn";
      } else if (g.elapsed < g.flipUntil) {
        text = g.calls.flip || "Now the other way!";
      } else if (g.waiting && g.added < g.steps) {
        const item = g.trayItems[g.needed[g.added]];
        text = (g.calls.add || "Add the %s").replace("%s", item ? item.label : "?");
        cls = "ask";
      } else if (g.lumps.length > 0 && g.mix >= g.added / g.steps - (sp.lumpShare == null ? 0.04 : sp.lumpShare) * g.lumps.length - 0.005) {
        text = g.calls.lumps || "Break up the lumps!";
        cls = "ask";
      }
      if (g.callEl.innerText !== text) g.callEl.innerText = text;
      g.callEl.className = "cg-pot-call" + (text ? " show " + cls : "");
    },

    press() {
      /* the mouse plays this one */
    },
  },

  /* ---- Tasting: nose the glass (hold SPACE, let go in the gold), then catch three flavours ---- */
  taste: {
    holds: true,

    init(g, stage) {
      const s = g.spec;
      const L = s.labels || {};
      g.total = 1;
      g.labels = L;
      g.winText = L.clear;
      g.loseText = L.muddled;
      if (L.noseHint) document.getElementById("cg-hint").innerText = L.noseHint;
      g.phase = "nose";
      g.level = 0;
      g.breathing = false;
      g.band = s.noseBand || 0.18;
      g.bandAt = 0.5 + Math.random() * Math.max(0, 0.38 - g.band); /* the gold sits in the top half */
      g.noseScore = 0;
      g.noseWait = 0;

      const keys = (Array.isArray(s.palateKeys) && s.palateKeys.length ? s.palateKeys : ["W", "A", "S", "D"])
        .map((k) => String(k).toUpperCase());
      g.keys = keys;
      g.window = s.palateWindow || 0.9;
      g.slot = g.window + 0.7;
      g.palateDur = 3 * g.slot;
      g.palateT = 0;

      const wrap = cgEl("div", "cg-taste phase-nose", stage);
      g.wrapEl = wrap;
      wrap.style.setProperty("--tint", s.tint || "#d9d0b4");

      /* the glass, its spirit and the aroma rising off it */
      const glass = cgEl("div", "cg-taste-glass", wrap);
      for (let i = 0; i < 3; i++) cgEl("i", "cg-taste-wisp w" + i, glass);
      const bowl = cgEl("div", "cg-taste-bowl", glass);
      cgEl("div", "cg-taste-liquid", bowl);
      cgEl("div", "cg-taste-shine", bowl);

      const side = cgEl("div", "cg-taste-side", wrap);

      /* the nose: a breath meter with the gold sweet spot */
      const nose = cgEl("div", "cg-taste-nose", side);
      cgEl("div", "cg-taste-label", nose).innerText = L.nose || "Nose";
      const meter = cgEl("div", "cg-taste-breath", nose);
      g.bandEl = cgEl("div", "cg-taste-band", meter);
      g.fillEl = cgEl("div", "cg-taste-fill", meter);
      g.keyEl = cgEl("div", "cg-key cg-taste-space", nose);
      g.keyEl.innerText = "SPACE";

      /* the palate: three flavours along the tongue, each lit for a moment */
      const pal = cgEl("div", "cg-taste-palate", side);
      cgEl("div", "cg-taste-label", pal).innerText = L.palate || "Palate";
      const tongue = cgEl("div", "cg-taste-tongue", pal);
      g.dropEl = cgEl("div", "cg-taste-drop", tongue);
      const names = Array.isArray(L.zones) ? L.zones : [];
      g.zones = [];
      for (let i = 0; i < 3; i++) {
        let key;
        do { key = keys[Math.floor(Math.random() * keys.length)]; }
        while (keys.length > 1 && i > 0 && key === g.zones[i - 1].key);
        const el = cgEl("div", "cg-taste-zone", tongue);
        const cap = cgEl("div", "cg-key", el);
        cap.innerText = key;
        cgEl("span", "cg-taste-zname", el).innerText = names[i] || "";
        g.zones.push({ key, el, cap, hit: null, score: 0, centre: g.slot * (i + 0.5) });
      }
    },

    toPalate(g) {
      g.phase = "palate";
      g.palateT = -0.5;
      g.wrapEl.classList.remove("phase-nose");
      g.wrapEl.classList.add("phase-palate");
      if (g.labels.palateHint) document.getElementById("cg-hint").innerText = g.labels.palateHint;
    },

    /* the reading: nose and palate together, 0 - 1 */
    finish(g) {
      if (g.over) return;
      const palate = g.zones.reduce((sum, z) => sum + z.score, 0) / g.zones.length;
      const w = typeof g.spec.nose === "number" ? g.spec.nose : 0.4;
      g.score = Math.max(0, Math.min(1, g.noseScore * w + palate * (1 - w)));
      cgFinish(g.score >= (typeof g.spec.muddled === "number" ? g.spec.muddled : 0.35));
    },

    update(g, dt) {
      if (g.phase === "nose") {
        if (g.holding) {
          g.breathing = true;
          /* a breath is never quite even */
          g.level += (g.spec.noseRise || 0.45) * dt * (1 + 0.3 * Math.sin(g.elapsed * 6.5));
          if (g.level >= 1) {
            g.level = 1;
            g.noseScore = 0;
            cgFlash(false);
            if (g.labels.cough) cgBanner(g.labels.cough, "lose");
            setTimeout(() => { if (skillGame === g && !g.over) cgBanner(""); }, 900);
            return this.toPalate(g);
          }
        } else if (g.breathing) {
          /* let go: the nearer the middle of the gold, the better the nose */
          const half = g.band / 2;
          const off = Math.abs(g.level - (g.bandAt + half));
          g.noseScore = off <= half ? 0.6 + 0.4 * (1 - off / half) : Math.max(0, 0.6 - (off - half) * 4);
          cgFlash(off <= half);
          return this.toPalate(g);
        } else if ((g.noseWait += dt) > 5) {
          g.noseScore = 0; /* never breathed in: no nose at all */
          return this.toPalate(g);
        }
      } else {
        g.palateT += dt;
        for (const z of g.zones) {
          if (z.hit === null && g.palateT > z.centre + g.window / 2) {
            z.hit = false; /* the flavour went by */
            cgPulse(z.cap, "wrong");
          }
        }
        if (g.palateT >= g.palateDur) return this.finish(g);
      }
      if (g.elapsed >= g.time - 0.1) this.finish(g);
    },

    render(g) {
      g.fillEl.style.height = cgPct(g.level);
      g.bandEl.style.bottom = cgPct(g.bandAt);
      g.bandEl.style.height = cgPct(g.band);
      g.bandEl.classList.toggle("inside", g.holding && g.level >= g.bandAt && g.level <= g.bandAt + g.band);
      g.keyEl.classList.toggle("done", !!g.holding && g.phase === "nose");
      /* the aroma thickens as the breath goes in */
      g.wrapEl.style.setProperty("--aroma", (0.2 + 0.8 * (g.phase === "nose" ? g.level : 0.15)).toFixed(2));

      g.dropEl.style.left = cgPct(Math.max(0, g.palateT) / g.palateDur);
      for (const z of g.zones) {
        const open = g.phase === "palate" && z.hit === null && Math.abs(g.palateT - z.centre) <= g.window / 2;
        z.el.classList.toggle("open", open);
        z.el.classList.toggle("hit", z.hit === true);
        z.el.classList.toggle("miss", z.hit === false);
        z.cap.classList.toggle("current", open);
        z.cap.classList.toggle("done", z.hit === true);
      }
    },

    press() {
      /* held, not pressed: see the key handlers */
    },

    key(g, code) {
      if (g.phase !== "palate") return;
      const pressed = CG_ARROW_KEYS[code] || (code.startsWith("Key") ? code.slice(3) : null);
      if (!pressed || !g.keys.includes(pressed)) return;

      const i = Math.floor(g.palateT / g.slot);
      const z = g.zones[i];
      if (!z || z.hit !== null) return;

      /* one try per flavour: the right letter while it is lit, the nearer its peak the better */
      const off = Math.abs(g.palateT - z.centre);
      if (pressed === z.key && off <= g.window / 2) {
        z.hit = true;
        z.score = 1 - 0.5 * (off / (g.window / 2));
        cgFlash(true);
      } else {
        z.hit = false;
        cgPulse(z.cap, "wrong");
        cgFlash(false);
      }
    },
  },

  /* ---- Bottling: pour each bottle from the jug to the chalk mark, then cork it ---- */
  bottle: {
    holds: true,

    init(g, stage) {
      const s = g.spec;
      const L = s.labels || {};
      g.labels = L;
      g.total = 1;
      g.rounds = Math.max(1, Math.floor(s.rounds || 4));
      g.outcomes = [];
      g.index = -1;
      g.winText = L.clear;
      g.prevHold = false;

      const wrap = cgEl("div", "cg-btl", stage);
      g.wrapEl = wrap;
      wrap.style.setProperty("--tint", s.tint || "#d9d0b4");

      /* the shelf: corked bottles stand on the left, the empties wait on the right */
      g.doneEl = cgEl("div", "cg-btl-row done", wrap);
      const bench = cgEl("div", "cg-btl-bench", wrap);
      g.waitEl = cgEl("div", "cg-btl-row wait", wrap);
      cgEl("div", "cg-btl-plank", wrap);

      /* the jug, tipping from its foot toward the bottle */
      g.jugEl = cgEl("div", "cg-btl-jug", bench);
      g.jugEl.innerHTML = BOTTLE_JUG_SVG;
      g.streamEl = cgEl("div", "cg-btl-stream", bench);

      /* the bottle under it: glass, spirit, froth, the chalk mark, the cork */
      g.bottleEl = cgEl("div", "cg-btl-bottle", bench);
      g.bottleEl.innerHTML = BOTTLE_SVG;
      const svg = g.bottleEl.querySelector("svg");
      g.liquidEl = svg.querySelector(".liq");
      g.frothEl = svg.querySelector(".froth");
      g.markEl = svg.querySelector(".mark");
      g.corkEl = cgEl("div", "cg-btl-cork", g.bottleEl);
      g.splashEl = cgEl("div", "cg-btl-splash", g.bottleEl);
      g.callEl = cgEl("div", "cg-btl-call", bench);

      /* the mallet's swing, bar-style, for the cork */
      const swing = cgEl("div", "cg-bar cg-btl-swing", wrap);
      g.swingEl = swing;
      g.zoneEl = cgEl("div", "cg-bar-zone", swing);
      g.markBarEl = cgEl("div", "cg-bar-mark", swing);

      for (let i = 0; i < g.rounds; i++) {
        const b = cgEl("i", "cg-btl-mini", g.waitEl);
        b.innerHTML = BOTTLE_MINI_SVG;
      }

      g.audio = s.sound === false ? null : bottleAudio(s.volume == null ? 0.5 : s.volume);
      g.cleanup = () => { if (g.audio) g.audio.close(); };

      this.next(g);
    },

    /* the next empty slides in under the jug */
    next(g) {
      const s = g.spec;
      g.index += 1;
      if (g.index >= g.rounds) return this.finish(g);

      const wait = g.waitEl.firstElementChild;
      if (wait) wait.remove();

      g.phase = "slide";
      g.phaseT = 0;
      g.flow = 0;
      g.level = 0;
      g.froth = 0;
      g.bottleT = 0;
      g.perfect = false;
      g.band = s.band || 0.09;
      g.markAt = 0.75 + Math.random() * 0.08;
      g.tries = Math.max(1, s.corkTries || 2);
      g.bottleEl.className = "cg-btl-bottle slide-in";
      g.corkEl.className = "cg-btl-cork";
      g.swingEl.classList.remove("live");
      this.call(g, "");
    },

    call(g, text, cls) {
      if (g.callEl.innerText !== text) g.callEl.innerText = text;
      g.callEl.className = "cg-btl-call" + (text ? " show " + (cls || "") : "");
    },

    /* one bottle settled: "clean" or "spill" */
    settle(g, outcome, text, cls) {
      g.outcomes.push(outcome);
      g.phase = "done";
      g.phaseT = 0;
      g.flow = 0;
      g.swingEl.classList.remove("live");
      this.call(g, text, cls);
      cgFlash(outcome === "clean");

      const mini = cgEl("i", "cg-btl-mini " + outcome, g.doneEl);
      mini.innerHTML = BOTTLE_MINI_SVG;
      mini.style.setProperty("--fill", outcome === "clean" ? Math.min(1, g.level).toFixed(2) : "0.15");
      if (outcome === "spill") {
        g.bottleEl.classList.add("spilled");
        if (g.audio) g.audio.splash();
      }
    },

    /* the run is over: report every bottle, the share poured clean as the score */
    finish(g) {
      if (g.over) return;
      while (g.outcomes.length < g.rounds) g.outcomes.push("spill"); /* the clock ran out on the rest */
      const spills = g.outcomes.filter((o) => o === "spill").length;
      g.score = (g.rounds - spills) / g.rounds;
      g.loseText = (g.labels.spilled || "%d Spilled").replace("%d", spills);
      g.phase = "over";
      cgFinish(spills === 0);
    },

    update(g, dt) {
      const s = g.spec;
      const pressed = g.holding && !g.prevHold;
      g.prevHold = g.holding;
      g.phaseT += dt;

      if (g.phase === "slide") {
        if (g.phaseT >= 0.35) {
          g.phase = "pour";
          g.phaseT = 0;
          g.bottleEl.classList.remove("slide-in");
          this.call(g, g.labels.fill || "", "ask");
        }
      } else if (g.phase === "pour") {
        g.bottleT += dt;

        /* the jug tips while SPACE is held and rights itself after: the pour tapers off */
        if (pressed && g.level > 0.02) g.froth += s.glug == null ? 0.02 : s.glug; /* a top-up glugs */
        g.flow = Math.max(0, Math.min(1, g.flow + (g.holding ? s.flowRise || 2.2 : -(s.flowFall || 3.0)) * dt));

        /* the neck is narrow: there the spirit climbs more than twice as fast */
        const neck = g.level >= BOTTLE_NECK ? BOTTLE_NECK_SPEED : 1;
        g.level += (s.fillRate || 0.42) * g.flow * neck * dt;
        /* a fast pour foams, worst in the neck; the head settles all the while */
        g.froth += (s.frothRate || 0.12) * g.flow * g.flow * neck * dt;
        g.froth = Math.max(0, g.froth - g.froth * (s.frothFall || 0.9) * dt);

        if (g.level + g.froth >= 1) {
          g.level = Math.min(g.level, 1);
          return this.settle(g, "spill", g.labels.spill || "Spilled!", "bad");
        }
        /* the pour has stopped: judge where it settled */
        if (g.flow === 0 && !g.holding && g.level >= g.markAt) {
          if (g.level <= g.markAt + g.band) {
            g.perfect = Math.abs(g.level - (g.markAt + g.band / 2)) <= g.band * 0.22;
            this.toCork(g);
          } else {
            return this.settle(g, "spill", g.labels.spill || "Spilled!", "bad"); /* over the mark: poured off */
          }
        } else if (g.bottleT >= (s.bottleTime || 7)) {
          return this.settle(g, "spill", g.labels.short || "Too slow", "bad");
        }
      } else if (g.phase === "cork") {
        cgSwing(g, dt);
        if (pressed) this.strike(g);
        else if (g.phaseT >= (s.corkTime || 3)) this.settle(g, "spill", g.labels.knocked || "Knocked it over!", "bad");
      } else if (g.phase === "done") {
        if (g.phaseT >= 0.75) this.next(g);
      }

      if (g.audio) g.audio.pour(g.phase === "pour" ? g.flow : 0, g.level);
      if (!g.over && g.elapsed >= g.time - 0.1) this.finish(g);
    },

    toCork(g) {
      const s = g.spec;
      g.phase = "cork";
      g.phaseT = 0;
      g.prevHold = g.holding;
      g.pos = 0;
      g.dir = 1;
      g.speed = s.corkSpeed || 1.3;
      g.width = s.corkZone || 0.22;
      g.zone = 0.2 + Math.random() * (0.6 - g.width);
      g.swingEl.classList.add("live");
      g.corkEl.className = "cg-btl-cork ready";
      this.call(g, g.perfect ? g.labels.perfect || "" : g.labels.cork || "", g.perfect ? "good" : "ask");
    },

    strike(g) {
      if (g.pos >= g.zone && g.pos <= g.zone + g.width) {
        g.corkEl.className = "cg-btl-cork seated";
        if (g.audio) g.audio.cork();
        return this.settle(g, "clean", g.perfect ? g.labels.perfect || "" : g.labels.clean || "", "good");
      }
      g.tries -= 1;
      if (g.tries <= 0) {
        g.corkEl.className = "cg-btl-cork knocked";
        return this.settle(g, "spill", g.labels.knocked || "Knocked it over!", "bad");
      }
      g.corkEl.className = "cg-btl-cork ready crooked";
      cgPulse(g.swingEl, "wrong");
      cgFlash(false);
      this.call(g, g.labels.crooked || "", "bad");
      g.zone = 0.2 + Math.random() * (0.6 - g.width); /* the mallet comes round again */
    },

    render(g) {
      const tilt = g.phase === "pour" ? g.flow : 0;
      g.jugEl.style.transform = `rotate(${(8 + 42 * tilt).toFixed(1)}deg)`;
      g.streamEl.style.opacity = tilt > 0.03 ? Math.min(1, tilt * 1.6).toFixed(2) : "0";
      g.streamEl.style.width = (2 + 5 * tilt).toFixed(1) + "px";

      /* the spirit and its froth in the glass: level 0 is the base, 1 the brim */
      const y = (v) => BOTTLE_BASE - (BOTTLE_BASE - BOTTLE_BRIM) * Math.max(0, Math.min(1, v));
      const top = y(g.level);
      g.liquidEl.setAttribute("y", top.toFixed(2));
      g.liquidEl.setAttribute("height", (BOTTLE_BASE - top).toFixed(2));
      const froth = y(g.level + g.froth);
      g.frothEl.setAttribute("y", froth.toFixed(2));
      g.frothEl.setAttribute("height", Math.max(0, top - froth).toFixed(2));
      g.markEl.setAttribute("y", y(g.markAt + g.band).toFixed(2));
      g.markEl.setAttribute("height", (y(g.markAt) - y(g.markAt + g.band)).toFixed(2));
      g.markEl.classList.toggle("inside", g.level >= g.markAt && g.level <= g.markAt + g.band);

      if (g.phase === "cork") {
        g.zoneEl.style.left = cgPct(g.zone);
        g.zoneEl.style.width = cgPct(g.width);
        g.markBarEl.style.left = cgPct(g.pos);
      }
    },

    press() {
      /* held, not pressed: see update */
    },
  },
};

/* ---- the bottling game's helpers ---- */
/* The bottle, drawn in a 40 x 100 box */
const BOTTLE_BASE = 96;
const BOTTLE_BRIM = 5;
const BOTTLE_NECK = 0.72;
const BOTTLE_NECK_SPEED = 2.2;
const BOTTLE_PATH = "M15.5 5 H24.5 V30 C24.5 37 35 39.5 35 49 V91 Q35 96 30 96 H10 Q5 96 5 91 V49 C5 39.5 15.5 37 15.5 30 Z";

const BOTTLE_SVG =
  `<svg class="cg-btl-svg" viewBox="0 0 40 100" aria-hidden="true">` +
  `<defs><clipPath id="cg-btl-clip"><path d="${BOTTLE_PATH}"/></clipPath></defs>` +
  `<path class="glass" d="${BOTTLE_PATH}"/>` +
  `<g clip-path="url(#cg-btl-clip)">` +
  `<rect class="liq" x="0" y="96" width="40" height="0"/>` +
  `<rect class="froth" x="0" y="96" width="40" height="0"/>` +
  `</g>` +
  `<rect class="mark" x="11.5" y="20" width="17" height="6"/>` +
  `<path class="edge" d="${BOTTLE_PATH}"/>` +
  `<rect class="shine" x="8.5" y="50" width="2.6" height="38" rx="1.3"/>` +
  `<rect class="shine" x="17" y="9" width="1.6" height="18" rx="0.8"/>` +
  `</svg>`;

/* a small one for the shelf: --fill sets how full it stands */
const BOTTLE_MINI_SVG =
  `<svg viewBox="0 0 40 100" aria-hidden="true">` +
  `<path class="glass" d="${BOTTLE_PATH}"/>` +
  `<rect class="liq" x="5.5" y="30" width="29" height="66" rx="4"/>` +
  `<rect class="cork" x="15" y="0" width="10" height="9" rx="1.5"/>` +
  `<path class="edge" d="${BOTTLE_PATH}"/>` +
  `</svg>`;

/* a stoneware jug, cream glaze over brown, its lip to the right */
const BOTTLE_JUG_SVG =
  `<svg viewBox="0 0 60 70" aria-hidden="true">` +
  `<path class="jug-handle" d="M13 18 C1 18 1 44 12 46"/>` +
  `<path class="jug-body" d="M18 8 H43 L51 4 L48 12 C54 22 56 34 54 48 C52 60 46 66 31 66 C16 66 10 60 8 48 C6 34 10 22 18 12 Z"/>` +
  `<path class="jug-glaze" d="M18 8 H43 L51 4 L48 12 C50 16 51 19 52 23 H10 C12 18 14 15 18 12 Z"/>` +
  `<ellipse class="jug-mouth" cx="31" cy="8.5" rx="12.5" ry="2.4"/>` +
  `<path class="jug-band" d="M9 40 C20 43 42 43 55 40"/>` +
  `</svg>`;

/* The bottling game's sound, made in the page */
function bottleAudio(volume) {
  let ac = null;
  try {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ac = new AC();
  } catch (e) {
    return null;
  }
  const master = ac.createGain();
  master.gain.value = Math.max(0, Math.min(1, volume));
  master.connect(ac.destination);

  const noise = ac.createBuffer(1, ac.sampleRate * 2, ac.sampleRate);
  const data = noise.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;

  /* the pour: always running, silent until the jug tips */
  const src = ac.createBufferSource();
  src.buffer = noise;
  src.loop = true;
  const band = ac.createBiquadFilter();
  band.type = "bandpass";
  band.Q.value = 5;
  band.frequency.value = 420;
  const pourGain = ac.createGain();
  pourGain.gain.value = 0;
  src.connect(band).connect(pourGain).connect(master);
  src.start();

  const burst = (type, freq, peak, decay) => {
    const b = ac.createBufferSource(), f = ac.createBiquadFilter(), gn = ac.createGain();
    const t = ac.currentTime;
    b.buffer = noise;
    f.type = type;
    f.frequency.value = freq;
    gn.gain.setValueAtTime(0.0001, t);
    gn.gain.exponentialRampToValueAtTime(peak, t + 0.008);
    gn.gain.exponentialRampToValueAtTime(0.0001, t + decay);
    b.connect(f).connect(gn).connect(master);
    b.start(t);
    b.stop(t + decay + 0.05);
  };

  return {
    pour(flow, level) {
      const t = ac.currentTime;
      const glug = 0.7 + 0.3 * Math.sin(t * 34) * Math.sin(t * 9.5); /* it comes in glugs, not a hiss */
      pourGain.gain.setTargetAtTime(0.3 * flow * glug, t, 0.03);
      band.frequency.setTargetAtTime(380 + 1500 * Math.max(0, Math.min(1, level)), t, 0.06);
    },
    cork() {
      const t = ac.currentTime;
      const o = ac.createOscillator(), gn = ac.createGain();
      o.type = "triangle";
      o.frequency.setValueAtTime(260, t);
      o.frequency.exponentialRampToValueAtTime(110, t + 0.12);
      gn.gain.setValueAtTime(0.0001, t);
      gn.gain.exponentialRampToValueAtTime(0.5, t + 0.005);
      gn.gain.exponentialRampToValueAtTime(0.0001, t + 0.14);
      o.connect(gn).connect(master);
      o.start(t);
      o.stop(t + 0.2);
      burst("highpass", 2500, 0.15, 0.05);
    },
    splash() {
      burst("bandpass", 900, 0.35, 0.4);
      burst("lowpass", 400, 0.25, 0.25);
    },
    close() {
      try { ac.close(); } catch (e) { /* already closed */ }
    },
  };
}

/* ---- the spoon's helpers ---- */
const SPOON_WASH = 0.8;
const SPOON_PALETTE = ["#efe3c4", "#6b3a17", "#d8b24a", "#b8452f", "#7a3f7e", "#8fb35a"];

function spoonRgb(hex) {
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || ""));
  if (!m) return [214, 170, 96];
  const n = parseInt(m[1], 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function spoonCss(rgb, a) {
  return `rgba(${rgb[0] | 0}, ${rgb[1] | 0}, ${rgb[2] | 0}, ${a})`;
}

/* what the wash is turning into: plain amber, coloured by each ingredient mixed in so far */
function spoonTarget(g) {
  let r = 138, gr = 84, b = 33, w = 1;
  for (let k = 0; k < g.added; k++) {
    const rgb = g.trayItems[g.needed[k]].rgb;
    r += rgb[0] * 0.45; gr += rgb[1] * 0.45; b += rgb[2] * 0.45; w += 0.45;
  }
  return [r / w, gr / w, b / w];
}

function spoonParticle(g, x, y, vx, vy, rgb, size, life) {
  if (g.particles.length > 220) return;
  g.particles.push({ x, y, vx, vy, rgb, size, life, age: 0 });
}

function spoonSplash(g, x, y, rgb, n, power) {
  for (let k = 0; k < n; k++) {
    const a = Math.random() * Math.PI * 2, v = (0.3 + Math.random() * 0.7) * power;
    spoonParticle(g, x, y, Math.cos(a) * v, Math.sin(a) * v, rgb, 0.015 + Math.random() * 0.025, 0.4 + Math.random() * 0.4);
  }
  g.particles.push({ x, y, vx: 0, vy: 0, rgb: [255, 246, 226], size: 0.05, life: 0.45, age: 0, ring: true });
}

/* the wash, drawn: colour, swirl, sheen, wake, lumps, bubbles, foam, particles */
function spoonDraw(g) {
  const cv = g.canvas, ctx = g.ctx;
  const cssW = cv.clientWidth;
  if (!cssW) return;
  const dpr = Math.min(2, window.devicePixelRatio || 1);
  const W = Math.round(cssW * dpr);
  if (cv.width !== W) { cv.width = W; cv.height = W; }
  const c = W / 2, rad = W / 2;
  const P = (u) => c + u * rad; /* wash units (-1..1) to pixels */
  const col = g.color;

  ctx.clearRect(0, 0, W, W);
  ctx.save();
  ctx.beginPath();
  ctx.arc(c, c, rad, 0, Math.PI * 2);
  ctx.clip();

  /* the body of the wash */
  const light = col.map((v) => Math.min(255, v * 1.45 + 18));
  const dark = col.map((v) => v * 0.45);
  const base = ctx.createRadialGradient(P(-0.18), P(-0.24), rad * 0.05, c, c, rad);
  base.addColorStop(0, spoonCss(light, 1));
  base.addColorStop(0.55, spoonCss(col, 1));
  base.addColorStop(1, spoonCss(dark, 1));
  ctx.fillStyle = base;
  ctx.fillRect(0, 0, W, W);

  /* a new ingredient's colour, curling round with the stir */
  const curl = 2.2 + Math.min(3, g.speed) * 0.8;
  ctx.lineCap = "round";
  for (const ink of g.inks) {
    ctx.strokeStyle = spoonCss(ink.rgb, 0.55 * ink.amt);
    ctx.lineWidth = rad * (0.08 + 0.12 * ink.amt);
    ctx.beginPath();
    for (let t = 0.08; t <= 0.95; t += 0.04) {
      const a = ink.a + g.stirAngle - t * curl * g.dir;
      const px = P(Math.cos(a) * t), py = P(Math.sin(a) * t);
      if (t === 0.08) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.stroke();
  }

  /* streaks in the wash, bending more the faster it goes */
  const streakA = Math.min(0.32, 0.06 + g.speed * 0.18);
  ctx.strokeStyle = spoonCss(light, streakA);
  ctx.lineWidth = rad * 0.025;
  for (let k = 0; k < 7; k++) {
    ctx.beginPath();
    for (let t = 0.12; t <= 0.92; t += 0.05) {
      const a = (k / 7) * Math.PI * 2 + g.stirAngle - t * curl * g.dir;
      const px = P(Math.cos(a) * t), py = P(Math.sin(a) * t);
      if (t === 0.12) ctx.moveTo(px, py); else ctx.lineTo(px, py);
    }
    ctx.stroke();
  }

  /* the sheen: glossier as it comes smooth, brighter on a streak */
  const gloss = 0.06 + 0.22 * g.mix + 0.18 * g.streak;
  const sa = g.stirAngle * 0.25;
  const sheen = ctx.createRadialGradient(P(Math.cos(sa) * 0.35), P(Math.sin(sa) * 0.35 - 0.1), 0,
    P(Math.cos(sa) * 0.35), P(Math.sin(sa) * 0.35 - 0.1), rad * 0.55);
  sheen.addColorStop(0, `rgba(255, 248, 230, ${gloss.toFixed(3)})`);
  sheen.addColorStop(1, "rgba(255, 248, 230, 0)");
  ctx.fillStyle = sheen;
  ctx.fillRect(0, 0, W, W);

  /* the spoon's wake */
  for (let k = 1; k < g.wake.length; k++) {
    const a = g.wake[k - 1], b = g.wake[k];
    const life = 1 - (g.elapsed - b.t) / 0.6;
    if (life <= 0) continue;
    ctx.strokeStyle = `rgba(255, 244, 222, ${(0.35 * life).toFixed(3)})`;
    ctx.lineWidth = rad * (0.03 + 0.05 * life);
    ctx.beginPath();
    ctx.moveTo(P(a.x), P(a.y));
    ctx.lineTo(P(b.x), P(b.y));
    ctx.stroke();
  }

  /* lumps of what was just added, bobbing as they drift */
  for (const l of g.lumps) {
    const lx = Math.cos(l.a) * l.r, ly = Math.sin(l.a) * l.r;
    const s = l.size * (1 + Math.sin(l.wob) * 0.06);
    ctx.fillStyle = "rgba(0, 0, 0, 0.28)";
    ctx.beginPath();
    ctx.arc(P(lx + 0.012), P(ly + 0.02), s * rad, 0, Math.PI * 2);
    ctx.fill();
    for (let k = 0; k < 3; k++) {
      const oa = l.wob * 0.3 + k * 2.1;
      const ox = lx + Math.cos(oa) * s * 0.35, oy = ly + Math.sin(oa) * s * 0.35;
      const lump = ctx.createRadialGradient(P(ox - s * 0.25), P(oy - s * 0.3), 0, P(ox), P(oy), s * 0.75 * rad);
      lump.addColorStop(0, spoonCss(l.rgb.map((v) => Math.min(255, v * 1.35 + 20)), 1));
      lump.addColorStop(1, spoonCss(l.rgb.map((v) => v * 0.6), 1));
      ctx.fillStyle = lump;
      ctx.beginPath();
      ctx.arc(P(ox), P(oy), s * 0.72 * rad, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  /* fermentation bubbles: a ring that swells and pops */
  for (const b of g.bubbles) {
    const t = b.age / b.life;
    ctx.strokeStyle = `rgba(255, 246, 226, ${(0.55 * (1 - t)).toFixed(3)})`;
    ctx.lineWidth = Math.max(1, rad * 0.006);
    ctx.beginPath();
    ctx.arc(P(b.x), P(b.y), b.size * (0.6 + t * 0.8) * rad, 0, Math.PI * 2);
    ctx.stroke();
  }

  /* froth: foam creeping in from the rim, heaving when it is about to go over */
  const fr = Math.min(1, g.froth);
  if (fr > 0.01) {
    const heave = fr > 0.7 ? Math.sin(g.elapsed * 9) * 0.02 * fr : 0;
    const reach = fr * 0.5;
    for (const f of g.foam) {
      if (f.depth > fr) break;
      const r = 1 - f.depth * reach + heave + Math.sin(g.elapsed * 3 + f.a * 5) * 0.008;
      const a = f.a + g.stirAngle * 0.6;
      ctx.fillStyle = `rgba(252, 247, 236, ${(0.75 + 0.25 * (1 - f.depth)).toFixed(3)})`;
      ctx.beginPath();
      ctx.arc(P(Math.cos(a) * r), P(Math.sin(a) * r), f.size * (0.8 + fr) * rad, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  /* splashes and bursts */
  for (const p of g.particles) {
    const t = p.age / p.life;
    if (p.ring) {
      ctx.strokeStyle = spoonCss(p.rgb, 0.7 * (1 - t));
      ctx.lineWidth = rad * 0.015;
      ctx.beginPath();
      ctx.arc(P(p.x), P(p.y), (p.size + t * 0.25) * rad, 0, Math.PI * 2);
      ctx.stroke();
    } else {
      ctx.fillStyle = spoonCss(p.rgb, 0.9 * (1 - t));
      ctx.beginPath();
      ctx.arc(P(p.x), P(p.y), p.size * (1 - t * 0.5) * rad, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  ctx.restore();
}

/* The spoon's sounds, made on the spot */
function spoonAudio(volume) {
  let ac = null;
  try {
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    ac = new AC();
  } catch (e) {
    return null;
  }
  const master = ac.createGain();
  master.gain.value = Math.max(0, Math.min(1, volume));
  master.connect(ac.destination);

  const noise = ac.createBuffer(1, ac.sampleRate, ac.sampleRate);
  const data = noise.getChannelData(0);
  for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;

  const env = (node, peak, attack, decay) => {
    const t = ac.currentTime;
    node.gain.setValueAtTime(0.0001, t);
    node.gain.exponentialRampToValueAtTime(peak, t + attack);
    node.gain.exponentialRampToValueAtTime(0.0001, t + attack + decay);
  };
  const tone = (type, from, to, peak, decay, delay) => {
    const o = ac.createOscillator(), gn = ac.createGain();
    o.type = type;
    const t = ac.currentTime + (delay || 0);
    o.frequency.setValueAtTime(from, t);
    o.frequency.exponentialRampToValueAtTime(to, t + decay);
    gn.gain.setValueAtTime(0.0001, t);
    gn.gain.exponentialRampToValueAtTime(peak, t + 0.01);
    gn.gain.exponentialRampToValueAtTime(0.0001, t + decay);
    o.connect(gn).connect(master);
    o.start(t);
    o.stop(t + decay + 0.05);
  };
  const burst = (filterType, freq, peak, decay) => {
    const src = ac.createBufferSource(), f = ac.createBiquadFilter(), gn = ac.createGain();
    src.buffer = noise;
    f.type = filterType;
    f.frequency.value = freq;
    env(gn, peak, 0.005, decay);
    src.connect(f).connect(gn).connect(master);
    src.start();
    src.stop(ac.currentTime + decay + 0.05);
  };

  /* the wash's swish: a looped murmur whose loudness follows the stir */
  let swishGain = null;
  const startSwish = () => {
    const src = ac.createBufferSource(), f = ac.createBiquadFilter();
    swishGain = ac.createGain();
    src.buffer = noise;
    src.loop = true;
    f.type = "lowpass";
    f.frequency.value = 650;
    swishGain.gain.value = 0;
    src.connect(f).connect(swishGain).connect(master);
    src.start();
  };

  return {
    wake() { if (ac.state === "suspended") ac.resume(); },
    plop() { tone("sine", 520, 140, 0.5, 0.22); },
    crunch() { burst("bandpass", 1900, 0.35, 0.07); },
    fizz() { burst("highpass", 2800, 0.4, 0.55); },
    tick() { tone("square", 150, 120, 0.12, 0.07); },
    chime() { tone("sine", 660, 660, 0.3, 0.7); tone("sine", 990, 990, 0.25, 0.8, 0.12); },
    swish(level) {
      if (!swishGain) startSwish();
      swishGain.gain.setTargetAtTime(0.18 * level, ac.currentTime, 0.08);
    },
    close() { try { ac.close(); } catch (e) { /* already closed */ } },
  };
}

/* The pot's rim marks, clockwise from the top */
const POT_KEYS = ["W", "D", "S", "A"];
const POT_EPS = 1e-6;

function potPlaceChip(g) {
  if (!g.drop) return;
  const a = (g.drop.pos * Math.PI) / 2;
  g.chipEl.style.left = 50 + 30 * Math.sin(a) + "%";
  g.chipEl.style.top = 50 - 30 * Math.cos(a) + "%";
  g.chipEl.innerText = g.drop.label;
  g.chipEl.dataset.key = g.drop.pos + "|" + g.drop.label;
  g.chipEl.classList.remove("folded");
}

/* The arrow keys stand in for WASD in every game that reads letters */
const CG_ARROW_KEYS = { ArrowUp: "W", ArrowLeft: "A", ArrowDown: "S", ArrowRight: "D" };
const CG_ARROW_GLYPHS = { W: "↑", A: "←", S: "↓", D: "→" };

/* ---------------------------------------------------------------- */
/*  Running one                                                      */
/* ---------------------------------------------------------------- */
function cgStart(data) {
  if (skillGame) cgStop();

  const spec = data.game || {};
  const mode = CG_MODES[spec.type] ? spec.type : "bar";
  const root = document.getElementById("minigame");
  const stage = document.getElementById("cg-stage");

  skillGame = {
    mode,
    spec,
    text: data.text || {},
    time: spec.time || 12,
    strikes: Math.max(0, spec.strikes || 0),
    misses: 0,
    done: 0,
    total: 1,
    elapsed: 0,
    ready: 0.7,
    live: false,
    over: false,
    last: performance.now(),
  };

  document.getElementById("cg-title").innerText = (data.title || "").toUpperCase();
  document.getElementById("cg-hint").innerText = data.hint || "";
  document.getElementById("cg-quit").innerText = skillGame.text.giveUp || "ESC to give up";

  stage.innerHTML = "";
  stage.className = "cg-stage mode-" + mode;
  CG_MODES[mode].init(skillGame, stage);
  CG_MODES[mode].render(skillGame);
  cgRenderFoot();
  cgRenderTimer();

  cgBanner(skillGame.text.ready || "Steady...", "ready");
  root.className = "visible" + (spec.compact ? " compact" : "") + (spec.minimal ? " minimal" : "")
    + (spec.anchor === "high" ? " high" : "") + (spec.mouse ? " mouse" : "");
  /* a mouse game (the spoon): the page takes the mouse for as long as it runs */
  document.body.classList.toggle("mouse-game", !!spec.mouse);

  requestAnimationFrame(cgLoop);
}

function cgRenderTimer() {
  const g = skillGame;
  const left = Math.max(0, 1 - g.elapsed / g.time);
  const fill = document.getElementById("cg-timer-fill");
  fill.style.width = cgPct(left);
  fill.classList.toggle("low", left < 0.25);
}

function cgLoop(now) {
  const g = skillGame;
  if (!g || g.stopped) return;

  const dt = Math.min(0.05, (now - g.last) / 1000);
  g.last = now;

  if (!g.over) {
    if (!g.live) {
      g.ready -= dt;
      if (g.ready <= 0) {
        g.live = true;
        cgBanner("");
      }
    } else {
      g.elapsed += dt;
      CG_MODES[g.mode].update(g, dt);
      if (!g.over && g.elapsed >= g.time) cgFinish(false);
    }
    CG_MODES[g.mode].render(g);
    cgRenderTimer();
  }

  requestAnimationFrame(cgLoop);
}

/* Stamp the result, hold it a moment, then answer Lua */
function cgFinish(passed, quit) {
  const g = skillGame;
  if (!g || g.over) return;
  g.over = true;
  g.holding = false;

  const root = document.getElementById("minigame");
  root.classList.add(passed ? "won" : "lost");
  cgBanner(passed ? g.winText || g.text.win || "Well Done"
    : quit ? g.text.quit || "Gave Up" : g.loseText || g.text.lose || "Botched", passed ? "win" : "lose");

  /* A compact game is one of a run */
  setTimeout(() => {
    if (skillGame !== g) return;
    cgStop();
    fetch(`https://${GetParentResourceName()}/minigameResult`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      /* a game that grades the play (taste) sends its 0 - 1 score too; giving up sends none */
      body: JSON.stringify({
        passed: !!passed,
        score: !quit && typeof g.score === "number" ? g.score : undefined,
        /* a game of rounds (bottle) sends how each went; giving up sends none */
        outcomes: !quit && Array.isArray(g.outcomes) ? g.outcomes : undefined,
      }),
    });
  }, g.spec.compact && passed ? 350 : 750);
}

/* Take it off screen without answering - Lua has already given up on it */
function cgStop() {
  if (skillGame) {
    skillGame.stopped = true;
    if (skillGame.cleanup) skillGame.cleanup();
  }
  skillGame = null;
  document.getElementById("minigame").className = "";
  document.body.classList.remove("mouse-game");
  cgBanner("");
}

window.addEventListener("keydown", (e) => {
  const g = skillGame;
  if (!g || g.over) return;

  if (e.code === "Space") {
    e.preventDefault();
    if (g.mode === "hold" || CG_MODES[g.mode].holds) g.holding = true;
    else if (g.live && !e.repeat) CG_MODES[g.mode].press(g);
  } else if (g.live && !e.repeat && CG_MODES[g.mode].key) {
    CG_MODES[g.mode].key(g, e.code);
  }
});

window.addEventListener("keyup", (e) => {
  const g = skillGame;
  if (!g) return;

  if (e.code === "Space") g.holding = false;
  if (e.key === "Escape") cgFinish(false, true);
});

/* ------------------------------------------------------------------ */
/*  Tasting: the bottle picker and the tasting-notes card              */
/*                                                                     */
/*  tastePicker   the tasting cup and a shelf of the untasted bottles. */
/*                Has the cursor: hover or the arrows choose a bottle  */
/*                and pour it into the cup (fresh or crate-aged tint), */
/*                a click or Enter sips it - the cup tips and drains - */
/*                then posts tastePick. Esc posts tasteCancel.         */
/*  tastingCard   what the sip revealed, on the dark plate: the grade  */
/*                as pelt stars (Normal one, Good two, Perfect three), */
/*                the heat score on a scale, notes inked in one by one,*/
/*                flaws in red. No focus; a bar drains, then it fades. */
/*  Every word comes from Lua (Config.Text.Tasting), already formatted */
/* ------------------------------------------------------------------ */
let tastePickerOpen = false;
let tasteCardTimer = null;
let tasteCardLeave = null;
let tastePicker = null;

const TASTE_SIP_MS = 520;
const TASTE_CUP_EMPTY = 112;
const TASTE_CUP_FULL = 52;     /* ... and poured */

/* written out per callback (not one helper with the name in a variable) so the code map can pair both ends */
function tastePick(id) {
  fetch(`https://${GetParentResourceName()}/tastePick`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({ id }),
  });
}

function tasteCancel() {
  fetch(`https://${GetParentResourceName()}/tasteCancel`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({}),
  });
}

function tasteTint(bottle) {
  if (!tastePicker || !bottle) return "transparent";
  return bottle.aged ? tastePicker.agedTint : tastePicker.tint;
}

/* pour the chosen bottle into the cup */
function tasteChoose(index, scroll) {
  if (!tastePicker || tastePicker.sipping || tastePicker.list.length === 0) return;
  const n = tastePicker.list.length;
  index = ((index % n) + n) % n;
  const changed = index !== tastePicker.sel;
  tastePicker.sel = index;

  const rows = document.getElementById("tp-list").children;
  for (let i = 0; i < rows.length; i++) rows[i].classList.toggle("sel", i === index);
  if (scroll && rows[index]) rows[index].scrollIntoView({ block: "nearest" });

  const bottle = tastePicker.list[index];
  const cup = document.getElementById("tp-cup");
  cup.style.setProperty("--tint", tasteTint(bottle));
  document.getElementById("tp-liquid").style.transform = "translateY(" + TASTE_CUP_FULL + "px)";
  cup.classList.add("filled");
  if (changed) replay(cup, "pour");

  document.getElementById("tp-pick-name").innerText = bottle.label || "";
  const aged = document.getElementById("tp-pick-aged");
  aged.innerText = bottle.aged || "";
  aged.style.display = bottle.aged ? "" : "none";
}

/* tip the cup, then start the tasting */
function tasteSip(index) {
  if (!tastePickerOpen || !tastePicker || tastePicker.sipping) return;
  if (typeof index === "number" && index !== tastePicker.sel) tasteChoose(index, false);
  const bottle = tastePicker.list[tastePicker.sel];
  if (!bottle) return;

  tastePicker.sipping = true;
  const root = document.getElementById("taste-picker");
  root.classList.add("sipping");
  document.getElementById("tp-liquid").style.transform = "translateY(" + TASTE_CUP_EMPTY + "px)";
  tastePicker.timer = setTimeout(() => {
    if (!tastePickerOpen) return;
    hideTastePicker();
    tastePick(bottle.id);
  }, TASTE_SIP_MS);
}

const TASTE_BOTTLE =
  '<svg viewBox="0 0 24 60" aria-hidden="true">' +
  '<path class="g" d="M9.4 6.5h5.2v11.4c2 2 5.4 4.6 5.4 9.1v26a3.5 3.5 0 0 1-3.5 3.5h-9A3.5 3.5 0 0 1 4 53V27c0-4.5 3.4-7.1 5.4-9.1z"/>' +
  '<path class="l" d="M5.4 27.4c0-3.6 2.8-5.8 5.4-8.3V13h2.4v6.1c2.6 2.5 5.4 4.7 5.4 8.3v25.3a2.2 2.2 0 0 1-2.2 2.2H7.6a2.2 2.2 0 0 1-2.2-2.2z"/>' +
  '<rect class="p" x="6.4" y="31" width="11.2" height="9.5" rx="0.6"/>' +
  '<text class="q" x="12" y="38.6" text-anchor="middle">?</text>' +
  '<rect class="c" x="9" y="1.5" width="6" height="6.5" rx="1.2"/>' +
  "</svg>";

function showTastePicker(data) {
  const t = data.text || {};
  clearTimeout(tastePicker && tastePicker.timer);
  tastePicker = {
    list: Array.isArray(data.list) ? data.list : [],
    sel: -1,
    tint: data.tint || "#d9d0b4",
    agedTint: data.agedTint || "#b8742a",
    sipping: false,
    timer: null,
  };

  document.getElementById("tp-title").innerText = t.title || "";
  document.getElementById("tp-sip").innerText = t.taste || "";
  document.getElementById("tp-sip").style.display = t.taste ? "" : "none";

  /* the key strip, or the old one-line hint if no keys were sent */
  const keys = t.keys || null;
  const keysEl = document.getElementById("tp-keys");
  keysEl.innerHTML = "";
  if (keys) {
    [
      ["← → ↑ ↓", keys.Select],
      [keys.Enter || "Enter", keys.Taste],
      [keys.Esc || "Esc", keys.Leave],
    ].forEach(([key, label]) => {
      if (!label) return;
      const k = cgEl("span", "tp-key", keysEl);
      cgEl("kbd", "", k).innerText = key;
      cgEl("span", "", k).innerText = label;
    });
  }
  keysEl.style.display = keys ? "" : "none";
  const hint = document.getElementById("tp-hint");
  hint.innerText = t.hint || "";
  hint.style.display = keys ? "none" : "";

  const list = document.getElementById("tp-list");
  list.innerHTML = "";
  tastePicker.list.forEach((bottle, index) => {
    const row = cgEl("button", "tp-row", list);
    row.type = "button";
    row.style.animationDelay = Math.min(index, 12) * 40 + "ms";
    row.style.setProperty("--tint", tasteTint(bottle));
    if (bottle.aged) row.classList.add("aged");

    const icon = cgEl("span", "tp-icon", row);
    icon.innerHTML = TASTE_BOTTLE;
    if (bottle.count > 1) cgEl("span", "tp-count", icon).innerText = "×" + bottle.count;
    cgEl("span", "tp-name", row).innerText = bottle.label || "";
    if (bottle.aged) cgEl("span", "tp-aged", row).innerText = bottle.aged;

    row.addEventListener("mouseenter", () => tasteChoose(index, false));
    row.addEventListener("click", () => tasteSip(index));
  });

  const root = document.getElementById("taste-picker");
  root.classList.remove("sipping", "leaving");
  const cup = document.getElementById("tp-cup");
  cup.classList.remove("filled");
  document.getElementById("tp-liquid").style.transform = "translateY(" + TASTE_CUP_EMPTY + "px)";

  tastePickerOpen = true;
  replay(root, "show");
  /* pour the first one in a beat after the slip arrives */
  setTimeout(() => { if (tastePickerOpen && tastePicker && tastePicker.sel < 0) tasteChoose(0, false); }, 160);
}

function hideTastePicker() {
  tastePickerOpen = false;
  if (tastePicker) clearTimeout(tastePicker.timer);
  tastePicker = null;
  document.getElementById("taste-picker").classList.remove("show", "sipping");
}

/* the pelt stars */
const TASTE_STARS = { normal: 1, good: 2, perfect: 3 };

function showTastingCard(data) {
  const card = document.getElementById("taste-card");
  const t = data.text || {};
  const quality = String(data.quality || "").toLowerCase();

  document.getElementById("tc-title").innerText = t.title || "";
  document.getElementById("tc-product").innerText = data.product || "";
  const grade = document.getElementById("tc-grade");
  grade.innerText = data.grade || "?";
  card.dataset.quality = quality;

  const stars = TASTE_STARS[quality] || 0;
  const starEls = document.getElementById("tc-stars").children;
  for (let i = 0; i < starEls.length; i++) {
    starEls[i].classList.toggle("on", i < stars);
    starEls[i].style.animationDelay = 260 + i * 180 + "ms";
  }
  document.getElementById("tc-stars").style.display = stars ? "" : "none";

  /* the heat score: a scale when the number came, the words alone otherwise */
  const scoreRow = document.getElementById("tc-score-row");
  scoreRow.style.display = data.scoreText ? "" : "none";
  document.getElementById("tc-score").innerText = data.scoreText || "";
  const hasNum = typeof data.score === "number";
  /* the words already carry the figure (CardScore); the number slot stays for a server's own wording */
  document.getElementById("tc-score-num").innerText = hasNum && !/\d/.test(data.scoreText || "") ? Math.round(data.score) : "";
  scoreRow.classList.toggle("words", !hasNum);
  const fill = document.getElementById("tc-score-fill");
  fill.style.width = "0%";
  if (hasNum) setTimeout(() => { fill.style.width = Math.max(0, Math.min(100, data.score)) + "%"; }, 420);

  /* notes then flaws, inked in one after another */
  let delay = 520;
  document.getElementById("tc-notes-head").innerText = t.notes || "";
  const notes = document.getElementById("tc-notes");
  notes.innerHTML = "";
  (data.notes || []).forEach((n) => {
    const chip = cgEl("span", "tc-chip", notes);
    chip.innerText = n;
    chip.style.animationDelay = delay + "ms";
    delay += 140;
  });

  document.getElementById("tc-flaws-head").innerText = t.flaws || "";
  const flaws = document.getElementById("tc-flaws");
  flaws.innerHTML = "";
  if ((data.flaws || []).length === 0) {
    const none = cgEl("li", "tc-none", flaws);
    none.innerText = t.none || "";
    none.style.animationDelay = delay + "ms";
  }
  (data.flaws || []).forEach((f) => {
    const li = cgEl("li", "tc-flaw", flaws);
    li.innerText = f;
    li.style.animationDelay = delay + "ms";
    delay += 160;
  });

  document.getElementById("tc-partial").innerText = data.full ? "" : t.partial || "";

  /* how long it stays: a bar that drains */
  const ms = Math.max(2000, data.ms || 10000);
  const timer = document.getElementById("tc-timer");
  timer.style.transition = "none";
  timer.style.width = "100%";
  void timer.offsetWidth;
  timer.style.transition = "width " + ms + "ms linear";
  timer.style.width = "0%";

  clearTimeout(tasteCardTimer);
  clearTimeout(tasteCardLeave);
  card.classList.remove("leaving");
  replay(card, "show");

  tasteCardTimer = setTimeout(() => {
    card.classList.add("leaving");
    tasteCardLeave = setTimeout(() => card.classList.remove("show", "leaving"), 380);
  }, ms);
}

/* the cup's keys; Esc is in document.onkeyup with the other UIs */
window.addEventListener("keydown", (e) => {
  if (!tastePickerOpen || !tastePicker || tastePicker.sipping) return;
  const cols = 3;
  const sel = Math.max(0, tastePicker.sel);
  if (e.key === "ArrowRight") tasteChoose(sel + 1, true);
  else if (e.key === "ArrowLeft") tasteChoose(sel - 1, true);
  else if (e.key === "ArrowDown") tasteChoose(Math.min(tastePicker.list.length - 1, sel + cols), true);
  else if (e.key === "ArrowUp") tasteChoose(Math.max(0, sel - cols), true);
  else if (e.key === "Enter") { if (!e.repeat) tasteSip(); }
  else return;
  e.preventDefault();
});

document.getElementById("tp-sip").addEventListener("click", () => tasteSip());

/* ------------------------------------------------------------------ */
/*  The buyer's ledger (GSC.Buyers / GSC.Market)                       */
/*                                                                     */
/*  buyerLedger       open it: the buyer, your trust, every stack he'd */
/*                    take with his price and why; steppers per row    */
/*  buyerLedgerDone   the deal went through: stamp it                  */
/*  buyerLedgerClose  take it away                                     */
/*  Shake on it posts buyerSell { buyer, lines: [{ id, qty }] } - the  */
/*  server prices it all again; the total here is only what it shows.  */
/*                                                                     */
/*  Drawn as the game's own shop menu: a dark brush plate, cash with   */
/*  the cents raised. It has NUI focus, so it takes the mouse and the  */
/*  keys: Up / Down pick a line, Left / Right the amount (Shift: all   */
/*  or none), Backspace clears it, Enter is HELD to shake on it (the   */
/*  button fills; let go early and nothing is sold), Esc walks away.   */
/*  Appetite is what the next bottle fetches of his full price - the   */
/*  same falloff as Market.DemandRate - so you watch it sink as you    */
/*  pile bottles on the table.                                         */
/* ------------------------------------------------------------------ */
let ledger = null;

const LEDGER_HOLD_MS = 650;  /* how long Shake On It is held */
const LEDGER_ROLL_MS = 380;

function ledgerRound(x) {
  return Math.floor(x * 100 + 0.5) / 100;
}

function ledgerRate(n) {
  return Math.max(ledger.floor, 1 - ledger.drop * n);
}

/* the same falloff as Market.LineTotal: each bottle a little cheaper than the last */
function ledgerTotal() {
  if (!ledger) return { total: 0, bottles: 0, lines: {} };
  let n = ledger.soldBefore || 0;
  let total = 0;
  let bottles = 0;
  const lines = {};
  for (const row of ledger.rows) {
    const q = ledger.qty[row.id] || 0;
    let line = 0;
    for (let i = 0; i < q; i++) {
      line += ledgerRound(row.unit * ledgerRate(n));
      n += 1;
    }
    lines[row.id] = ledgerRound(line);
    total += line;
    bottles += q;
  }
  return { total: ledgerRound(total), bottles, lines };
}

function ledgerMoney(x) {
  return "$" + (Math.round(x * 100) / 100).toFixed(2);
}

/* $50.92 the way the game prints cash: the dollar sign and cents raised */
function ledgerCash(el, x) {
  const [whole, cents] = (Math.round(Math.max(0, x) * 100) / 100).toFixed(2).split(".");
  el.innerHTML = "";
  cgEl("sup", "bl-cash-sign", el).innerText = "$";
  cgEl("span", "bl-cash-whole", el).innerText = whole;
  cgEl("sup", "bl-cash-cents", el).innerText = cents;
}

function ledgerTextFmt(template, n) {
  return String(template || "%d").replace("%d", n);
}

/* ---- the total rolls to its new figure rather than snapping ---- */
let ledgerRoll = { shown: 0, from: 0, to: 0, start: 0, raf: 0, land: 0 };

function ledgerRollTo(value) {
  const el = document.getElementById("bl-total");
  cancelAnimationFrame(ledgerRoll.raf);
  clearTimeout(ledgerRoll.land);
  ledgerRoll.from = ledgerRoll.shown;
  ledgerRoll.to = value;
  ledgerRoll.start = performance.now();
  if (Math.abs(ledgerRoll.to - ledgerRoll.from) < 0.005) {
    ledgerRoll.shown = value;
    ledgerCash(el, value);
    return;
  }
  replay(el, "bump");
  const tick = (now) => {
    const k = Math.min(1, (now - ledgerRoll.start) / LEDGER_ROLL_MS);
    const eased = 1 - Math.pow(1 - k, 3);
    ledgerRoll.shown = ledgerRoll.from + (ledgerRoll.to - ledgerRoll.from) * eased;
    ledgerCash(el, ledgerRoll.shown);
    if (k < 1) ledgerRoll.raf = requestAnimationFrame(tick);
  };
  ledgerRoll.raf = requestAnimationFrame(tick);
  /* frames are only the show: the figure always lands, even if none are drawn */
  ledgerRoll.land = setTimeout(() => {
    cancelAnimationFrame(ledgerRoll.raf);
    ledgerRoll.shown = value;
    ledgerCash(el, value);
  }, LEDGER_ROLL_MS + 40);
}

/* ---- meters ---- */
function ledgerMeter(prefix, fraction) {
  const pct = Math.max(0, Math.min(1, fraction)) * 100 + "%";
  document.getElementById(prefix + "-fill").style.width = pct;
  document.getElementById(prefix + "-needle").style.left = pct;
}

function ledgerTrust(trust) {
  const v = Math.max(0, Math.min(100, trust || 0));
  ledgerMeter("bl-trust", v / 100);
  document.getElementById("bl-trust-num").innerText = Math.round(v);
  const meter = document.getElementById("bl-trust");
  const refuse = ledger && typeof ledger.refuse === "number" ? ledger.refuse : null;
  meter.classList.toggle("low", refuse !== null && v < refuse + 10);
  meter.classList.toggle("high", v >= 75);
}

/* ---- what a tag says, from the words it was written with ---- */
function ledgerTagClass(tag) {
  const tags = (ledger && ledger.text && ledger.text.tags) || {};
  if (tag === tags.Tainted || tag === tags.Soured) return "bad";
  if (tag === tags.Untasted) return "dim";
  if (tag === tags.Tasted) return "good";
  const aged = String(tags.Aged || "").split("%s")[0];
  if (aged && tag.indexOf(aged) === 0) return "gold";
  return "";
}

const LEDGER_BOTTLE =
  '<svg viewBox="0 0 24 60" aria-hidden="true">' +
  '<path class="g" d="M9.4 6.5h5.2v11.4c2 2 5.4 4.6 5.4 9.1v26a3.5 3.5 0 0 1-3.5 3.5h-9A3.5 3.5 0 0 1 4 53V27c0-4.5 3.4-7.1 5.4-9.1z"/>' +
  '<path class="l" d="M5.4 27.4c0-3.6 2.8-5.8 5.4-8.3V13h2.4v6.1c2.6 2.5 5.4 4.7 5.4 8.3v25.3a2.2 2.2 0 0 1-2.2 2.2H7.6a2.2 2.2 0 0 1-2.2-2.2z"/>' +
  '<rect class="p" x="6.4" y="31" width="11.2" height="9.5" rx="0.6"/>' +
  '<rect class="c" x="9" y="1.5" width="6" height="6.5" rx="1.2"/>' +
  "</svg>";

/* ---- picking a line ---- */
function ledgerSelect(index, scroll) {
  if (!ledger || ledger.rows.length === 0) return;
  const n = ledger.rows.length;
  ledger.sel = ((index % n) + n) % n;
  ledger.rows.forEach((row, i) => row.el.classList.toggle("sel", i === ledger.sel));
  if (scroll) ledger.rows[ledger.sel].el.scrollIntoView({ block: "nearest" });
}

function ledgerSetQty(row, q) {
  if (!ledger || ledger.done || ledger.sending) return;
  const before = ledger.qty[row.id] || 0;
  const used = ledgerTotal().bottles - before;
  const room = Math.max(0, ledger.left - used);
  ledger.qty[row.id] = Math.max(0, Math.min(row.count, room, q));
  if (ledger.qty[row.id] !== before) {
    replay(row.el.querySelector(".bl-qty"), ledger.qty[row.id] > before ? "up" : "down");
  } else if (q > before) {
    replay(row.el, "refuse"); /* hit his limit or the stack's end */
  }
  ledgerRender();
}

function ledgerOfferAll() {
  if (!ledger || ledger.done || ledger.sending) return;
  const { bottles } = ledgerTotal();
  const most = Math.min(ledger.left, ledger.rows.reduce((s, r) => s + r.count, 0));
  if (bottles >= most && bottles > 0) {
    ledger.qty = {};
  } else {
    let room = ledger.left;
    ledger.rows.forEach((row) => {
      const q = Math.min(row.count, room);
      ledger.qty[row.id] = q;
      room -= q;
    });
  }
  ledger.rows.forEach((row) => replay(row.el.querySelector(".bl-qty"), "up"));
  ledgerRender();
}

function ledgerRender() {
  const t = ledger.text || {};
  const rowsEl = document.getElementById("bl-rows");
  const { total, bottles, lines } = ledgerTotal();

  ledger.rows.forEach((row) => {
    const el = row.el;
    const q = ledger.qty[row.id] || 0;
    el.querySelector(".bl-qty").innerText = q;
    el.classList.toggle("picked", q > 0);
    el.querySelector(".bl-minus").disabled = q <= 0;

    const sub = el.querySelector(".bl-sub");
    if (q > 0) {
      sub.querySelector(".bl-sub-n").innerText = ledgerTextFmt(t.bottles || "%d", q);
      const full = ledgerRound(row.unit * q);
      const struck = sub.querySelector(".bl-sub-full");
      struck.innerText = lines[row.id] < full - 0.005 ? ledgerMoney(full) : "";
      sub.querySelector(".bl-sub-sum").innerText = ledgerMoney(lines[row.id]);
    }
  });

  ledgerRollTo(total);
  const left = Math.max(0, ledger.left - bottles);
  document.getElementById("bl-left").innerText = ledgerTextFmt(t.left, left);
  document.getElementById("bl-left").classList.toggle("none", left === 0);

  const sell = document.getElementById("bl-sell");
  sell.disabled = bottles === 0 || !!ledger.sending;
  rowsEl.classList.toggle("full", bottles >= ledger.left);

  const most = Math.min(ledger.left, ledger.rows.reduce((s, r) => s + r.count, 0));
  document.getElementById("bl-all-in").innerText =
    bottles >= most && bottles > 0 ? t.clear || "" : t.offerAll || "";
  document.getElementById("bl-all-in").disabled = most === 0;

  /* appetite: what the NEXT bottle on the table would fetch */
  const next = ledgerRate((ledger.soldBefore || 0) + bottles);
  ledgerMeter("bl-appetite", next);
  document.getElementById("bl-appetite-num").innerText = Math.round(next * 100) + "%";
  document.getElementById("bl-appetite").classList.toggle("low", next <= ledger.floor + 0.001);
}

function showLedger(data) {
  const t = data.text || {};
  ledger = {
    buyer: data.buyer,
    rows: Array.isArray(data.rows) ? data.rows : [],
    qty: {},
    left: Math.max(0, data.left || 0),
    soldBefore: data.soldBefore || 0,
    drop: typeof data.drop === "number" ? data.drop : 0.02,
    floor: typeof data.floor === "number" ? data.floor : 0.6,
    refuse: typeof data.refuse === "number" ? data.refuse : null,
    text: t,
    sel: 0,
    done: false,
    sending: false,
  };

  document.getElementById("bl-title").innerText = t.title || "";
  document.getElementById("bl-name").innerText = data.name || "";
  document.getElementById("bl-trust-label").innerText = t.trust || "";
  document.getElementById("bl-appetite-label").innerText = t.appetite || "";
  document.getElementById("bl-appetite").style.display = t.appetite ? "" : "none";
  const refuseTick = document.getElementById("bl-trust-refuse");
  refuseTick.style.display = ledger.refuse !== null ? "" : "none";
  if (ledger.refuse !== null) refuseTick.style.left = Math.max(0, Math.min(100, ledger.refuse)) + "%";
  ledgerTrust(data.trust);

  const rumour = document.getElementById("bl-rumour");
  document.getElementById("bl-rumour-text").innerText = data.rumour || "";
  rumour.style.display = data.rumour ? "" : "none";
  document.getElementById("bl-total-label").innerText = t.total || "";
  document.getElementById("bl-sell-text").innerText = t.sell || "";
  document.getElementById("bl-stamp").innerText = t.sealed || "";

  /* the keys along the foot, or the old one-line note if none were sent */
  const keys = t.keys || null;
  const keysEl = document.getElementById("bl-keys");
  keysEl.innerHTML = "";
  if (keys) {
    [
      ["↑ ↓", keys.Select],
      ["← →", keys.Amount],
      [(keys.Shift || "Shift") + " →", keys.All],
      [keys.Enter || "Enter", keys.Sell],
      [keys.Esc || "Esc", keys.Leave],
    ].forEach(([key, label]) => {
      if (!label) return;
      const k = cgEl("span", "bl-key", keysEl);
      cgEl("kbd", "", k).innerText = key;
      cgEl("span", "", k).innerText = label;
    });
  }
  keysEl.style.display = keys ? "" : "none";
  const close = document.getElementById("bl-close");
  close.innerText = t.close || "";
  close.style.display = keys ? "none" : "";

  const rowsEl = document.getElementById("bl-rows");
  rowsEl.innerHTML = "";
  ledger.rows.forEach((row, index) => {
    const el = cgEl("div", "bl-row", rowsEl);
    el.style.animationDelay = Math.min(index, 10) * 45 + "ms";
    row.el = el;

    const tags = (row.tags || []).filter((tag) => tag);
    const kinds = tags.map(ledgerTagClass);
    const icon = cgEl("div", "bl-icon", el);
    icon.innerHTML = LEDGER_BOTTLE;
    icon.classList.add(kinds.includes("bad") ? "bad" : kinds.includes("gold") ? "gold" : "plain");
    cgEl("span", "bl-count", icon).innerText = "×" + row.count;

    const info = cgEl("div", "bl-info", el);
    cgEl("div", "bl-label", info).innerText = row.label;
    const tagsEl = cgEl("div", "bl-tags", info);
    tags.forEach((tag, i) => {
      cgEl("span", "bl-tag " + kinds[i], tagsEl).innerText = tag;
    });

    const price = cgEl("div", "bl-price", el);
    ledgerCash(cgEl("div", "bl-cash", price), row.unit);
    cgEl("div", "bl-each", price).innerText = t.each || "";

    const step = cgEl("div", "bl-step", el);
    const minus = cgEl("button", "bl-btn bl-minus", step);
    minus.type = "button";
    minus.innerText = "−";
    cgEl("span", "bl-qty", step).innerText = "0";
    const plus = cgEl("button", "bl-btn bl-plus", step);
    plus.type = "button";
    plus.innerText = "+";
    const all = cgEl("button", "bl-btn bl-all", step);
    all.type = "button";
    all.innerText = t.all || "≫";

    const sub = cgEl("div", "bl-sub", el);
    cgEl("span", "bl-sub-n", sub);
    cgEl("s", "bl-sub-full", sub);
    cgEl("span", "bl-sub-sum", sub);

    minus.addEventListener("click", () => ledgerSetQty(row, (ledger.qty[row.id] || 0) - 1));
    plus.addEventListener("click", () => ledgerSetQty(row, (ledger.qty[row.id] || 0) + 1));
    all.addEventListener("click", () =>
      ledgerSetQty(row, (ledger.qty[row.id] || 0) >= row.count ? 0 : row.count));
    el.addEventListener("mouseenter", () => ledgerSelect(index, false));
    /* the wheel over the stepper turns the amount; elsewhere it scrolls the list */
    step.addEventListener("wheel", (e) => {
      e.preventDefault();
      ledgerSetQty(row, (ledger.qty[row.id] || 0) + (e.deltaY < 0 ? 1 : -1));
    }, { passive: false });
  });

  const root = document.getElementById("buyer-ledger");
  root.classList.remove("done", "sending");
  document.getElementById("bl-coins").innerHTML = "";
  ledgerHoldCancel();
  ledgerRoll.shown = 0;
  ledgerCash(document.getElementById("bl-total"), 0);
  replay(root, "show");
  ledgerSelect(0, false);
  ledgerRender();
}

function hideLedger() {
  ledgerHoldCancel();
  ledger = null;
  document.getElementById("buyer-ledger").classList.remove("show", "done", "sending");
}

/* a scatter of coins off the total */
function ledgerCoins() {
  const box = document.getElementById("bl-coins");
  box.innerHTML = "";
  for (let i = 0; i < 14; i++) {
    const coin = cgEl("i", "", box);
    const angle = -Math.PI / 2 + (Math.random() - 0.5) * Math.PI * 0.9;
    const dist = 60 + Math.random() * 90;
    coin.style.setProperty("--dx", Math.cos(angle) * dist + "px");
    coin.style.setProperty("--dy", Math.sin(angle) * dist + "px");
    coin.style.setProperty("--spin", (Math.random() * 720 - 360) + "deg");
    coin.style.animationDelay = Math.random() * 120 + "ms";
  }
}

function ledgerDone(data) {
  const root = document.getElementById("buyer-ledger");
  if (ledger) ledger.done = true;
  ledgerHoldCancel();
  if (data && typeof data.total === "number") ledgerRollTo(data.total);
  if (data && typeof data.trust === "number") ledgerTrust(data.trust);
  root.classList.add("done");
  ledgerCoins();
}

/* ---- Shake On It: held, not clicked ---- */
let ledgerHold = { start: 0, raf: 0, on: false, timer: 0 };

function ledgerHoldStart() {
  const sell = document.getElementById("bl-sell");
  if (!ledger || ledger.done || ledger.sending || sell.disabled || ledgerHold.on) return;
  ledgerHold.on = true;
  ledgerHold.start = performance.now();
  sell.classList.add("holding");
  const fill = document.getElementById("bl-sell-fill");
  const tick = (now) => {
    if (!ledgerHold.on) return;
    fill.style.width = Math.min(1, (now - ledgerHold.start) / LEDGER_HOLD_MS) * 100 + "%";
    ledgerHold.raf = requestAnimationFrame(tick);
  };
  ledgerHold.raf = requestAnimationFrame(tick);
  /* the timer decides, the frames only draw the fill */
  ledgerHold.timer = setTimeout(() => {
    if (!ledgerHold.on) return;
    ledgerHold.on = false;
    cancelAnimationFrame(ledgerHold.raf);
    fill.style.width = "100%";
    sell.classList.remove("holding");
    buyerSell();
  }, LEDGER_HOLD_MS);
}

function ledgerHoldCancel() {
  cancelAnimationFrame(ledgerHold.raf);
  clearTimeout(ledgerHold.timer);
  ledgerHold.on = false;
  const sell = document.getElementById("bl-sell");
  if (sell) sell.classList.remove("holding");
  const fill = document.getElementById("bl-sell-fill");
  if (fill && !(ledger && ledger.sending)) fill.style.width = "0%";
}

/* written out per callback so the code map can pair both ends */
function buyerSell() {
  if (!ledger) return;
  const lines = ledger.rows
    .filter((row) => (ledger.qty[row.id] || 0) > 0)
    .map((row) => ({ id: row.id, qty: ledger.qty[row.id] }));
  if (lines.length === 0) return;
  ledger.sending = true;
  document.getElementById("bl-sell").disabled = true;
  document.getElementById("buyer-ledger").classList.add("sending");
  fetch(`https://${GetParentResourceName()}/buyerSell`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({ buyer: ledger.buyer, lines }),
  });
}

function buyerCancel() {
  hideLedger();
  fetch(`https://${GetParentResourceName()}/buyerCancel`, {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=UTF-8" },
    body: JSON.stringify({}),
  });
}

(function wireLedger() {
  const sell = document.getElementById("bl-sell");
  sell.addEventListener("mousedown", (e) => { if (e.button === 0) ledgerHoldStart(); });
  sell.addEventListener("mouseup", ledgerHoldCancel);
  sell.addEventListener("mouseleave", ledgerHoldCancel);
  document.getElementById("bl-all-in").addEventListener("click", ledgerOfferAll);

  /* Esc is handled with the other UIs in document.onkeyup */
  window.addEventListener("keydown", (e) => {
    if (!ledger || ledger.done) return;
    const row = ledger.rows[ledger.sel];
    const q = row ? ledger.qty[row.id] || 0 : 0;

    if (e.key === "ArrowUp") ledgerSelect(ledger.sel - 1, true);
    else if (e.key === "ArrowDown") ledgerSelect(ledger.sel + 1, true);
    else if (e.key === "ArrowLeft" && row) ledgerSetQty(row, e.shiftKey ? 0 : q - 1);
    else if (e.key === "ArrowRight" && row) ledgerSetQty(row, e.shiftKey ? row.count : q + 1);
    else if ((e.key === "Backspace" || e.key === "Delete") && row) ledgerSetQty(row, 0);
    else if (e.key === "Enter") { if (!e.repeat) ledgerHoldStart(); }
    else return;
    e.preventDefault();
  });
  window.addEventListener("keyup", (e) => {
    if (e.key === "Enter" && ledger) ledgerHoldCancel();
  });
})();

/* ------------------------------------------------------------------ */
/*  Hold The Heat: "The Firebox" (Config.HeatSkill.Game.Panel)         */
/*                                                                     */
/*  Lua opens it (pushPanel open), feeds it the server's reading once  */
/*  a second (update), steps it aside for an incident's minigame       */
/*  (suspend / resume) and closes it (open = false). The player drags  */
/*  a split into the fire (pushStoke), holds the valve (pushTap),      */
/*  pulls the lever (pushVent), clicks the trouble tag (pushTrouble),  */
/*  Esc steps back (pushPanelClose). The server owns every number:     */
/*  this only draws them, eased between its one-second readings.       */
/* ------------------------------------------------------------------ */
const PP_MIN = 40;          /* the dial's cold end */
const PP_CX = 160, PP_CY = 170, PP_R = 140;
let pp = null;

/* written out per callback (not one helper with the name in a variable) so the code map can pair both ends */
function ppStokePost() {
  fetch(`https://${GetParentResourceName()}/pushStoke`, {
    method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: "{}",
  });
}
function ppTapPost(open) {
  fetch(`https://${GetParentResourceName()}/pushTap`, {
    method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: JSON.stringify({ open: !!open }),
  });
}
function ppVentPost() {
  fetch(`https://${GetParentResourceName()}/pushVent`, {
    method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: "{}",
  });
}
function ppTroublePost() {
  fetch(`https://${GetParentResourceName()}/pushTrouble`, {
    method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: "{}",
  });
}
function ppClosePost() {
  fetch(`https://${GetParentResourceName()}/pushPanelClose`, {
    method: "POST", headers: { "Content-Type": "application/json; charset=UTF-8" }, body: "{}",
  });
}

/* ---- the dial: heat → a point on the arc (40 at the left, max at the right) ---- */
function ppPoint(heat, r) {
  const span = Math.max(1, pp.max - PP_MIN);
  const f = Math.max(0, Math.min(1, (heat - PP_MIN) / span));
  const a = Math.PI * (1 - f);
  return { x: PP_CX + r * Math.cos(a), y: PP_CY - r * Math.sin(a) };
}
function ppArc(h1, h2, r) {
  const a = ppPoint(h1, r), b = ppPoint(h2, r);
  return `M${a.x.toFixed(1)} ${a.y.toFixed(1)} A${r} ${r} 0 0 1 ${b.x.toFixed(1)} ${b.y.toFixed(1)}`;
}
function ppBuildDial() {
  document.getElementById("pp-track").setAttribute("d", ppArc(PP_MIN, pp.max, PP_R));
  document.getElementById("pp-red").setAttribute("d", ppArc(Math.min(pp.max, 100), pp.max, PP_R));
  const ticks = document.getElementById("pp-ticks");
  ticks.innerHTML = "";
  for (let h = PP_MIN; h <= pp.max + 0.01; h += 5) {
    const big = h % 20 === 0;
    const a = ppPoint(h, PP_R - 10), b = ppPoint(h, PP_R + (big ? 9 : 4));
    const line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", a.x); line.setAttribute("y1", a.y); line.setAttribute("x2", b.x); line.setAttribute("y2", b.y);
    if (big) line.setAttribute("class", "big");
    ticks.appendChild(line);
    if (big) {
      const p = ppPoint(h, PP_R + 21);
      const label = document.createElementNS("http://www.w3.org/2000/svg", "text");
      label.setAttribute("x", p.x); label.setAttribute("y", p.y + 4); label.textContent = h;
      ticks.appendChild(label);
    }
  }
}

/* ---- sounds, made here (no files): a crackle, the hiss of the tap, the lever's clank ---- */
function ppAudio(volume) {
  let ctx = null;
  try { ctx = new (window.AudioContext || window.webkitAudioContext)(); } catch (e) { return null; }
  const master = ctx.createGain();
  master.gain.value = volume;
  master.connect(ctx.destination);
  const noise = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const ch = noise.getChannelData(0);
  for (let i = 0; i < ch.length; i++) ch[i] = Math.random() * 2 - 1;
  const burst = (t, len, freq, gain) => {
    const src = ctx.createBufferSource(); src.buffer = noise;
    const f = ctx.createBiquadFilter(); f.type = "bandpass"; f.frequency.value = freq; f.Q.value = 1.2;
    const g = ctx.createGain(); g.gain.setValueAtTime(gain, t); g.gain.exponentialRampToValueAtTime(0.001, t + len);
    src.connect(f); f.connect(g); g.connect(master); src.start(t, Math.random() * 0.5, len + 0.05);
  };
  let hiss = null;
  return {
    crackle() {
      const t = ctx.currentTime;
      for (let i = 0; i < 7; i++) burst(t + i * 0.05 + Math.random() * 0.04, 0.05 + Math.random() * 0.06, 1400 + Math.random() * 2600, 0.5);
      burst(t, 0.5, 300, 0.35);
    },
    hiss(on) {
      if (on && !hiss) {
        const src = ctx.createBufferSource(); src.buffer = noise; src.loop = true;
        const f = ctx.createBiquadFilter(); f.type = "highpass"; f.frequency.value = 2600;
        const g = ctx.createGain(); g.gain.setValueAtTime(0.0001, ctx.currentTime);
        g.gain.exponentialRampToValueAtTime(0.25, ctx.currentTime + 0.15);
        src.connect(f); f.connect(g); g.connect(master); src.start();
        hiss = { src, g };
      } else if (!on && hiss) {
        const h = hiss; hiss = null;
        h.g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.2);
        setTimeout(() => { try { h.src.stop(); } catch (e) { /* gone */ } }, 260);
      }
    },
    clank() {
      const t = ctx.currentTime;
      [180, 271].forEach((freq, i) => {
        const o = ctx.createOscillator(); o.type = "triangle"; o.frequency.value = freq;
        const g = ctx.createGain(); g.gain.setValueAtTime(0.35 / (i + 1), t); g.gain.exponentialRampToValueAtTime(0.001, t + 0.4);
        o.connect(g); g.connect(master); o.start(t); o.stop(t + 0.45);
      });
      burst(t + 0.05, 0.6, 3200, 0.3);
    },
    close() { try { if (hiss) hiss.src.stop(); ctx.close(); } catch (e) { /* closed */ } },
  };
}

/* ---- opening, readings, closing ---- */
function pushPanelMessage(data) {
  const root = document.getElementById("push-panel");
  if (data.open === true) {
    if (pp) ppTeardown();
    const t = data.text || {};
    pp = {
      text: t, warnText: data.warnText || {}, grades: data.grades || [40, 60, 82],
      max: data.maxHeat || 105, cooldown: (data.cooldown || 1) * 1000, stokeMs: (data.stokeSeconds || 3) * 1000,
      canFuel: data.canFuel !== false, canCool: data.canCool !== false, canVent: !!data.canVent,
      read: {}, heat: null, readyAt: 0, tap: false, valveAngle: 0, boosts: [], parts: [], smoke: [], drag: null,
      last: performance.now(), audio: data.sound ? ppAudio(Math.max(0, Math.min(1, typeof data.volume === "number" ? data.volume : 0.5))) : null,
    };
    const set = (id, v) => { const el = document.getElementById(id); if (el && v) el.textContent = v; };
    set("pp-title", (t.Title || "Hold The Heat").toUpperCase());
    set("pp-heat-cap", t.Heat); set("pp-rack-cap", t.Rack); set("pp-fire-cap", t.Firebox);
    set("pp-barrel-cap", t.Barrel); set("pp-press-cap", t.Pressure); set("pp-lever-label", t.Lever);
    set("pp-keys", t.Keys);
    document.getElementById("pp-lever").classList.toggle("off", !pp.canVent);
    ppBuildDial();
    ppApply(data.reading || {});
    root.className = "open";
    pp.raf = requestAnimationFrame(ppLoop);
    return;
  }
  if (!pp) return;
  if (data.open === false) {
    ppTeardown();
    root.className = "";
  } else if (data.suspend) {
    ppSetTap(false, true);
    ppDrop(false);
    root.className = "";
    cancelAnimationFrame(pp.raf);
    pp.raf = null;
  } else if (data.resume) {
    root.className = "open";
    if (data.reading) ppApply(data.reading);
    if (!pp.raf) { pp.last = performance.now(); pp.raf = requestAnimationFrame(ppLoop); }
  } else if (data.update && data.reading) {
    ppApply(data.reading);
  }
}

function ppTeardown() {
  if (!pp) return;
  cancelAnimationFrame(pp.raf);
  if (pp.audio) pp.audio.close();
  ppDrop(false);
  pp = null;
}

function ppApply(r) {
  pp.read = r;
  if (pp.heat === null) pp.heat = r.heat || 0;
  const t = pp.text;
  const g = r.game || {};

  /* the run: quality, stars, time left */
  const score = typeof r.score === "number" ? Math.floor(r.score) : null;
  document.getElementById("pp-score").textContent = (t.Quality || "QUALITY") + " " + (score === null ? "--" : score + "%");
  const stars = score === null ? 0 : pp.grades.filter((cut) => score >= cut).length;
  document.getElementById("pp-stars").innerHTML = [0, 1, 2].map((i) =>
    `<span class="${i < stars ? "on" : ""}">★</span>`).join("");
  document.getElementById("pp-stars").title = stars ? (t.Grades || [])[stars - 1] || "" : "";
  document.getElementById("pp-timer").textContent = typeof r.pushLeft === "number" ? Math.ceil(r.pushLeft) + "s" : "--";

  /* the band and the mark */
  const band = document.getElementById("pp-band");
  const mark = document.getElementById("pp-mark");
  if (typeof r.target === "number") {
    const half = r.band || 5;
    band.setAttribute("d", ppArc(r.target - half, r.target + half, PP_R));
    const p = ppPoint(r.target, PP_R + 13);
    mark.setAttribute("transform", `translate(${p.x.toFixed(1)} ${p.y.toFixed(1)})`);
    band.style.display = mark.style.display = "";
  } else {
    band.style.display = mark.style.display = "none";
  }

  /* the rack: a log drawn per split (up to 12), or why there is none */
  const rack = document.getElementById("pp-rack");
  const splits = typeof g.splits === "number" ? g.splits : null;
  const pile = document.getElementById("pp-splits");
  const want = splits === null ? 0 : Math.min(12, splits);
  while (pile.children.length > want) pile.lastChild.remove();
  while (pile.children.length < want) {
    const log = document.createElement("div");
    log.className = "pp-split";
    log.style.setProperty("--tilt", (Math.random() * 6 - 3).toFixed(1) + "deg");
    pile.appendChild(log);
  }
  rack.classList.toggle("empty", splits === null || splits <= 0 || !pp.canFuel);
  document.getElementById("pp-rack-note").textContent = splits === null ? t.NoRack || ""
    : splits <= 0 ? t.RackEmpty || "" : (t.Splits || "%d").replace("%d", splits) + " · " + (t.Drag || "");

  /* the water barrel */
  const barrel = document.getElementById("pp-barrel");
  const water = typeof g.water === "number" ? g.water : null;
  const full = Math.max(1, g.waterMax || 1);
  document.getElementById("pp-water").style.height = (water === null ? 0 : Math.max(0, Math.min(100, (water / full) * 100))) + "%";
  barrel.classList.toggle("empty", water === null || water <= 0 || !pp.canCool);
  document.getElementById("pp-barrel-note").textContent = water === null ? t.NoBarrel || ""
    : water <= 0 ? t.BarrelDry || "" : (t.Litres || "%d L").replace("%d", Math.floor(water)) + " · " + (t.Valve || "");
  if ((water === null || water <= 0) && pp.tap) ppSetTap(false);

  /* the fire */
  document.getElementById("pp-firebox").classList.toggle("out", !r.fireLit);
  document.getElementById("pp-fire-note").textContent = r.fireLit ? "" : t.FireOut || "";

  /* the warning, three seconds ahead */
  const warn = g.warn || null;
  const warnEl = document.getElementById("pp-warn");
  warnEl.textContent = warn ? pp.warnText[warn] || "" : "";
  warnEl.className = "pp-warn" + (warn ? " " + warn : "");
  document.getElementById("push-panel").dataset.warn = warn || "";

  /* pressure and the lever */
  const press = typeof r.pressure === "number" ? r.pressure : null;
  const pfill = document.getElementById("pp-pfill");
  pfill.style.width = (press === null ? 0 : Math.max(0, Math.min(100, press))) + "%";
  pfill.classList.toggle("hot", press !== null && press >= (r.pressureWarn || 70));
  document.getElementById("pp-pwarn").style.left = Math.max(0, Math.min(100, r.pressureWarn || 70)) + "%";

  /* trouble at the still */
  const trouble = document.getElementById("pp-trouble");
  if (r.incident) {
    trouble.textContent = (t.Trouble || "TROUBLE: %s").replace("%s", r.incident.label || "")
      + (typeof r.incident.left === "number" ? "  " + Math.ceil(r.incident.left) + "s" : "");
    trouble.classList.add("show");
  } else {
    trouble.classList.remove("show");
  }
}

/* ---- the actions ---- */
function ppStoke(fromX, fromY) {
  if (!pp || !pp.canFuel || document.getElementById("pp-rack").classList.contains("empty")) return false;
  const now = performance.now();
  if (now < pp.readyAt) return false;
  pp.readyAt = now + pp.cooldown;
  ppStokePost();
  pp.boosts.push({ from: now + 450, to: now + 450 + pp.stokeMs });
  if (pp.audio) setTimeout(() => pp && pp.audio && pp.audio.crackle(), 380);

  /* the split flies into the mouth */
  const mouth = document.getElementById("pp-mouth").getBoundingClientRect();
  const fly = document.createElement("div");
  fly.className = "pp-split pp-fly";
  const rack = document.getElementById("pp-splits").getBoundingClientRect();
  fly.style.left = (typeof fromX === "number" ? fromX : rack.left + rack.width / 2) + "px";
  fly.style.top = (typeof fromY === "number" ? fromY : rack.top + rack.height / 2) + "px";
  document.getElementById("push-panel").appendChild(fly);
  requestAnimationFrame(() => {
    fly.style.left = mouth.left + mouth.width / 2 + "px";
    fly.style.top = mouth.top + mouth.height * 0.72 + "px";
    fly.style.transform = "translate(-50%, -50%) rotate(200deg) scale(0.6)";
    fly.style.opacity = "0";
  });
  setTimeout(() => fly.remove(), 520);
  document.getElementById("pp-rack").classList.add("cooling");
  setTimeout(() => { const el = document.getElementById("pp-rack"); if (el) el.classList.remove("cooling"); }, pp.cooldown);
  return true;
}

function ppSetTap(open, quiet) {
  if (!pp) return;
  if (open && (!pp.canCool || document.getElementById("pp-barrel").classList.contains("empty"))) open = false;
  if (pp.tap === open) return;
  pp.tap = open;
  document.getElementById("pp-barrel").classList.toggle("tap", open);
  if (!quiet) ppTapPost(open);
  if (pp.audio) pp.audio.hiss(open);
}

function ppVent() {
  if (!pp || !pp.canVent) return;
  const lever = document.getElementById("pp-lever");
  if (lever.classList.contains("pulled")) return;
  lever.classList.add("pulled");
  setTimeout(() => lever.classList.remove("pulled"), 650);
  ppVentPost();
  if (pp.audio) pp.audio.clank();
  for (let i = 0; i < 26; i++) {
    pp.smoke.push({ x: 150 + (Math.random() - 0.5) * 60, y: 30, vx: (Math.random() - 0.5) * 50, vy: -30 - Math.random() * 40,
      age: 0, life: 1 + Math.random() * 0.6, size: 10 + Math.random() * 14, steam: true });
  }
}

/* ---- dragging a split ---- */
function ppDrop(stoke, x, y) {
  if (!pp || !pp.drag) return;
  const ghost = document.getElementById("pp-ghost");
  ghost.classList.remove("show");
  document.getElementById("pp-mouth").classList.remove("hover");
  pp.drag = null;
  if (stoke) ppStoke(x, y);
}

document.addEventListener("mousedown", (e) => {
  if (!pp || document.getElementById("push-panel").className !== "open") return;
  if (e.target.closest(".pp-splits .pp-split")) {
    if (document.getElementById("pp-rack").classList.contains("empty") || performance.now() < pp.readyAt) return;
    e.preventDefault();
    pp.drag = true;
    const ghost = document.getElementById("pp-ghost");
    ghost.style.left = e.clientX + "px";
    ghost.style.top = e.clientY + "px";
    ghost.classList.add("show");
  } else if (e.target.closest("#pp-valve")) {
    e.preventDefault();
    ppSetTap(true);
  } else if (e.target.closest("#pp-lever")) {
    ppVent();
  } else if (e.target.closest("#pp-trouble.show")) {
    ppTroublePost();
  }
});

document.addEventListener("mousemove", (e) => {
  if (!pp || !pp.drag) return;
  const ghost = document.getElementById("pp-ghost");
  ghost.style.left = e.clientX + "px";
  ghost.style.top = e.clientY + "px";
  const m = document.getElementById("pp-mouth").getBoundingClientRect();
  const over = e.clientX >= m.left && e.clientX <= m.right && e.clientY >= m.top && e.clientY <= m.bottom;
  document.getElementById("pp-mouth").classList.toggle("hover", over);
});

document.addEventListener("mouseup", (e) => {
  if (!pp) return;
  if (pp.drag) {
    const m = document.getElementById("pp-mouth").getBoundingClientRect();
    const over = e.clientX >= m.left && e.clientX <= m.right && e.clientY >= m.top && e.clientY <= m.bottom;
    ppDrop(over, e.clientX, e.clientY);
  }
  if (pp && pp.tap && !pp.keyTap) ppSetTap(false);
});

window.addEventListener("keydown", (e) => {
  if (!pp || document.getElementById("push-panel").className !== "open") return;
  if (e.code === "Space") { e.preventDefault(); if (!e.repeat) ppStoke(); }
  else if (e.code === "KeyS" && !e.repeat) { pp.keyTap = true; ppSetTap(true); }
  else if (e.code === "KeyV" && !e.repeat) ppVent();
  else if (e.code === "KeyT" && !e.repeat && pp.read.incident) ppTroublePost();
  else if (e.key === "Escape") { ppSetTap(false); ppClosePost(); }
});

window.addEventListener("keyup", (e) => {
  if (!pp) return;
  if (e.code === "KeyS") { pp.keyTap = false; ppSetTap(false); }
});

/* ---- every frame: the needle eases, the fire burns ---- */
function ppLoop(now) {
  if (!pp) return;
  const dt = Math.min(0.05, (now - pp.last) / 1000);
  pp.last = now;
  const r = pp.read;

  /* the needle slides to the latest reading over about a second (the server ticks once a second) */
  const target = r.heat || 0;
  pp.heat += (target - pp.heat) * Math.min(1, dt * 2.6);
  const tip = ppPoint(pp.heat, PP_R - 18);
  const needle = document.getElementById("pp-needle");
  needle.setAttribute("x2", tip.x.toFixed(1));
  needle.setAttribute("y2", tip.y.toFixed(1));
  const half = r.band || 5;
  const zone = typeof r.target !== "number" ? "" : Math.abs(pp.heat - r.target) <= half ? "in" : pp.heat > r.target ? "over" : "under";
  const heatEl = document.getElementById("pp-heat");
  heatEl.dataset.zone = zone;
  document.getElementById("pp-heat-val").textContent = Math.floor(pp.heat);
  document.getElementById("pp-dial").classList.toggle("critical", pp.heat >= pp.max * 0.93);

  /* the valve turns while it is open */
  if (pp.tap) pp.valveAngle = (pp.valveAngle + dt * 260) % 360;
  document.getElementById("pp-valve").style.transform = `rotate(${pp.valveAngle.toFixed(1)}deg)`;

  ppDrawFire(dt, now);
  pp.raf = requestAnimationFrame(ppLoop);
}

const PP_MAX_PARTS = 240, PP_MAX_SMOKE = 70, PP_FIRE_MS = 33;
let ppSprites = null;

function ppMakeSprite(r, g, b, alpha) {
  const c = document.createElement("canvas");
  c.width = c.height = 64;
  const x = c.getContext("2d");
  const grad = x.createRadialGradient(32, 32, 0, 32, 32, 32);
  grad.addColorStop(0, `rgba(${r},${g},${b},${alpha})`);
  grad.addColorStop(1, `rgba(${r},${g},${b},0)`);
  x.fillStyle = grad;
  x.fillRect(0, 0, 64, 64);
  return c;
}

function ppSpritesReady() {
  if (ppSprites) return ppSprites;
  /* young to old: white-yellow, yellow, orange, deep orange, red */
  const flame = [[255, 225, 130], [255, 190, 80], [255, 140, 40], [240, 95, 25], [200, 55, 15]]
    .map(([r, g, b]) => ppMakeSprite(r, g, b, 0.9));
  ppSprites = { flame, smoke: ppMakeSprite(18, 14, 12, 0.85), steam: ppMakeSprite(235, 235, 230, 0.6) };
  return ppSprites;
}

function ppDrawFire(dt, now) {
  pp.fireAcc = (pp.fireAcc || 0) + dt;
  if (now - (pp.fireDrawn || 0) < PP_FIRE_MS) return;
  pp.fireDrawn = now;
  dt = Math.min(0.1, pp.fireAcc);
  pp.fireAcc = 0;

  const canvas = document.getElementById("pp-fire");
  const ctx = canvas.getContext("2d");
  const W = canvas.width, H = canvas.height;
  const sp = ppSpritesReady();
  const r = pp.read;
  const warn = (r.game || {}).warn;
  const lit = !!r.fireLit;

  /* how big the fire is: the heat, plus a stoke landing */
  let power = lit ? Math.max(0.12, Math.min(1, (pp.heat - PP_MIN) / Math.max(1, pp.max - PP_MIN))) : 0;
  pp.boosts = pp.boosts.filter((b) => now < b.to);
  for (const b of pp.boosts) if (now >= b.from) power += 0.35 * (1 - (now - b.from) / (b.to - b.from));
  if (warn === "flare") power += 0.15 + Math.sin(now / 70) * 0.08;
  power = Math.max(0, Math.min(1.4, power));
  const lean = warn === "draught" ? 70 : 0;

  /* new flame tongues and sparks (about 220 a second at full fire) */
  pp.emitAcc = (pp.emitAcc || 0) + (lit ? power * 220 * dt : 0);
  while (pp.emitAcc >= 1 && pp.parts.length < PP_MAX_PARTS) {
    pp.emitAcc -= 1;
    const spread = 40 + power * 70;
    pp.parts.push({ x: W / 2 + (Math.random() - 0.5) * spread * 2, y: H - 14, vx: (Math.random() - 0.5) * 18 + lean * 0.4,
      vy: -(50 + Math.random() * 90 * (0.6 + power)), age: 0, life: 0.45 + Math.random() * 0.55 * (0.6 + power),
      size: 10 + Math.random() * 16 * (0.5 + power), spark: Math.random() < 0.06 });
  }
  if (pp.emitAcc > 1) pp.emitAcc = 1;
  if (warn === "flare" && pp.smoke.length < PP_MAX_SMOKE && Math.random() < dt * 22) {
    pp.smoke.push({ x: W / 2 + (Math.random() - 0.5) * 80, y: H * 0.45, vx: (Math.random() - 0.5) * 20, vy: -25 - Math.random() * 25,
      age: 0, life: 1.6 + Math.random(), size: 16 + Math.random() * 18 });
  }

  ctx.clearRect(0, 0, W, H);
  ctx.globalAlpha = 1;

  /* the glow of the bed of coals */
  const glow = ctx.createRadialGradient(W / 2, H - 6, 4, W / 2, H - 6, 150);
  glow.addColorStop(0, `rgba(255,120,30,${0.25 + power * 0.45})`);
  glow.addColorStop(1, "rgba(255,80,20,0)");
  ctx.fillStyle = glow;
  ctx.fillRect(0, 0, W, H);
  ctx.fillStyle = lit ? `rgba(255,${Math.round(110 + power * 60)},40,${0.55 + power * 0.3})` : "rgba(120,40,20,0.5)";
  ctx.beginPath();
  for (let i = 0; i < 9; i++) {
    const x = 40 + i * 27 + Math.sin(now / 300 + i) * 2;
    ctx.moveTo(x + 14, H - 8);
    ctx.ellipse(x, H - 8, 14, 6, 0, 0, Math.PI * 2);
  }
  ctx.fill();

  /* the flames: one sprite per particle, its colour by its age */
  ctx.globalCompositeOperation = "lighter";
  const keep = [];
  for (const p of pp.parts) {
    p.age += dt;
    if (p.age >= p.life) continue;
    p.vx += lean * dt * 1.6;
    p.x += p.vx * dt; p.y += p.vy * dt;
    const k = p.age / p.life;
    if (p.spark) {
      ctx.globalAlpha = 1 - k;
      ctx.fillStyle = "rgb(255,220,140)";
      ctx.fillRect(p.x, p.y, 2, 2);
    } else {
      const size = p.size * (1 - k * 0.7);
      ctx.globalAlpha = 0.6 * (1 - k);
      ctx.drawImage(sp.flame[Math.min(4, Math.floor(k * 5))], p.x - size, p.y - size, size * 2, size * 2);
    }
    keep.push(p);
  }
  pp.parts = keep;
  ctx.globalCompositeOperation = "source-over";

  /* smoke (a flare coming) and steam (the vent) */
  const keepSmoke = [];
  for (const s of pp.smoke) {
    s.age += dt;
    if (s.age >= s.life) continue;
    s.x += (s.vx + lean * 0.5) * dt; s.y += s.vy * dt;
    const k = s.age / s.life;
    const size = s.size * (1 + k * 1.6);
    ctx.globalAlpha = (s.steam ? 0.55 : 0.65) * (1 - k);
    ctx.drawImage(s.steam ? sp.steam : sp.smoke, s.x - size, s.y - size, size * 2, size * 2);
    keepSmoke.push(s);
  }
  pp.smoke = keepSmoke;
  ctx.globalAlpha = 1;
}

/* ================= Settings panel (GSC.AdminPanel) ================= */
/* The server builds each file's tree and checks every save; this only edits and sends paths + values. */
(() => {
  const panel = document.getElementById("cfg-panel");
  if (!panel) return;
  const $ = (id) => document.getElementById(id);
  const post = (name, body) =>
    fetch(`https://${GetParentResourceName()}/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=UTF-8" },
      body: JSON.stringify(body || {}),
    }).catch(() => {});

  let T = {};
  let files = [];
  let fileKey = null;
  let fileData = null;
  let isOpen = false;
  let saving = false;
  let escArmed = 0;
  let statusTimer = null;
  const staged = new Map();  // path key -> { path, value } | { path, reset: true }
  const invalid = new Set(); // path keys with text that is not a valid value
  let errors = new Map();    // path key -> message from the server

  const pkey = (path) => JSON.stringify(path);
  const fmt = (s, ...a) => { let i = 0; return String(s || "").replace(/%[ds]/g, () => String(a[i++])); };
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined && text !== null) e.textContent = String(text);
    return e;
  }

  /* hashes (control keys) read better as 0x... */
  const isHash = (n) => Number.isInteger(n) && n >= 0x10000000;
  function showNum(kind, n) {
    if (typeof n !== "number") return "";
    return kind === "int" && isHash(n) ? "0x" + n.toString(16).toUpperCase() : String(n);
  }

  function parseNum(text, kind) {
    const s = String(text).trim();
    if (s === "") return null;
    let n;
    if (/^-?0x[0-9a-f]+$/i.test(s)) n = s.startsWith("-") ? -parseInt(s.slice(1), 16) : parseInt(s, 16);
    else if (/^-?(\d+\.?\d*|\.\d+)(e-?\d+)?$/i.test(s)) n = Number(s);
    else return null;
    if (!Number.isFinite(n)) return null;
    if (kind === "int" && !Number.isInteger(n)) return null;
    return n;
  }

  function showValue(v, kind, item) {
    if (v === undefined || v === null) return "";
    if (kind === "bool") return v ? "true" : "false";
    if (kind === "int" || kind === "float") return showNum(kind, v);
    if (kind === "list") return (v || []).map((x) => showValue(x, item)).join(", ") || "(empty)";
    if (kind === "rows") return fmt(T.Entries || "%d entries", (v || []).length);
    if (kind === "dict") return Object.keys(v || {}).join(", ");
    if (kind && kind.startsWith("vec")) return ["x", "y", "z", "w"].filter((k) => v[k] !== undefined).map((k) => v[k]).join(", ");
    return String(v);
  }

  /* ---------- status line ---------- */
  function setStatus(text, kind, ms) {
    const s = $("cfg-status");
    s.textContent = text || "";
    s.className = kind || "";
    clearTimeout(statusTimer);
    if (ms) statusTimer = setTimeout(() => { s.textContent = ""; s.className = ""; }, ms);
  }

  function updateFoot() {
    const n = staged.size;
    $("cfg-count").textContent = n ? fmt(T.Unsaved || "%d unsaved", n) : "";
    $("cfg-save").disabled = saving || n === 0 || invalid.size > 0;
    $("cfg-discard").disabled = saving || (n === 0 && invalid.size === 0);
  }

  /* ---------- staging ---------- */
  function stage(node, path, row, value) {
    const key = pkey(path);
    invalid.delete(key);
    errors.delete(key);
    if (same(value, node.v)) staged.delete(key);
    else staged.set(key, { path, value });
    row.classList.toggle("dirty", staged.has(key));
    row.classList.remove("invalid");
    row.querySelector(".cfg-err").textContent = "";
    updateFoot();
  }

  function markInvalid(path, row) {
    const key = pkey(path);
    invalid.add(key);
    row.classList.add("invalid");
    updateFoot();
  }

  /* what the editor starts with: a staged value, the file value after a staged reset, or the live value */
  function startValue(node, key) {
    const s = staged.get(key);
    if (!s) return node.v;
    return s.reset ? node.d : s.value;
  }

  /* ---------- editors ---------- */
  function numberInput(kind, value, onValue, onBad) {
    const inp = el("input", "cfg-input");
    inp.type = "text";
    inp.spellcheck = false;
    inp.value = showNum(kind, value);
    inp.addEventListener("input", () => {
      const n = parseNum(inp.value, kind);
      inp.classList.toggle("bad", n === null);
      if (n === null) onBad(); else onValue(n);
    });
    return inp;
  }

  function makeEditor(node, path, row) {
    if (node.t === "rows" || node.t === "dict") return rowsUnit(node, path, row);
    const key = pkey(path);
    return editor(node.t, node.it, startValue(node, key), (v) => stage(node, path, row, v), () => markInvalid(path, row));
  }

  /* one value of any kind: set(v) with each valid value, bad() while the text is not one */
  function editor(kind, it, cur, set, bad) {
    if (kind === "bool") {
      const wrap = el("div", "cfg-ctrl-inner");
      wrap.style.display = "flex"; wrap.style.alignItems = "center"; wrap.style.gap = "10px";
      const lab = el("label", "cfg-switch");
      const inp = el("input"); inp.type = "checkbox"; inp.checked = !!cur;
      const word = el("span", "cfg-bool-word", cur ? "true" : "false");
      inp.addEventListener("change", () => { word.textContent = inp.checked ? "true" : "false"; set(inp.checked); });
      lab.append(inp, el("span", "cfg-slider"));
      wrap.append(lab, word);
      return wrap;
    }

    if (kind === "int" || kind === "float") return numberInput(kind, cur, set, bad);

    if (kind === "str") {
      const inp = el("input", "cfg-input");
      inp.type = "text"; inp.spellcheck = false; inp.maxLength = 256;
      inp.value = cur == null ? "" : String(cur);
      inp.addEventListener("input", () => set(inp.value));
      return inp;
    }

    if (kind === "vec2" || kind === "vec3" || kind === "vec4") {
      const axes = ["x", "y", "z", "w"].slice(0, Number(kind.slice(3)));
      const value = Object.assign({}, cur);
      const wrap = el("div", "cfg-vec");
      const parts = {};
      for (const a of axes) {
        const lab = el("label", null, a);
        const inp = numberInput("float", value[a], () => {}, () => {});
        parts[a] = inp;
        inp.addEventListener("input", () => {
          const out = { __vec: axes.length };
          for (const b of axes) {
            const n = parseNum(parts[b].value, "float");
            if (n === null) return bad();
            out[b] = n;
          }
          set(out);
        });
        lab.append(inp);
        wrap.append(lab);
      }
      return wrap;
    }

    if (kind === "list") {
      const item = it || "str";
      let list = Array.isArray(cur) ? cur.slice() : [];
      const wrap = el("div", "cfg-list");
      const add = el("input", "cfg-input");
      add.type = "text"; add.spellcheck = false; add.placeholder = T.AddItem || "Add...";
      const draw = () => {
        wrap.textContent = "";
        list.forEach((v, i) => {
          const chip = el("span", "cfg-chip", showValue(v, item));
          const x = el("button", null, "✕");
          x.type = "button";
          x.addEventListener("click", () => { list.splice(i, 1); set(list.slice()); draw(); });
          chip.append(x);
          wrap.append(chip);
        });
        wrap.append(add);
      };
      add.addEventListener("keydown", (e) => {
        if (e.key !== "Enter") return;
        e.preventDefault();
        const text = add.value.trim();
        if (text === "") return;
        let v = text;
        if (item === "int" || item === "float") v = parseNum(text, item);
        else if (item === "bool") v = text === "true" ? true : text === "false" ? false : null;
        if (v === null) { add.classList.add("bad"); return; }
        add.classList.remove("bad");
        add.value = "";
        list.push(v);
        set(list.slice());
        draw();
        add.focus();
      });
      draw();
      return wrap;
    }

    return el("span", "cfg-hint", showValue(cur, kind));
  }

  /* ---------- lists of entries: saved whole, so entries can be added, copied, moved and removed ---------- */
  const clone = (v) => JSON.parse(JSON.stringify(v));

  function miniButton(text, title, onClick) {
    const b = el("button", "cfg-btn cfg-btn-ghost cfg-btn-mini", text);
    b.type = "button";
    if (title) b.title = title;
    b.addEventListener("click", onClick);
    return b;
  }

  function entryTitle(entry) {
    if (!entry || typeof entry !== "object" || entry.__vec) return "";
    for (const k of ["name", "label", "title", "id", "key", "item"]) if (typeof entry[k] === "string" && entry[k]) return entry[k];
    return "";
  }

  /* any value inside an entry */
  function fieldEditor(schema, value, set, ctx) {
    if (!schema) return el("span", "cfg-hint", "?");
    if (schema.t === "rows") return rowsEditor(schema, value, ctx);
    if (schema.t === "dict") return dictEditor(schema, value, ctx);
    if (schema.t === "obj") return objEditor(schema, value, ctx);
    const id = ctx.id();
    return editor(schema.t, schema.it, value, (v) => { set(v); ctx.ok(id); }, () => ctx.bad(id));
  }

  function objEditor(schema, value, ctx) {
    const box = el("div", "cfg-fields");
    const order = (schema.o || []).filter((k) => value && value[k] !== undefined);
    for (const k of Object.keys(value || {})) if (!order.includes(k)) order.push(k);
    for (const k of order) {
      const sub = (schema.f || {})[k];
      if (!sub) continue;
      const wide = sub.t === "obj" || sub.t === "rows" || sub.t === "list" || sub.t === "dict";
      const line = el("div", "cfg-field" + (wide ? " cfg-field-wide" : ""));
      const keyEl = el("span", "cfg-field-key", k);
      if (schema.r && schema.r[k]) {
        const b = el("span", "cfg-badge cfg-badge-restart", T.Restart || "RESTART");
        b.title = T.RestartTip || "";
        keyEl.append(" ", b);
      }
      line.append(keyEl);
      line.append(fieldEditor(sub, value[k], (v) => { value[k] = v; }, ctx));
      const hint = schema.h && schema.h[k];
      if (hint) line.append(el("div", "cfg-hint cfg-field-hint", hint));
      box.append(line);
    }
    return box;
  }

  function rowsEditor(schema, list, ctx) {
    const box = el("div", "cfg-rows");
    list.forEach((entry, i) => {
      const card = el("div", "cfg-entry");
      const head = el("div", "cfg-entry-head");
      head.append(el("span", "cfg-entry-num", "#" + (i + 1)));
      const title = entryTitle(entry);
      if (title) head.append(el("span", "cfg-entry-title", title));
      head.append(el("span", "cfg-spacer"));

      const up = miniButton("↑", T.MoveUp || "Move up", () => { [list[i - 1], list[i]] = [list[i], list[i - 1]]; ctx.redraw(); });
      const down = miniButton("↓", T.MoveDown || "Move down", () => { [list[i + 1], list[i]] = [list[i], list[i + 1]]; ctx.redraw(); });
      const dup = miniButton(T.Duplicate || "Duplicate", null, () => { list.splice(i + 1, 0, clone(entry)); ctx.redraw(); });
      const rm = miniButton(T.Remove || "Remove", null, () => { list.splice(i, 1); ctx.redraw(); });
      up.disabled = i === 0;
      down.disabled = i === list.length - 1;
      rm.disabled = list.length <= 1;
      rm.classList.add("cfg-btn-danger");
      head.append(up, down, dup, rm);

      card.append(head, fieldEditor(schema.item, entry, (v) => { list[i] = v; }, ctx));
      box.append(card);
    });
    const add = miniButton(T.AddEntry || "+ Add entry", T.AddEntryTip || "Adds a copy of the last entry", () => {
      list.push(clone(list[list.length - 1]));
      ctx.redraw();
    });
    add.classList.add("cfg-add-entry");
    add.disabled = list.length >= 100;
    box.append(add);
    return box;
  }

  /* named entries (a recipe, a price): add as a copy under a new name; only names the file lacks can go */
  const NAME_RE = /^[A-Za-z_][A-Za-z0-9_]{0,31}$/;

  function dictEditor(schema, map, ctx) {
    const box = el("div", "cfg-rows");
    const fileKeys = new Set(ctx.fileKeys || []);
    const keys = Object.keys(map).sort((a, b) => (fileKeys.has(b) - fileKeys.has(a)) || a.localeCompare(b));
    const leaf = schema.item && schema.item.t !== "obj" && schema.item.t !== "rows" && schema.item.t !== "dict";

    for (const name of keys) {
      const card = el(leaf ? "div" : "details", "cfg-entry cfg-entry-named");
      const head = el(leaf ? "div" : "summary", "cfg-entry-head");
      head.append(el("span", "cfg-entry-num", name));
      const title = entryTitle(map[name]);
      if (title && title !== name) head.append(el("span", "cfg-entry-title", title));
      head.append(el("span", "cfg-spacer"));
      if (leaf) {
        const id = ctx.id();
        head.append(editor(schema.item.t, schema.item.it, map[name], (v) => { map[name] = v; ctx.ok(id); }, () => ctx.bad(id)));
      }
      const rm = miniButton(T.Remove || "Remove", fileKeys.has(name) ? (T.InFile || "In the config file - can't be removed") : null, (e) => {
        e.preventDefault(); e.stopPropagation();
        delete map[name]; ctx.open.delete(name); ctx.redraw();
      });
      rm.disabled = fileKeys.has(name) || keys.length <= 1;
      rm.classList.add("cfg-btn-danger");
      head.append(rm);
      card.append(head);

      if (!leaf) {
        card.open = ctx.open.has(name);
        card.addEventListener("toggle", () => { if (card.open) ctx.open.add(name); else ctx.open.delete(name); });
        card.append(fieldEditor(schema.item, map[name], (v) => { map[name] = v; }, ctx));
      }
      box.append(card);
    }

    /* + a new one: a name, and which one to copy */
    const addRow = el("div", "cfg-add-named");
    const nameInp = el("input", "cfg-input");
    nameInp.type = "text"; nameInp.spellcheck = false; nameInp.maxLength = 32;
    nameInp.placeholder = T.NewName || "new name (letters, numbers, _)";
    const from = el("select", "cfg-input cfg-select");
    for (const name of keys) { const o = el("option", null, (T.CopyOf || "copy of") + " " + name); o.value = name; from.append(o); }
    const msg = el("span", "cfg-err");
    const add = miniButton(T.Add || "Add", null, () => {
      const name = nameInp.value.trim();
      if (!NAME_RE.test(name)) { msg.textContent = T.NameBad || "Letters, numbers and _ only (32 max), not starting with a number."; return; }
      if (Object.prototype.hasOwnProperty.call(map, name)) { msg.textContent = T.NameTaken || "That name is already used."; return; }
      map[name] = clone(map[from.value]);
      ctx.open.add(name);
      ctx.redraw();
    });
    add.disabled = keys.length >= 50;
    nameInp.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); add.click(); } });
    addRow.append(nameInp, from, add, msg);
    box.append(addRow);
    return box;
  }

  function rowsUnit(node, path, row) {
    const key = pkey(path);
    const work = clone(startValue(node, key) || (node.t === "dict" ? {} : []));
    const host = el("div", "cfg-unit");
    const bad = new Set();
    let seq = 0;
    const push = () => {
      if (bad.size) return markInvalid(path, row);
      stage(node, path, row, clone(work));
    };
    const draw = () => {
      host.textContent = "";
      seq = 0;
      host.append(fieldEditor(node.s, work, () => {}, ctx));
    };
    const ctx = {
      fileKeys: node.fk || [],
      open: new Set(),
      id: () => ++seq,
      ok: (id) => { bad.delete(id); push(); },
      bad: (id) => { bad.add(id); markInvalid(path, row); },
      redraw: () => { bad.clear(); push(); draw(); },
    };
    draw();
    return host;
  }

  /* ---------- the tree ---------- */
  const label = (k) => (typeof k === "number" ? "#" + k : String(k));

  function renderLeaf(node, path) {
    const key = pkey(path);
    const row = el("div", "cfg-row" + (node.t === "rows" || node.t === "dict" ? " cfg-row-rows" : ""));
    row.dataset.search = (path.join(".") + " " + (node.h || "")).toLowerCase();

    const head = el("div", "cfg-label");
    head.append(el("span", "cfg-key", label(path[path.length - 1])));
    if (node.r) {
      const b = el("span", "cfg-badge cfg-badge-restart", T.Restart || "RESTART");
      b.title = T.RestartTip || "";
      head.append(b);
    }
    if (node.o) head.append(el("span", "cfg-badge cfg-badge-changed", T.Changed || "Changed in game"));

    const ctrl = el("div", "cfg-ctrl");
    ctrl.append(makeEditor(node, path, row));
    if (node.o) {
      const reset = el("button", "cfg-btn cfg-btn-ghost cfg-btn-mini", "↺");
      reset.type = "button";
      reset.title = T.Reset || "Back to the file value";
      reset.addEventListener("click", () => {
        invalid.delete(key);
        errors.delete(key);
        staged.set(key, { path, reset: true });
        render();
      });
      ctrl.append(reset);
    }
    row.append(head, ctrl);

    if (node.h) row.append(el("div", "cfg-hint", node.h));
    if (node.o) row.append(el("div", "cfg-fileval", fmt(T.FileValue || "File value: %s", showValue(node.d, node.t, node.it))));
    row.append(el("div", "cfg-err", errors.get(key) || ""));

    if (staged.has(key)) row.classList.add("dirty");
    if (invalid.has(key) || errors.has(key)) row.classList.add("invalid");
    return row;
  }

  function renderNode(node, parentPath, depth) {
    const path = parentPath.concat([node.k]);
    if (node.t !== "obj") return renderLeaf(node, path);

    const det = el("details", "cfg-group");
    det.open = depth < 2;
    det.dataset.search = (String(node.k) + " " + (node.h || "")).toLowerCase();
    const sum = el("summary", "cfg-group-head");
    sum.append(el("span", "cfg-key", label(node.k)));
    if (node.h) sum.append(el("span", "cfg-group-hint", node.h));
    det.append(sum);
    for (const c of node.c || []) det.append(renderNode(c, path, depth + 1));
    return det;
  }

  function renderSection(sec) {
    const box = el("section", "cfg-sec");
    box.dataset.search = (sec.k + " " + (sec.title || "") + " " + (sec.h || "")).toLowerCase();
    const head = el("div", "cfg-sec-head");
    head.append(el("span", "cfg-sec-name", sec.title || sec.k), el("span", "cfg-sec-key", "Config." + sec.k));
    box.append(head);
    if (sec.t === "obj") {
      if (sec.h) box.append(el("div", "cfg-hint", sec.h));
      for (const c of sec.c || []) box.append(renderNode(c, [sec.k], 1));
    } else {
      box.append(renderLeaf(sec, [sec.k]));
    }
    return box;
  }

  function render() {
    const main = $("cfg-main");
    const scroll = main.scrollTop;
    main.textContent = "";
    if (!fileData) {
      main.append(el("div", "cfg-empty", T.Loading || "Loading..."));
    } else {
      for (const sec of fileData.sections || []) main.append(renderSection(sec));
      main.append(el("div", "cfg-empty cfg-nomatch", T.NoMatch || "Nothing in this file matches."));
      applySearch();
      main.scrollTop = scroll;
    }
    updateFoot();
  }

  /* ---------- search (this file) ---------- */
  function filter(node, q) {
    if (node.classList.contains("cfg-row")) {
      const hit = !q || node.dataset.search.includes(q);
      node.hidden = !hit;
      return hit;
    }
    const selfHit = !!q && (node.dataset.search || "").includes(q);
    let childHit = false;
    for (const child of node.children) {
      if (child.classList.contains("cfg-row") || child.tagName === "DETAILS") {
        if (filter(child, selfHit ? "" : q)) childHit = true;
      }
    }
    const show = !q || selfHit || childHit;
    node.hidden = !show;
    if (q && show && node.tagName === "DETAILS") node.open = true;
    return show;
  }

  function applySearch() {
    const q = $("cfg-search").value.trim().toLowerCase();
    let any = false;
    for (const sec of $("cfg-main").querySelectorAll(".cfg-sec")) if (filter(sec, q)) any = true;
    const none = $("cfg-main").querySelector(".cfg-nomatch");
    if (none) none.hidden = any || !q;
  }

  /* ---------- files ---------- */
  function drawFiles() {
    const nav = $("cfg-files");
    nav.textContent = "";
    for (const f of files) {
      const b = el("button", "cfg-file" + (f.key === fileKey ? " active" : ""), f.title);
      b.type = "button";
      b.append(el("span", "cfg-file-path", f.path));
      b.addEventListener("click", () => loadFile(f.key));
      nav.append(b);
    }
  }

  function loadFile(key) {
    if (!key) return;
    fileKey = key;
    fileData = null;
    $("cfg-search").value = "";
    drawFiles();
    render();
    post("cfgLoadFile", { file: key });
  }

  /* ---------- open / close / save ---------- */
  function show(d) {
    T = d.text || {};
    files = Array.isArray(d.files) ? d.files : [];
    staged.clear(); invalid.clear(); errors = new Map();
    saving = false; escArmed = 0;
    $("cfg-title").textContent = T.Title || "Kasippu Settings";
    $("cfg-note").textContent = T.Note || "";
    $("cfg-search").placeholder = T.Search || "Search this file...";
    $("cfg-save").textContent = T.Save || "Save changes";
    $("cfg-discard").textContent = T.Discard || "Discard";
    $("cfg-close").title = T.Close || "Close";
    setStatus("");
    isOpen = true;
    panel.classList.add("show");
    loadFile(d.file || (files[0] && files[0].key));
  }

  function hide() {
    if (!isOpen) return;
    isOpen = false;
    panel.classList.remove("show");
    staged.clear(); invalid.clear(); errors = new Map();
    fileData = null;
  }

  function requestClose() {
    if (staged.size > 0 && Date.now() - escArmed > 3000) {
      escArmed = Date.now();
      setStatus(T.DiscardAsk || "Unsaved changes - press Esc again to close without saving.", "bad", 3000);
      return;
    }
    hide();
    post("cfgClose");
  }

  function save() {
    if (saving || staged.size === 0 || invalid.size > 0) return;
    saving = true;
    setStatus("...", "");
    updateFoot();
    post("cfgSave", { file: fileKey, changes: Array.from(staged.values()) });
  }

  function onResult(r) {
    saving = false;
    r = r || {};
    if (r.ok) {
      staged.clear(); invalid.clear(); errors = new Map();
      setStatus(r.msg, "ok", 5000);
    } else {
      errors = new Map();
      for (const e of r.errors || []) errors.set(pkey(e.path), e.err);
      setStatus(r.msg, "bad", 8000);
      render();
    }
    updateFoot();
  }

  $("cfg-save").addEventListener("click", save);
  $("cfg-discard").addEventListener("click", () => {
    staged.clear(); invalid.clear(); errors = new Map();
    setStatus("");
    render();
  });
  $("cfg-close").addEventListener("click", requestClose);
  $("cfg-search").addEventListener("input", applySearch);

  window.addEventListener("keyup", (e) => {
    if (isOpen && e.key === "Escape") requestClose();
  });

  window.addEventListener("message", (event) => {
    const d = event.data || {};
    if (d.action === "cfgOpen") show(d);
    else if (d.action === "cfgFile") {
      if (isOpen && d.data && d.data.key === fileKey) { fileData = d.data; render(); }
    } else if (d.action === "cfgResult") { if (isOpen) onResult(d.result); }
    else if (d.action === "cfgClose" || d.action === "uiReset") hide();
  });
})();
