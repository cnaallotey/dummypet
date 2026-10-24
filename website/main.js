(() => {
  "use strict";
  const { Stage, COATS } = window.DummyPet;

  let savedCoat = 0;
  try { savedCoat = Number(localStorage.getItem("dummypet.coat")) || 0; } catch (_) { /* storage blocked */ }

  const hero = new Stage(document.getElementById("hero-canvas"), { mode: "hero", interactive: true, coat: savedCoat, ground: 30 });
  const tricks = new Stage(document.getElementById("tricks-canvas"), { mode: "tricks", interactive: true, coat: savedCoat, ground: 30, scale: 1.05 });
  setTimeout(() => hero.say("Hi! Click to throw my ball 🎾", 3.2), 900);

  document.querySelectorAll("canvas[data-stage]").forEach((c, i) => {
    new Stage(c, { mode: c.dataset.stage, coat: [0, 3, 2, 4, 1][i % 5], grass: c.dataset.grass !== "false", interactive: true, ground: 24 });
  });

  // Tricks
  const buttons = document.querySelectorAll(".trick");
  buttons.forEach((b) => {
    b.addEventListener("click", () => {
      buttons.forEach((x) => x.setAttribute("aria-pressed", "false"));
      b.setAttribute("aria-pressed", "true");
      tricks.trick(b.dataset.trick);
    });
  });
  tricks.onTrickEnd = () => buttons.forEach((x) => x.setAttribute("aria-pressed", "false"));

  // Breeds
  const list = document.getElementById("breed-list");
  const breedButtons = COATS.map((coat, i) => {
    const btn = document.createElement("button");
    btn.className = "breed";
    btn.setAttribute("role", "radio");
    btn.setAttribute("aria-checked", String(i === savedCoat));
    btn.innerHTML = `<div class="scene scene-sky"><canvas aria-hidden="true"></canvas></div>${coat.name}`;
    list.appendChild(btn);
    const stage = new Stage(btn.querySelector("canvas"), { mode: "portrait", coat: i, ground: 16, interactive: true });
    btn.addEventListener("click", () => {
      breedButtons.forEach((x) => x.setAttribute("aria-checked", "false"));
      btn.setAttribute("aria-checked", "true");
      stage.pat();
      hero.setCoat(i);
      tricks.setCoat(i);
      hero.say(`I'm a ${coat.name} now! ✨`, 2);
      try { localStorage.setItem("dummypet.coat", String(i)); } catch (_) { /* storage blocked */ }
    });
    return btn;
  });

  // Copy command
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const text = document.querySelector(btn.dataset.copy).textContent;
      const label = btn.querySelector("span");
      try {
        await navigator.clipboard.writeText(text);
        label.textContent = "Copied";
      } catch (_) {
        label.textContent = "Press ⌘C";
        const range = document.createRange();
        range.selectNodeContents(document.querySelector(btn.dataset.copy));
        const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
      }
      setTimeout(() => { label.textContent = "Copy"; }, 1800);
    });
  });

  // Reveal on scroll
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }, { rootMargin: "0px 0px -8% 0px" });
  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

  // Download celebration on the hero dog
  document.querySelectorAll("[data-download]").forEach((a) => {
    a.addEventListener("click", () => { hero.dog.happyTimer = 2; hero.hearts(4); hero.say("Yay! See you on your desktop 💕", 3); });
  });

  document.getElementById("year").textContent = new Date().getFullYear();
})();
