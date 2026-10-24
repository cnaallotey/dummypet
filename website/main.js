(() => {
  "use strict";
  const { Stage, COATS } = window.DummyPet;
  const Sky = window.DummySky && window.DummySky.Sky;
  const gsap = window.gsap;
  const ScrollTrigger = window.ScrollTrigger;
  const dark = window.matchMedia("(prefers-color-scheme: dark)");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  const $ = (sel) => document.querySelector(sel);

  let savedCoat = 0;
  try { savedCoat = Number(localStorage.getItem("dummypet.coat")) || 0; } catch (_) { /* storage blocked */ }

  // Each WebGL sky and the dog canvas on top of it share one ground height.
  const makeSky = (canvas, opts) => (Sky ? new Sky(canvas, opts) : null);

  // ---------- Hero ----------
  const heroGround = (w, h) => Math.round(clamp(h * 0.17, 70, 150));
  const heroDay = () => (dark.matches ? 0.97 : 0.06);
  const heroSky = makeSky($("#hero-sky"), { day: heroDay(), ground: heroGround, shoot: true });
  const hero = new Stage($("#hero-canvas"), { mode: "hero", interactive: true, coat: savedCoat, ground: heroGround, grass: !(heroSky && heroSky.ok), scale: 0.8 });
  dark.addEventListener("change", () => heroSky && heroSky.setDay(heroDay()));
  setTimeout(() => hero.say("Click the sky to throw my ball 🎾", 3.4), 900);

  // ---------- A day with your dog ----------
  const storyGround = (w, h) => Math.round(clamp(h * 0.16, 46, 96));
  const storySky = makeSky($("#story-sky"), { day: 0, ground: storyGround, shoot: true });
  const story = new Stage($("#story-dog"), { mode: "morning", interactive: true, coat: savedCoat, ground: storyGround, grass: !(storySky && storySky.ok), scale: 1.1 });
  const chapters = [...document.querySelectorAll(".chapter")];
  const dots = [...document.querySelectorAll(".story-dots li")];
  const chapterDays = chapters.map((c) => Number(c.dataset.day));
  let current = -1;
  let smoothSky = false;
  function activate(i) {
    if (i === current) return;
    current = i;
    chapters.forEach((c, k) => c.classList.toggle("active", k === i));
    dots.forEach((d, k) => d.classList.toggle("on", k <= i));
    story.setMode(chapters[i].dataset.mode);
    if (storySky && !smoothSky) storySky.setDay(chapterDays[i], reduce.matches);
  }
  const chapterObserver = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) activate(chapters.indexOf(e.target));
  }, { rootMargin: "-45% 0px -45% 0px" });
  chapters.forEach((c) => chapterObserver.observe(c));
  activate(0);

  // ---------- Tricks ----------
  const tricks = new Stage($("#tricks-canvas"), { mode: "tricks", interactive: true, coat: savedCoat, ground: 30, scale: 1.05 });
  const buttons = document.querySelectorAll(".trick");
  buttons.forEach((b) => {
    b.addEventListener("click", () => {
      buttons.forEach((x) => x.setAttribute("aria-pressed", "false"));
      b.setAttribute("aria-pressed", "true");
      tricks.trick(b.dataset.trick);
    });
  });
  tricks.onTrickEnd = () => buttons.forEach((x) => x.setAttribute("aria-pressed", "false"));

  // ---------- Breeds ----------
  const list = $("#breed-list");
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
      for (const s of [hero, tricks, story]) s.setCoat(i);
      tricks.say(`I'm a ${coat.name} now! ✨`, 2);
      try { localStorage.setItem("dummypet.coat", String(i)); } catch (_) { /* storage blocked */ }
    });
    return btn;
  });

  // ---------- Closing ----------
  const closingSky = makeSky($("#closing-sky"), { day: 1, ground: 56, shoot: true });
  const closing = new Stage($("#closing-dog"), { mode: "sleep", coat: 0, ground: 56, grass: !(closingSky && closingSky.ok), interactive: true });
  const placeSleeper = () => { closing.dog.x = closing.w * (closing.w > 640 ? 0.78 : 0.7); };
  placeSleeper();
  new ResizeObserver(placeSleeper).observe($("#closing-dog"));

  // ---------- Scroll animations ----------
  if (gsap && ScrollTrigger) {
    gsap.registerPlugin(ScrollTrigger);
    const mm = gsap.matchMedia();
    mm.add("(prefers-reduced-motion: no-preference)", () => {
      // Hero: hills sink at different speeds (depth) and the copy lifts away.
      ScrollTrigger.create({
        trigger: "#hero", start: "top top", end: "bottom top", scrub: true,
        onUpdate: (self) => heroSky && heroSky.setScroll(self.progress),
      });
      gsap.to(".hero-inner", {
        yPercent: -22, opacity: 0.15, ease: "none",
        scrollTrigger: { trigger: "#hero", start: "top top", end: "bottom top", scrub: true },
      });

      // Story: the sky's clock follows scroll continuously instead of jumping per chapter.
      if (storySky) {
        smoothSky = true;
        ScrollTrigger.create({
          trigger: ".story-chapters", start: "top center", end: "bottom center", scrub: true,
          onUpdate: (self) => {
            const f = self.progress * (chapterDays.length - 1);
            const i = Math.min(chapterDays.length - 2, Math.floor(f));
            storySky.setDay(chapterDays[i] + (chapterDays[i + 1] - chapterDays[i]) * (f - i));
          },
        });
      }

      // Install: a progress line fills down the three steps.
      gsap.to(".steps", {
        "--p": 1, ease: "none",
        scrollTrigger: { trigger: ".steps", start: "top 75%", end: "bottom 55%", scrub: true },
      });

      return () => {
        smoothSky = false;
        if (heroSky) heroSky.setScroll(0);
        if (storySky && current >= 0) storySky.setDay(chapterDays[current]);
      };
    });
  }

  // ---------- Copy command ----------
  document.querySelectorAll("[data-copy]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const target = document.querySelector(btn.dataset.copy);
      const label = btn.querySelector("span");
      try {
        await navigator.clipboard.writeText(target.textContent);
        label.textContent = "Copied";
      } catch (_) {
        label.textContent = "Press ⌘C";
        const range = document.createRange();
        range.selectNodeContents(target);
        const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range);
      }
      setTimeout(() => { label.textContent = "Copy"; }, 1800);
    });
  });

  // ---------- Reveal on scroll ----------
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); }
  }, { rootMargin: "0px 0px -8% 0px" });
  document.querySelectorAll(".reveal").forEach((el) => io.observe(el));

  // ---------- Download celebration ----------
  document.querySelectorAll("[data-download]").forEach((a) => {
    a.addEventListener("click", () => { hero.dog.happyTimer = 2; hero.hearts(4); hero.say("Yay! See you on your desktop 💕", 3); });
  });

  $("#year").textContent = new Date().getFullYear();
})();
