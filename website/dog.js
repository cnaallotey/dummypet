/* DummyPet web renderer: a port of Sources/Renderer.swift + a slimmed-down brain.
   Coordinates are y-up (like CoreGraphics); each Stage flips its canvas once. */
(() => {
  "use strict";
  const TAU = Math.PI * 2;
  const lerp = (a, b, t) => a + (b - a) * t;
  const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
  const rnd = (a, b) => a + Math.random() * (b - a);
  const chance = (p) => Math.random() < p;
  const pick = (arr) => arr[(Math.random() * arr.length) | 0];
  const smooth = (t) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };
  const col = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  // ---------- Affine transforms (CGAffineTransform layout: a b c d tx ty) ----------
  const T = {
    tr: (x, y) => [1, 0, 0, 1, x, y],
    rot: (a) => { const c = Math.cos(a), s = Math.sin(a); return [c, s, -s, c, 0, 0]; },
    sc: (x, y) => [x, 0, 0, y, 0, 0],
    // A then B
    cat: (A, B) => [
      A[0] * B[0] + A[1] * B[2], A[0] * B[1] + A[1] * B[3],
      A[2] * B[0] + A[3] * B[2], A[2] * B[1] + A[3] * B[3],
      A[4] * B[0] + A[5] * B[2] + B[4], A[4] * B[1] + A[5] * B[3] + B[5],
    ],
    ap: (M, x, y) => [M[0] * x + M[2] * y + M[4], M[1] * x + M[3] * y + M[5]],
  };
  const chain = (...ms) => ms.reduce((a, b) => T.cat(a, b));

  // ---------- Poses ----------
  const STAND = {
    bodyY: 32, bodyAngle: 0, headX: 30, headY: 16, headAngle: 0,
    ffx: 20, ffy: 0, bfx: -20, bfy: 0, prx: 0, pry: 0,
    tailAngle: 0.9, tailWag: 0.3, earLift: 0, eyeOpen: 1, mouth: 0, tongue: 0,
    walk: 0, roll: 0, happyEyes: 0, legWiggle: 0, scratch: 0,
  };
  const P = (o, base = STAND) => Object.assign({}, base, o);
  const POSE = {};
  POSE.stand = STAND;
  POSE.sit = P({ bodyY: 22, bodyAngle: 0.5, headX: 28, headY: 18, headAngle: -0.45, ffx: 19, bfx: -5, tailAngle: 0.55 });
  POSE.lie = P({ bodyY: 15, headX: 30, headY: 9, headAngle: -0.12, ffx: 44, ffy: 3, bfx: -34, bfy: 4, tailAngle: 0.15, tailWag: 0.2 });
  POSE.sleep = P({ headX: 31, headY: 4, headAngle: -0.3, eyeOpen: 0, tailWag: 0, earLift: -0.15 }, POSE.lie);
  POSE.eat = P({ headX: 33, headY: -4, headAngle: -0.55, tailWag: 0.5 });
  POSE.sniff = P({ headX: 33, headY: -2, headAngle: -0.45, tailWag: 0.4, tailAngle: 1.1 });
  POSE.beg = P({ bodyY: 24, bodyAngle: 1.1, headX: 34, headY: -2, headAngle: -1.0, ffx: 12, ffy: 42, bfx: -6, tailAngle: 1.2, tailWag: 0.5, earLift: 0.1 });
  POSE.playBow = P({ bodyY: 27, bodyAngle: -0.38, headX: 31, headY: 12, headAngle: 0.38, ffx: 40, bfx: -20, tailAngle: 1.35, tailWag: 0.7 });
  POSE.dig = P({ bodyY: 28, bodyAngle: -0.28, headX: 32, headY: 8, headAngle: 0.1, ffx: 36, ffy: 4, tailAngle: 1.3, tailWag: 0.5, scratch: 1 });
  POSE.jump = P({ bodyAngle: 0.05, ffx: 32, ffy: 16, bfx: -30, bfy: 12, earLift: 0.5, tailAngle: 1.0, mouth: 0.35 });
  POSE.bellyUp = P({ roll: Math.PI, ffx: 20, ffy: -12, bfx: -19, bfy: -12, legWiggle: 0.9, happyEyes: 1, tongue: 0.8, tailWag: 0.6, bodyY: 17, headY: -3, headAngle: 0.25 }, POSE.lie);
  POSE.playDead = P({ legWiggle: 0, happyEyes: 0, tongue: 1, tailWag: 0 }, POSE.bellyUp);
  POSE.wet = P({ earLift: -0.5, tailAngle: 0.2, tailWag: 0, eyeOpen: 0.7 }, POSE.sit);
  POSE.crouch = P({ bodyY: 25, ffx: 24, bfx: -16, tailWag: 0.8 });

  function approach(cur, t, k) {
    for (const key in t) {
      if (key === "roll") { cur.roll = t.roll; continue; }
      const kk = key === "mouth" ? Math.min(1, k * 1.8) : key === "walk" ? Math.min(1, k * 1.5) : k;
      cur[key] = lerp(cur[key], t[key], kk);
    }
  }

  // ---------- Breeds (same values as Model.swift) ----------
  function coat(name, b, d, e, pointy, pattern, o = [0.27, 0.17, 0.10]) {
    return {
      name, base: b, shade: b.map((v) => v * 0.84), dark: d, belly: e,
      muzzle: b.map((v, i) => (v + e[i] * 2) / 3), outline: o, pointy, pattern,
    };
  }
  const COATS = [
    coat("Golden Retriever", [0.89, 0.65, 0.35], [0.74, 0.48, 0.24], [0.98, 0.86, 0.64], false, "plain"),
    coat("Chocolate Lab", [0.48, 0.30, 0.19], [0.34, 0.20, 0.12], [0.62, 0.44, 0.31], false, "plain", [0.18, 0.10, 0.06]),
    coat("Dalmatian", [0.98, 0.97, 0.95], [0.13, 0.13, 0.14], [1, 1, 1], false, "spots", [0.22, 0.22, 0.24]),
    coat("Husky", [0.55, 0.58, 0.64], [0.33, 0.35, 0.40], [0.97, 0.97, 0.98], true, "husky", [0.16, 0.17, 0.20]),
    coat("Shiba Inu", [0.90, 0.52, 0.24], [0.74, 0.37, 0.15], [0.99, 0.93, 0.82], true, "shiba"),
    coat("Midnight Lab", [0.21, 0.20, 0.21], [0.12, 0.12, 0.13], [0.33, 0.32, 0.33], false, "plain", [0.04, 0.04, 0.05]),
    coat("Cotton Samoyed", [0.99, 0.98, 0.96], [0.90, 0.88, 0.85], [1, 1, 1], true, "plain", [0.45, 0.42, 0.40]),
  ];

  class Dog {
    constructor() {
      this.x = 0; this.y = 0; this.vx = 0; this.vy = 0;
      this.facing = 1; this.facingSmooth = 1; this.speed = 0; this.moved = false; this.phase = 0;
      this.pose = Object.assign({}, POSE.sit); this.roll = 0; this.rollLocked = false; this.wobble = 0;
      this.act = "sit"; this.actTime = 0; this.actDuration = 2; this.targetX = 0; this.trick = null;
      this.carrying = null; this.xEyes = false; this.foam = 0; this.tailSpeed = 10; this.spinStep = 0;
      this.blinkTimer = 2; this.blinking = 0; this.happyTimer = 0; this.pantTimer = 0; this.barkTimer = 0; this.jumpCooldown = 0;
      this.lickTimer = 0;
    }
    get onGround() { return this.y <= 0 && this.vy <= 0; }
  }

  function frames(d, s, gy) {
    const p = d.pose;
    const bob = Math.abs(Math.sin(d.phase)) * 2.2 * Math.min(p.walk, 1.2);
    const body = chain(T.tr(18, 6), T.rot(p.bodyAngle), T.tr(-18, -6 + p.bodyY + bob));
    const head = chain(T.rot(p.headAngle), T.tr(p.headX, p.headY));
    let f = d.facingSmooth;
    if (Math.abs(f) < 0.08) f = f < 0 ? -0.08 : 0.08;
    const world = chain(T.tr(0, -p.bodyY), T.rot(d.roll + d.wobble), T.tr(0, p.bodyY), T.sc(s * f, s), T.tr(d.x, gy + d.y));
    return {
      world, body, head,
      fromLocal: (x, y) => T.ap(world, x, y),
      fromBody: (x, y) => { const q = T.ap(body, x, y); return T.ap(world, q[0], q[1]); },
      fromHead: (x, y) => { const q = T.ap(head, x, y); const r = T.ap(body, q[0], q[1]); return T.ap(world, r[0], r[1]); },
    };
  }

  function neck(p) {
    const bx = 18, by = 6, tx = p.headX - 4, ty = p.headY - 5;
    const l = Math.hypot(tx - bx, ty - by) || 1;
    return { bx, by, tx, ty, cx: (bx + tx) / 2, cy: (by + ty) / 2, dx: (tx - bx) / l, dy: (ty - by) / l };
  }

  // ---------- Drawing helpers ----------
  const apply = (ctx, M) => ctx.transform(M[0], M[1], M[2], M[3], M[4], M[5]);
  function ell(ctx, cx, cy, rx, ry) { ctx.beginPath(); ctx.ellipse(cx, cy, Math.max(0.01, rx), Math.max(0.01, ry), 0, 0, TAU); }
  function fs(ctx, fill, stroke, w = 1.8) {
    ctx.fillStyle = fill; ctx.fill();
    if (stroke) { ctx.strokeStyle = stroke; ctx.lineWidth = w; ctx.lineJoin = "round"; ctx.stroke(); }
  }
  function line(ctx, ax, ay, bx, by, color, w) {
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.lineTo(bx, by);
    ctx.strokeStyle = color; ctx.lineWidth = w; ctx.lineCap = "round"; ctx.stroke();
  }
  function tri(ctx, a, b, c) { ctx.beginPath(); ctx.moveTo(a[0], a[1]); ctx.lineTo(b[0], b[1]); ctx.lineTo(c[0], c[1]); ctx.closePath(); }
  function floppyEar(ctx) {
    ctx.beginPath();
    ctx.moveTo(-6, 2);
    ctx.quadraticCurveTo(-12, -8, -5, -20);
    ctx.quadraticCurveTo(0, -27, 5, -17);
    ctx.quadraticCurveTo(8, -6, 6, 2);
    ctx.closePath();
  }
  function text(ctx, str, x, y, size, color, weight = 800) {
    ctx.save();
    ctx.translate(x, y); ctx.scale(1, -1);
    ctx.font = `${weight} ${size}px "Geist", system-ui, -apple-system, sans-serif`;
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillStyle = color; ctx.fillText(str, 0, 0);
    ctx.restore();
  }

  function drawDog(ctx, d, c, s, gy, time, look, dirt = 0) {
    const p = d.pose, t = time, fr = frames(d, s, gy), ol = col(c.outline);
    const lift = Math.min(d.y / 300, 0.6);
    const sw = 80 * s * (1 - lift * 0.6);
    ell(ctx, d.x, gy - 0.5 * s, sw / 2, 4.5 * s); ctx.fillStyle = `rgba(20,30,40,${0.16 * (1 - lift)})`; ctx.fill();

    ctx.save();
    apply(ctx, fr.world);
    const w = p.walk, ph = d.phase;
    const step = (o) => [Math.sin(ph + o) * 9 * w, Math.max(0, Math.cos(ph + o)) * 6 * w];
    const wig = (i) => [Math.sin(t * 15 + i * 1.7) * 4 * p.legWiggle, Math.cos(t * 13 + i * 2.3) * 4 * p.legWiggle];
    const scr = (o) => [Math.sin(t * 26 + o) * 8 * p.scratch, Math.abs(Math.cos(t * 26 + o)) * 6 * p.scratch];
    const add = (...v) => v.reduce((a, b) => [a[0] + b[0], a[1] + b[1]]);
    const sN = T.ap(fr.body, 20, -8), sF = T.ap(fr.body, 16, -8), hN = T.ap(fr.body, -19, -6), hF = T.ap(fr.body, -23, -6);
    const fFN = add([p.ffx, p.ffy], step(0), [p.prx, p.pry], wig(0), scr(0));
    const fFF = add([p.ffx - 5, p.ffy], step(Math.PI), wig(1), scr(Math.PI));
    const fBN = add([p.bfx, p.bfy], step(Math.PI), wig(2));
    const fBF = add([p.bfx - 5, p.bfy], step(0), wig(3));
    const leg = (a, b, color) => {
      line(ctx, a[0], a[1], b[0], b[1], ol, 11);
      line(ctx, a[0], a[1], b[0], b[1], color, 7.6);
      ell(ctx, b[0] + 1.5, b[1] + 2.5, 5.6, 4.2); fs(ctx, color, ol, 1.6);
    };
    leg(sF, fFF, col(c.shade));
    leg(hF, fBF, col(c.shade));

    // tail + body
    ctx.save();
    apply(ctx, fr.body);
    const ta = p.tailAngle + Math.sin(t * d.tailSpeed) * p.tailWag;
    const tdx = -Math.cos(ta), tdy = Math.sin(ta);
    const tbx = -28, tby = 5, ttx = tbx + tdx * 24, tty = tby + tdy * 24;
    const tcx = tbx + tdx * 14 + tdy * 5, tcy = tby + tdy * 14 - tdx * 5;
    ctx.beginPath(); ctx.moveTo(tbx, tby); ctx.quadraticCurveTo(tcx, tcy, ttx, tty);
    ctx.lineCap = "round"; ctx.strokeStyle = ol; ctx.lineWidth = 9.5; ctx.stroke();
    ctx.strokeStyle = col(c.base); ctx.lineWidth = 6.2; ctx.stroke();
    if (c.pointy) { ell(ctx, ttx, tty, 3, 3); ctx.fillStyle = col(c.belly); ctx.fill(); }

    ell(ctx, 0, 0, 31, 16); ctx.fillStyle = col(c.base); ctx.fill();
    ctx.save();
    ctx.clip();
    ell(ctx, 3, -12, 24, 8); ctx.fillStyle = col(c.belly); ctx.fill();
    if (c.pattern === "spots") {
      ctx.fillStyle = col(c.dark);
      for (const sp of [[-14, 6, 5], [4, -3, 4], [14, 8, 3.5], [-22, -5, 3], [-3, 11, 3], [21, -2, 3]]) { ell(ctx, sp[0], sp[1], sp[2], sp[2] * 0.85); ctx.fill(); }
    } else if (c.pattern === "husky") {
      ell(ctx, -6, 13, 27, 12); ctx.fillStyle = col(c.dark); ctx.fill();
    }
    if (dirt > 0.01) {
      ctx.fillStyle = `rgba(107,77,46,${0.75 * dirt})`;
      for (const b of [[-10, 2, 4], [8, 6, 3], [18, -6, 3.5], [-20, -8, 3]]) { ell(ctx, b[0], b[1], b[2], b[2] * 0.8); ctx.fill(); }
    }
    ctx.restore();
    ell(ctx, 0, 0, 31, 16); ctx.strokeStyle = ol; ctx.lineWidth = 1.8; ctx.stroke();
    ctx.restore();

    leg(hN, fBN, col(c.base));
    leg(sN, fFN, col(c.base));

    // haunch, neck, collar, head
    ctx.save();
    apply(ctx, fr.body);
    ell(ctx, -17, -1, 13, 14); fs(ctx, col(c.base), ol);
    if (c.pattern === "spots") { ell(ctx, -18, 4.5, 3, 2.5); ctx.fillStyle = col(c.dark); ctx.fill(); }
    const n = neck(p);
    line(ctx, n.bx, n.by, n.tx, n.ty, col(c.base), 17);
    const px = -n.dy, py = n.dx;
    line(ctx, n.cx + px * 8.5, n.cy + py * 8.5, n.cx - px * 8.5, n.cy - py * 8.5, "rgb(140,20,36)", 6.2);
    line(ctx, n.cx + px * 8.5, n.cy + py * 8.5, n.cx - px * 8.5, n.cy - py * 8.5, "rgb(224,56,71)", 4.2);
    ell(ctx, n.cx - px * 10.5, n.cy - py * 10.5, 2.9, 2.9); fs(ctx, "rgb(252,204,64)", "rgb(153,115,26)", 1);

    ctx.save();
    apply(ctx, fr.head);
    const earBounce = Math.sin(ph * 2) * 0.12 * w + Math.sin(t * 3) * 0.03;
    if (c.pointy) {
      tri(ctx, [-1, 10], [5, 29 + p.earLift * 4], [10, 11]); fs(ctx, col(c.shade), ol);
    } else {
      ctx.save(); ctx.translate(1, 13); ctx.rotate(0.35 - p.earLift * 1.3 + earBounce);
      floppyEar(ctx); fs(ctx, col(c.dark, 0.9), ol); ctx.restore();
    }
    ell(ctx, 0, 0, 17, 16.5); ctx.fillStyle = col(c.base); ctx.fill();
    ctx.save(); ctx.clip();
    if (c.pattern === "husky") {
      ell(ctx, 9, -8, 15, 10); ctx.fillStyle = col(c.belly); ctx.fill();
      ell(ctx, -8, 12, 12, 9); ctx.fillStyle = col(c.dark); ctx.fill();
      ell(ctx, 7.2, 10.2, 2.2, 1.7); ctx.fillStyle = col(c.belly); ctx.fill();
    } else if (c.pattern === "shiba") {
      ell(ctx, 9, -8, 15, 9.5); ctx.fillStyle = col(c.belly); ctx.fill();
    } else if (c.pattern === "spots") {
      ell(ctx, -7, 5.5, 4, 3.5); ctx.fillStyle = col(c.dark); ctx.fill();
    }
    ctx.restore();
    ell(ctx, 0, 0, 17, 16.5); ctx.strokeStyle = ol; ctx.lineWidth = 1.8; ctx.stroke();

    ell(ctx, 14, -5, 11.5, 7.5); fs(ctx, col(c.muzzle), ol);
    if (p.mouth > 0.05) { ell(ctx, 13, -11.5 - p.mouth * 2.5, 7.5, 1.5 + p.mouth * 4); ctx.fillStyle = "rgb(115,20,31)"; ctx.fill(); }
    if (p.tongue > 0.05) {
      const bob = Math.sin(t * 12) * 1.2 * p.tongue, ty = -12 - p.mouth * 4 - p.tongue * 4 + bob;
      ell(ctx, 15.5, ty, 3.9, 2.5 + 4.5 * p.tongue); fs(ctx, "rgb(245,117,143)", "rgb(191,64,89)", 1.1);
      line(ctx, 15.5, ty + 2, 15.5, ty - 2.5 * p.tongue, "rgb(204,77,102)", 0.9);
    }
    if (p.mouth > 0.05) { ell(ctx, 12.5, -12 - p.mouth * 6, 7, 3); fs(ctx, col(c.muzzle), ol, 1.4); }
    ctx.beginPath(); ctx.moveTo(23.5, -8); ctx.quadraticCurveTo(18, -12.5 - p.happyEyes * 1.5, 12, -9);
    ctx.strokeStyle = ol; ctx.lineWidth = 1.4; ctx.stroke();
    ell(ctx, 25, -1.5, 4.4, 3.4); ctx.fillStyle = "rgb(26,20,20)"; ctx.fill();
    ell(ctx, 26.1, 0.2, 1.1, 0.7); ctx.fillStyle = "rgba(255,255,255,0.55)"; ctx.fill();

    const open = d.blinking > 0 ? 0 : p.eyeOpen, ink = "rgb(18,15,15)";
    if (d.xEyes) {
      line(ctx, 3.5, 2.5, 8.5, 7.5, ink, 1.8); line(ctx, 3.5, 7.5, 8.5, 2.5, ink, 1.8);
    } else if (open < 0.25) {
      ctx.beginPath(); ctx.moveTo(2.5, 5); ctx.quadraticCurveTo(6, 2, 9.5, 5); ctx.strokeStyle = ink; ctx.lineWidth = 1.8; ctx.stroke();
    } else if (p.happyEyes > 0.5) {
      ctx.beginPath(); ctx.moveTo(2.5, 3.5); ctx.quadraticCurveTo(6, 9.5, 9.5, 3.5); ctx.strokeStyle = ink; ctx.lineWidth = 2; ctx.stroke();
    } else {
      const ex = 6 + look[0] * 1.3, ey = 5 + look[1] * 1.1;
      ell(ctx, ex, ey, 3.3, 3.6 * open); ctx.fillStyle = ink; ctx.fill();
      ell(ctx, ex + 1.15, ey + 0.4 * open + 1.05 * open, 1.05, 1.05 * open); ctx.fillStyle = "rgba(255,255,255,0.95)"; ctx.fill();
    }
    if (p.happyEyes > 0.2) { ell(ctx, 3.5, -2.5, 3.5, 2); ctx.fillStyle = `rgba(255,115,140,${0.45 * p.happyEyes})`; ctx.fill(); }

    if (c.pointy) {
      ctx.save(); ctx.translate(-4, 12); ctx.rotate(-p.earLift * 0.6); ctx.translate(4, -12);
      tri(ctx, [-12, 8], [-6, 31 + p.earLift * 3], [4, 13]); fs(ctx, col(c.base), ol);
      tri(ctx, [-8.5, 11], [-6, 25], [0, 14]); ctx.fillStyle = "rgb(245,179,184)"; ctx.fill();
      ctx.restore();
    } else {
      ctx.save(); ctx.translate(-6, 12); ctx.rotate(0.2 - p.earLift * 1.3 + earBounce);
      floppyEar(ctx); fs(ctx, col(c.dark), ol); ctx.restore();
    }
    if (d.foam > 0.01) {
      ctx.fillStyle = `rgba(255,255,255,${0.92 * d.foam})`;
      for (const f of [[-2, 15, 7], [7, 14, 5], [-10, 10, 5]]) { ell(ctx, f[0], f[1], f[2] * d.foam, f[2] * d.foam); ctx.fill(); }
    }
    ctx.restore(); // head
    if (d.foam > 0.01) {
      ctx.fillStyle = `rgba(255,255,255,${0.92 * d.foam})`;
      for (const b of [[-18, 14, 7], [-6, 17, 8], [8, 15, 7], [20, 11, 6], [-27, 5, 5], [-14, -2, 5]]) { ell(ctx, b[0], b[1], b[2] * d.foam, b[2] * d.foam); ctx.fill(); }
    }
    ctx.restore(); // body
    ctx.restore(); // world
  }

  // ---------- Props & particles ----------
  function drawBall(ctx, x, y, r, spin) {
    ell(ctx, x, y, r, r); fs(ctx, "rgb(214,237,66)", "rgb(107,133,20)", 1.5);
    ctx.save(); ell(ctx, x, y, r, r); ctx.clip();
    ctx.translate(x, y); ctx.rotate(spin);
    ctx.strokeStyle = "rgba(255,255,255,0.95)"; ctx.lineWidth = Math.max(1.2, r * 0.18);
    ctx.beginPath(); ctx.arc(-r * 1.25, 0, r * 0.95, -0.9, 0.9); ctx.stroke();
    ctx.beginPath(); ctx.arc(r * 1.25, 0, r * 0.95, Math.PI - 0.9, Math.PI + 0.9); ctx.stroke();
    ctx.restore();
  }
  function drawHeart(ctx, x, y, s, color) {
    ctx.fillStyle = color;
    ell(ctx, x - s * 0.45, y + s * 0.2, s * 0.55, s * 0.55); ctx.fill();
    ell(ctx, x + s * 0.45, y + s * 0.2, s * 0.55, s * 0.55); ctx.fill();
    tri(ctx, [x - s * 0.97, y + s * 0.05], [x + s * 0.97, y + s * 0.05], [x, y - s * 1.05]); ctx.fill();
  }
  function drawSparkle(ctx, x, y, s, rot, color) {
    ctx.save(); ctx.translate(x, y); ctx.rotate(rot); ctx.beginPath();
    for (let i = 0; i < 8; i++) {
      const a = i * Math.PI / 4, r = i % 2 === 0 ? s : s * 0.3;
      i === 0 ? ctx.moveTo(Math.cos(a) * r, Math.sin(a) * r) : ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    ctx.closePath(); ctx.fillStyle = color; ctx.fill(); ctx.restore();
  }
  function drawBowl(ctx, b, gy, s) {
    const w = 26 * s, h = 15 * s, x = b.x;
    ell(ctx, x, gy, w * 1.05, 3.5 * s); ctx.fillStyle = "rgba(20,30,40,0.15)"; ctx.fill();
    if (b.food > 0.01) {
      const mound = 2 * s + b.food * 8 * s;
      ell(ctx, x, gy + h, w * 0.85, mound); fs(ctx, "rgb(158,97,46)", "rgb(102,56,26)", 1.2);
      ctx.fillStyle = "rgb(122,69,31)";
      for (let i = 0; i < 9; i++) {
        ell(ctx, x + (i - 4) * w * 0.17, gy + h + mound * (0.2 + 0.5 * Math.abs(Math.sin(i * 1.9))), 2.2 * s, 1.6 * s); ctx.fill();
      }
    }
    ctx.beginPath(); ctx.moveTo(x - w, gy + h); ctx.lineTo(x + w, gy + h); ctx.lineTo(x + w * 0.76, gy); ctx.lineTo(x - w * 0.76, gy); ctx.closePath();
    fs(ctx, "rgb(219,69,82)", "rgb(128,26,38)", 1.6);
    ell(ctx, x, gy + h, w, 3.5 * s); fs(ctx, "rgb(242,107,117)", "rgb(128,26,38)", 1.4);
    ctx.fillStyle = "rgba(255,255,255,0.85)";
    ell(ctx, x, gy + h * 0.42, 3 * s, 2.4 * s); ctx.fill();
    for (let k = 0; k < 3; k++) { ell(ctx, x + (k - 1) * 3.4 * s, gy + h * 0.42 + 3.2 * s + (k === 1 ? s : 0), 1.3 * s, 1.3 * s); ctx.fill(); }
  }
  function drawFlower(ctx, f, gy, s, t) {
    const sway = Math.sin(t * 1.6 + f.phase) * 2.5, h = f.height * s;
    ctx.strokeStyle = "rgb(92,168,77)"; ctx.lineWidth = 1.6; ctx.lineCap = "round";
    if (f.kind === 0) {
      for (let i = -1; i <= 1; i++) {
        const dx = i * 3 * s;
        ctx.beginPath(); ctx.moveTo(f.x + dx, gy);
        ctx.quadraticCurveTo(f.x + dx, gy + h * 0.5, f.x + dx * 2 + sway, gy + h * (i === 0 ? 1 : 0.7)); ctx.stroke();
      }
      return;
    }
    const tx = f.x + sway, ty = gy + h * 1.3;
    ctx.beginPath(); ctx.moveTo(f.x, gy); ctx.quadraticCurveTo(f.x, gy + h * 0.7, tx, ty); ctx.stroke();
    if (f.kind === 1) {
      ctx.fillStyle = f.color;
      for (let i = 0; i < 6; i++) { const a = i * Math.PI / 3 + f.phase; ell(ctx, tx + Math.cos(a) * 3.2 * s, ty + Math.sin(a) * 3.2 * s, 2.4 * s, 2.4 * s); ctx.fill(); }
      ell(ctx, tx, ty, 2.2 * s, 2.2 * s); ctx.fillStyle = "rgb(252,204,51)"; ctx.fill();
    } else {
      ctx.beginPath();
      ctx.moveTo(tx - 4 * s, ty + 5 * s); ctx.lineTo(tx - 2 * s, ty + 2.5 * s); ctx.lineTo(tx, ty + 5 * s);
      ctx.lineTo(tx + 2 * s, ty + 2.5 * s); ctx.lineTo(tx + 4 * s, ty + 5 * s);
      ctx.quadraticCurveTo(tx, ty - 4 * s, tx - 4 * s, ty + 5 * s);
      ctx.fillStyle = f.color; ctx.fill();
    }
  }
  function drawLeash(ctx, ax, ay, bx, by) {
    const dist = Math.hypot(bx - ax, by - ay), sag = Math.max(6, 90 - dist * 0.22);
    ctx.beginPath(); ctx.moveTo(ax, ay); ctx.quadraticCurveTo((ax + bx) / 2, (ay + by) / 2 - sag, bx, by);
    ctx.lineCap = "round"; ctx.strokeStyle = "rgb(115,15,31)"; ctx.lineWidth = 5.2; ctx.stroke();
    ctx.strokeStyle = "rgb(230,64,82)"; ctx.lineWidth = 3.2; ctx.stroke();
  }
  function drawParticle(ctx, p) {
    const a = clamp(p.life / p.max, 0, 1);
    switch (p.kind) {
      case "heart": drawHeart(ctx, p.x, p.y, p.size * (0.7 + 0.3 * a), `rgba(245,84,115,${a})`); break;
      case "sparkle": drawSparkle(ctx, p.x, p.y, p.size * (0.4 + 0.6 * a), p.rot, `rgba(255,219,77,${a})`); break;
      case "crumb": ell(ctx, p.x, p.y, p.size, p.size); ctx.fillStyle = p.color.replace("A", a); ctx.fill(); break;
      case "dust": { const s = p.size * (1.6 - a * 0.6); ell(ctx, p.x, p.y, s, s); ctx.fillStyle = p.color.replace("A", a * 0.5); ctx.fill(); break; }
      case "droplet": ell(ctx, p.x, p.y, p.size * 0.7, p.size); ctx.fillStyle = `rgba(115,179,255,${0.85 * a})`; ctx.fill(); break;
      case "bubble":
        ell(ctx, p.x, p.y, p.size, p.size); ctx.fillStyle = `rgba(217,237,255,${0.25 * a})`; ctx.fill();
        ctx.strokeStyle = `rgba(153,204,255,${0.8 * a})`; ctx.lineWidth = 1.1; ctx.stroke();
        ell(ctx, p.x - p.size * 0.3, p.y + p.size * 0.35, p.size * 0.22, p.size * 0.17); ctx.fillStyle = `rgba(255,255,255,${0.8 * a})`; ctx.fill();
        break;
      case "zzz": ctx.save(); ctx.globalAlpha = a; text(ctx, p.text, p.x, p.y, p.size, "rgb(115,140,217)", 800); ctx.restore(); break;
      case "text": ctx.save(); ctx.globalAlpha = a; text(ctx, p.text, p.x, p.y, p.size, "#fff", 800); ctx.restore(); break;
      case "confetti":
        ctx.save(); ctx.translate(p.x, p.y); ctx.rotate(p.rot); ctx.fillStyle = p.color.replace("A", a);
        ctx.fillRect(-p.size / 2, -p.size / 4, p.size, p.size / 2 * Math.abs(Math.cos(p.rot * 2)) + 0.5); ctx.restore(); break;
    }
  }

  // ---------- Shared animation loop (one rAF for every stage) ----------
  const stages = new Set();
  let last = performance.now();
  function loop(now) {
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    for (const s of stages) {
      if (!s.visible) continue;
      try { s.frame(dt); } catch (err) { stages.delete(s); console.error(err); }
    }
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);

  const FLOWER_COLORS = ["#ffffff", "#fa8cb3", "#b38cfa", "#fa5959", "#fcbf4d"];
  const TREASURES = [["🦴", "a bone"], ["🧦", "your sock"], ["🪙", "a coin"], ["🧸", "a teddy"], ["🔑", "your keys?!"], ["🥏", "a frisbee"], ["💎", "a diamond"]];

  // ---------- Stage ----------
  class Stage {
    constructor(canvas, opts = {}) {
      this.canvas = canvas;
      this.ctx = canvas.getContext("2d");
      this.mode = opts.mode || "hero";
      this.coat = opts.coat || 0;
      this.k = opts.scale || 1;
      this.groundFn = typeof opts.ground === "function" ? opts.ground : () => opts.ground ?? 26;
      this.grass = opts.grass !== false;
      this.dog = new Dog();
      this.items = []; this.parts = []; this.flowers = []; this.bowl = null; this.bubble = null;
      this.time = 0; this.mouse = null; this.mouseVel = [0, 0]; this.owner = null;
      this.rub = 0; this.lastHeart = -10; this.rubStreak = 0; this.hover = false; this.sub = 0; this.cycle = 0;
      this.onTrickEnd = null;
      this.visible = true;
      this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      new IntersectionObserver((es) => { this.visible = es[0].isIntersecting; }, { rootMargin: "100px" }).observe(canvas);
      if (opts.interactive) this.bindPointer();
      this.init();
      this.updateFrames();
      stages.add(this);
    }

    resize() {
      const r = this.canvas.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(10, r.width); this.h = Math.max(10, r.height); this.dpr = dpr;
      this.canvas.width = Math.round(this.w * dpr); this.canvas.height = Math.round(this.h * dpr);
      const base = this.mode === "portrait" ? this.h / 118 : Math.min(this.w / 360, this.h / 150);
      this.s = clamp(base, 0.7, 2.3) * this.k;
      this.gy = this.groundFn(this.w, this.h);
      if (this.dog && this.mode !== "walk") this.dog.x = clamp(this.dog.x || this.w / 2, this.minX, this.maxX);
      if (this.flowers.length === 0 || this.mode === "walk") this.makeFlowers();
    }
    get minX() { return 50 * this.s; }
    get maxX() { return Math.max(this.minX + 1, this.w - 50 * this.s); }

    init() {
      const d = this.dog;
      d.x = this.w * (this.mode === "hero" ? 0.55 : 0.45);
      if (this.mode === "walk") { d.x = this.w * 0.4; this.set("walking"); }
      else if (this.mode === "sleep") { d.pose = Object.assign({}, POSE.sleep); this.set("sleep"); }
      else if (this.mode === "bath") this.set("bath", 5);
      else if (this.mode === "dig") this.set("dig", 2.6);
      else if (this.mode === "eat") { d.x = this.w * 0.38; this.bowl = { x: d.x + 43 * this.s, food: 1 }; d.pose = Object.assign({}, POSE.eat); this.set("eat"); }
      else if (this.mode === "portrait") { d.x = this.w / 2 - 4 * this.s; this.set("sit", 1e9); }
      else if (this.mode === "tricks") { d.x = this.w / 2; this.set("sit", 1e9); }
      else if (this.mode === "morning") { d.pose = Object.assign({}, POSE.sleep); this.set("sleep", 1.4); }
      else if (this.mode === "fetchloop") { d.x = this.w * 0.3; this.owner = this.w * 0.3; this.set("sit", 0.8); }
      else this.set("sit", 2.5);
    }

    makeFlowers() {
      this.flowers = [];
      let x = rnd(10, 40);
      while (x < this.w + 80) {
        const k = (Math.random() * 10) | 0;
        this.flowers.push({ x, kind: k < 5 ? 0 : k < 8 ? 1 : 2, height: rnd(8, 16), color: pick(FLOWER_COLORS), phase: rnd(0, 6) });
        x += rnd(22, 64);
      }
    }

    set(act, dur = 0) {
      const d = this.dog;
      d.act = act; d.actTime = 0; d.actDuration = dur; this.sub = 0;
      if (act !== "trick") { d.xEyes = false; d.rollLocked = false; }
    }
    say(str, dur = 2.4) { this.bubble = { text: str, life: dur, born: this.time }; }
    emit(kind, x, y, o = {}) {
      if (this.parts.length > 400) return;
      const life = o.life || 1;
      this.parts.push(Object.assign({ kind, x, y, vx: 0, vy: 0, life, max: life, size: 8, rot: 0, vrot: 0, g: 0, drag: 0, color: "rgba(255,255,255,A)", text: "" }, o, { life, max: life }));
    }
    hearts(n) {
      for (let i = 0; i < n; i++) this.emit("heart", this.head[0] + rnd(-14, 14), this.head[1] + 18 * this.s + i * 6, { vx: rnd(-25, 25), vy: rnd(50, 85), life: rnd(1.1, 1.6), size: rnd(6, 9) * this.s });
    }
    sparkles(x, y, n) {
      for (let i = 0; i < n; i++) {
        const a = rnd(0, TAU), r = rnd(4, 20), v = rnd(30, 90);
        this.emit("sparkle", x + Math.cos(a) * r, y + Math.sin(a) * r, { vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: rnd(0.6, 1.1), size: rnd(4, 7), vrot: rnd(-5, 5), drag: 2 });
      }
    }

    // ----- pointer -----
    bindPointer() {
      const c = this.canvas;
      const pos = (e) => { const r = c.getBoundingClientRect(); return [e.clientX - r.left, this.h - (e.clientY - r.top)]; };
      let samples = [];
      c.addEventListener("pointermove", (e) => {
        const p = pos(e), now = performance.now();
        samples.push([p, now]); samples = samples.filter((s) => now - s[1] < 90);
        if (this.mouse) {
          const dlt = Math.hypot(p[0] - this.mouse[0], p[1] - this.mouse[1]);
          if (this.inDog(p) && !this.held) {
            this.rub += dlt;
            if (this.rub > 140 * this.s) { this.rub = 0; this.petted(); }
          }
        }
        this.mouse = p;
        this.hover = this.inDog(p);
        if (this.held) { this.held.x = p[0]; this.held.y = Math.max(p[1], this.gy + this.held.r); }
      });
      c.addEventListener("pointerleave", () => { this.mouse = null; this.hover = false; });
      c.addEventListener("pointerdown", (e) => {
        const p = pos(e);
        this.mouse = p; this.owner = p[0];
        if (this.mode !== "hero") { if (this.inDog(p)) this.pat(); return; }
        if (this.inDog(p) && e.detail >= 2) { this.bark(); this.say(pick(["Woof! 🐶", "Bork!", "Arf arf!"]), 1.4); return; }
        if (this.inDog(p)) { this.pat(); return; }
        let ball = this.items.find((i) => !i.carried);
        if (this.dog.carrying) { this.dog.carrying.carried = false; this.dog.carrying = null; }
        if (!ball) { ball = { x: p[0], y: p[1], vx: 0, vy: 0, r: 9 * this.s, spin: 0, carried: false, thrown: false }; this.items = [ball]; }
        ball.x = p[0]; ball.y = Math.max(p[1], this.gy + ball.r); ball.vx = 0; ball.vy = 0; ball.thrown = false;
        this.held = ball;
        samples = [[p, performance.now()]];
        try { c.setPointerCapture(e.pointerId); } catch (_) { /* ignore */ }
        if (this.dog.act !== "trick") this.set("fetch");
      });
      const up = () => {
        if (!this.held) return;
        const b = this.held; this.held = null;
        let vx = 0, vy = 0;
        if (samples.length >= 2) {
          const a = samples[0], z = samples[samples.length - 1], dt = Math.max(0.016, (z[1] - a[1]) / 1000);
          vx = (z[0][0] - a[0][0]) / dt; vy = (z[0][1] - a[0][1]) / dt;
        }
        if (Math.hypot(vx, vy) < 120) { vx = (this.dog.x < b.x ? 1 : -1) * rnd(120, 220); vy = rnd(380, 520); }
        const sp = Math.hypot(vx, vy), max = 1600;
        if (sp > max) { vx *= max / sp; vy *= max / sp; }
        b.vx = vx; b.vy = vy; b.thrown = true;
        if (this.dog.act !== "trick") this.set("fetch");
      };
      c.addEventListener("pointerup", up);
      c.addEventListener("pointercancel", up);
    }
    inDog(p) {
      const d = this.dog, s = this.s;
      return p[0] > d.x - 56 * s && p[0] < d.x + 56 * s && p[1] > this.gy + d.y - 4 && p[1] < this.gy + d.y + 80 * s;
    }
    petted() {
      const d = this.dog;
      this.rubStreak = this.time - this.lastHeart < 2 ? this.rubStreak + 1 : 1;
      this.lastHeart = this.time;
      d.happyTimer = 1.6;
      this.emit("heart", this.head[0] + rnd(-12, 12), this.head[1] + 20 * this.s, { vx: rnd(-20, 20), vy: rnd(50, 80), life: rnd(1.1, 1.5), size: rnd(6, 9) * this.s });
      if (this.mode === "hero" && this.rubStreak >= 4 && ["idle", "sit", "lie"].includes(d.act)) {
        this.set("bellyUp"); if (chance(0.6)) this.say("Belly rubs!! 🥰", 1.8);
      }
    }
    pat() { this.dog.happyTimer = 1.2; this.hearts(1); if (chance(0.3)) this.bark(); }
    bark() { this.dog.barkTimer = 0.22; }

    // ----- tricks (mirrors World.trickBrain) -----
    trick(name) {
      const d = this.dog;
      if (["dragged"].includes(d.act)) return;
      if (d.carrying) { d.carrying.carried = false; d.carrying = null; }
      d.trick = name; d.spinStep = 0; d.y = 0; d.vy = 0; d.vx = 0;
      if (this.mouse && Math.abs(this.mouse[0] - d.x) > 4) d.facing = this.mouse[0] > d.x ? 1 : -1;
      this.set("trick");
    }
    trickBrain(dt) {
      const d = this.dog, s = this.s, t = d.actTime;
      const crossed = (x) => t >= x && t - dt < x;
      const done = () => { this.hearts(3); d.rollLocked = false; d.xEyes = false; d.roll = 0; this.set("sit", this.mode === "tricks" ? 1e9 : 1.6); if (this.onTrickEnd) this.onTrickEnd(); };
      switch (d.trick) {
        case "sit": if (t > 1.6) done(); break;
        case "speak":
          if (crossed(0.3) || crossed(0.85)) this.bark();
          if (crossed(0.3)) this.say("Woof! Woof!", 1.4);
          if (t > 1.6) done(); break;
        case "beg": if (t > 2.4) done(); break;
        case "spin":
          if (t < 1.3) {
            const st = (t / 0.13) | 0;
            if (st !== d.spinStep) { d.spinStep = st; d.facing = -d.facing; }
            if (crossed(0.1)) this.jump(18 * s, d.x);
          } else done();
          break;
        case "highFive":
          if (crossed(0.8)) {
            const fr = frames(d, s, this.gy), paw = fr.fromLocal(d.pose.ffx + d.pose.prx, d.pose.ffy + d.pose.pry);
            this.sparkles(paw[0], paw[1], 5);
            this.emit("text", paw[0], paw[1] + 18, { vy: 50, life: 1.2, size: 20, text: "✋" });
          }
          if (t > 1.8) done(); break;
        case "rollOver":
          d.rollLocked = true;
          d.roll = TAU * smooth((t - 0.35) / 0.9);
          if (t > 0.35 && t < 1.25) d.x = clamp(d.x + d.facing * 45 * s * dt, this.minX, this.maxX);
          if (t > 1.6) done(); break;
        case "playDead":
          d.xEyes = t > 0.6 && t < 3.0;
          if (crossed(0.25)) this.say("Bang! 💥 …x_x", 2);
          if (t > 3.6) { this.say("Ta-da! ✨", 1.4); done(); }
          break;
        case "backflip":
          if (crossed(0.3)) { d.vy = 680; d.y = 0.5; d.vx = 0; }
          if (t > 0.3) {
            d.rollLocked = true;
            d.roll = TAU * clamp((t - 0.3) / (2 * 680 / 1700), 0, 1);
            if (t > 0.4 && d.onGround) { this.sparkles(this.body[0], this.body[1], 10); this.say("🤸 Nailed it!", 1.6); done(); }
          }
          break;
        default: done();
      }
    }

    // ----- brain -----
    move(x, speed, dt, stop = 6, face = true) {
      const d = this.dog, dx = x - d.x;
      if (Math.abs(dx) <= stop) return true;
      const dir = dx > 0 ? 1 : -1;
      if (face) d.facing = dir;
      d.speed = lerp(d.speed, speed, Math.min(1, dt * 5));
      d.x += Math.min(Math.abs(dx), Math.max(d.speed, 20) * dt) * dir;
      d.moved = true;
      return Math.abs(x - d.x) <= stop;
    }
    jump(h, x) {
      const d = this.dog;
      if (!d.onGround || d.jumpCooldown > 0) return;
      d.vy = Math.min(Math.sqrt(2 * 1700 * Math.max(20, h)), 950);
      d.vx = clamp((x - d.x) * 2.2, -320, 320);
      if (Math.abs(x - d.x) > 2) d.facing = x > d.x ? 1 : -1;
      d.jumpCooldown = 0.7; d.y = 0.5;
    }
    decide() {
      const d = this.dog, r = Math.random();
      if (r < 0.45) {
        let tx = rnd(this.minX + 10, this.maxX - 10);
        if (Math.abs(tx - d.x) < 80) tx = d.x < this.w / 2 ? Math.min(this.maxX, d.x + rnd(100, 260)) : Math.max(this.minX, d.x - rnd(100, 260));
        d.targetX = tx; this.set("wander");
      } else if (r < 0.55) { d.targetX = clamp(d.x + d.facing * rnd(30, 80), this.minX, this.maxX); this.set("sniff", rnd(2, 3.5)); }
      else if (r < 0.65) this.set("playBow", 1.6);
      else if (r < 0.75) this.set("lie", rnd(4, 8));
      else this.set("sit", rnd(2.5, 6));
    }
    target() { return this.items.find((i) => i.thrown && !i.carried && i !== this.held); }

    heroBrain(dt) {
      const d = this.dog, s = this.s;
      switch (d.act) {
        case "idle": case "sit": case "lie": case "playBow":
          if (this.mode === "tricks" || this.mode === "fetchloop") break;
          if (d.actTime > d.actDuration) this.decide();
          break;
        case "wander":
          if (this.move(d.targetX, 85 * s, dt)) this.set(chance(0.5) ? "sit" : "idle", rnd(2, 5));
          else if (d.actTime > 15) this.decide();
          break;
        case "sniff":
          this.move(d.targetX, 26 * s, dt);
          if (d.actTime > d.actDuration) this.decide();
          break;
        case "bellyUp":
          if (this.time - this.lastHeart > 2.5) this.set("lie", 1.5);
          break;
        case "fetch": {
          if (this.held) {
            if (d.onGround && this.move(clamp(this.held.x, this.minX, this.maxX), 300 * s, dt, 55 * s)) {
              d.facing = this.held.x >= d.x ? 1 : -1;
              if (chance(dt * 1.2)) this.jump(25 * s, d.x);
            }
            break;
          }
          const b = this.target();
          if (!b) { this.set("sit", 2); break; }
          if (d.onGround) {
            if ((b.x - d.x) * d.facing < 0) d.facing = -d.facing;
            this.move(b.x - d.facing * 40 * s, 370 * s, dt, 3, false);
            const h = b.y - this.gy, dx = b.x - d.x;
            if (h > 55 * s && h < 240 * s && Math.abs(dx) < 120 * s && b.vy < 250) this.jump(h - 42 * s, b.x - d.facing * 30 * s);
          }
          const low = b.y - this.gy < 30 * s, near = Math.abs(this.mouth[0] - b.x) < 24 * s;
          if (Math.hypot(this.mouth[0] - b.x, this.mouth[1] - b.y) < b.r + 18 * s || (low && near && d.onGround)) {
            b.carried = true; b.thrown = false; d.carrying = b;
            if (d.y > 20) this.say(pick(["Got it!", "Nice catch, me! 😎"]), 1.2);
            this.set("carry");
          } else if (d.actTime > 20) { b.thrown = false; this.set("lie", 3); }
          break;
        }
        case "carry": {
          if (!d.carrying) { this.decide(); break; }
          if (!d.onGround) break;
          const home = this.owner ?? this.w * 0.5;
          if (this.move(clamp(home, this.minX, this.maxX), 280 * s, dt, 60 * s)) {
            d.facing = home >= d.x ? 1 : -1;
            const b = d.carrying; b.carried = false; b.x = this.mouth[0]; b.y = this.mouth[1]; b.vx = d.facing * 50; b.vy = 40;
            d.carrying = null; this.hearts(2); d.pantTimer = 4;
            if (chance(0.4)) this.say(pick(["Again! Again!", "Throw it! 🎾", "😁"]), 1.6);
            this.set("sit", 3);
          }
          break;
        }
        case "trick": this.trickBrain(dt); break;
      }
    }

    vignetteBrain(dt) {
      const d = this.dog, s = this.s, t = d.actTime;
      switch (this.mode) {
        case "walk": {
          const sniffing = d.act === "sniff";
          d.speed = lerp(d.speed, sniffing ? 0 : 95 * s, Math.min(1, dt * 4));
          d.facing = 1;
          for (const f of this.flowers) f.x -= d.speed * dt;
          if (this.flowers.length && this.flowers[0].x < -20) {
            this.flowers.shift();
            const lx = this.flowers[this.flowers.length - 1].x;
            const k = (Math.random() * 10) | 0;
            this.flowers.push({ x: lx + rnd(22, 64), kind: k < 5 ? 0 : k < 8 ? 1 : 2, height: rnd(8, 16), color: pick(FLOWER_COLORS), phase: rnd(0, 6) });
          }
          if (!sniffing && t > 4 && chance(dt * 0.4)) { this.set("sniff", 1.8); if (chance(0.5)) this.say("🌼 sniff sniff", 1.4); }
          if (sniffing && t > d.actDuration) this.set("walking");
          break;
        }
        case "sleep":
          this.sub -= dt;
          if (this.sub <= 0) { this.sub = 1.4; this.emit("zzz", this.head[0] + 10 * s, this.head[1] + 16 * s, { vx: 12, vy: 22, life: 2.4, size: rnd(11, 16) * s, text: chance(0.5) ? "z" : "Z", rot: rnd(-0.3, 0.3) }); }
          break;
        case "bath":
          if (d.act === "bath") {
            d.foam = Math.min(1, d.foam + dt / 2.5);
            if (chance(dt * 16)) this.emit("bubble", this.body[0] + rnd(-40, 40) * s, this.body[1] + rnd(-5, 40) * s, { vx: rnd(-15, 15), vy: rnd(25, 60), life: rnd(1, 2), size: rnd(3, 7) * s });
            if (t > d.actDuration) this.set("shake", 1.3);
          } else {
            const u = t / d.actDuration;
            d.wobble = Math.sin(t * 48) * 0.2 * (1 - u);
            d.foam = Math.max(0, d.foam - dt * 2.5);
            for (let i = 0; i < 2; i++) this.emit("droplet", this.body[0] + rnd(-30, 30) * s, this.body[1] + rnd(-5, 20) * s, { vx: rnd(-260, 260), vy: rnd(60, 260), life: rnd(0.5, 0.9), size: rnd(1.8, 3) * s, g: 900 });
            if (t > d.actDuration) { d.wobble = 0; this.sparkles(this.body[0], this.body[1], 6); this.say(pick(["So fresh! ✨", "Never again. …okay, maybe."]), 1.8); this.set("bath", 4.5); }
          }
          break;
        case "dig":
          if (d.act === "dig") {
            if (chance(dt * 26)) this.emit("dust", d.x + d.facing * 30 * s, this.gy + 4, { vx: -d.facing * rnd(80, 180), vy: rnd(80, 200), life: rnd(0.5, 0.9), size: rnd(2, 4) * s, color: "rgba(140,102,64,A)", g: 700 });
            if (t > d.actDuration) {
              const loot = TREASURES[this.cycle++ % TREASURES.length];
              const x = d.x + d.facing * 40 * s;
              this.emit("text", x, this.gy + 12, { vy: 45, life: 2, size: 24 * Math.min(1.2, s), text: loot[0] });
              this.sparkles(x, this.gy + 22, 6);
              this.say(`Found ${loot[1]}!`, 1.8);
              this.set("sit", 2.2);
            }
          } else if (t > d.actDuration) this.set("dig", 2.6);
          break;
        case "eat":
          if (d.act === "eat") {
            this.sub -= dt;
            if (this.sub <= 0) { this.sub = 0.32; for (let i = 0; i < 2; i++) this.emit("crumb", this.mouth[0], this.mouth[1], { vx: rnd(-60, 60), vy: rnd(40, 120), life: 0.8, size: rnd(1.4, 2.4) * s, color: "rgba(140,82,38,A)", g: 600 }); }
            this.bowl.food = Math.max(0, this.bowl.food - dt * 0.16);
            if (this.bowl.food <= 0) { d.lickTimer = 1.4; this.say(pick(["Yum! 😋", "*burp*", "More please"]), 1.6); this.set("sit", 2.4); }
          } else if (t > d.actDuration) {
            this.bowl.food = 1;
            for (let i = 0; i < 12; i++) this.emit("crumb", this.bowl.x + rnd(-14, 14) * s, this.gy + 60 * s + i * 5, { vy: -40, life: 0.6, size: rnd(2, 3) * s, color: "rgba(158,97,46,A)", g: 900 });
            this.set("eat");
          }
          break;
        case "morning":
          if (d.act === "sleep" && t > d.actDuration) this.set("stretch", 1.9);
          else if (d.act === "stretch" && t > d.actDuration) {
            this.set("sit", 3.6); d.happyTimer = 1.5;
            this.say(pick(["Good morning! ☀️", "Is it breakfast yet?", "Morning! 🐾"]), 2.2);
          } else if (d.act === "sit" && t > d.actDuration) this.set("stretch", 1.9);
          break;
        case "fetchloop":
          if ((d.act === "sit" || d.act === "idle") && t > d.actDuration && !this.items.some((b) => b.thrown || b.carried)) {
            const r = 9 * s;
            this.items = [{ x: this.w - r, y: this.h * rnd(0.5, 0.7), vx: -rnd(260, 420), vy: rnd(120, 300), r, spin: 0, carried: false, thrown: true }];
            this.owner = this.w * 0.28;
            this.set("fetch");
          }
          this.heroBrain(dt);
          break;
        case "portrait":
          break;
      }
    }

    targetPose() {
      const d = this.dog, t = this.time, s = this.s;
      let p;
      switch (d.act) {
        case "sit": p = POSE.sit; break;
        case "lie": p = POSE.lie; break;
        case "sleep": p = POSE.sleep; break;
        case "sniff": p = P({ headY: POSE.sniff.headY + Math.sin(t * 9) * 2 }, POSE.sniff); break;
        case "playBow": p = POSE.playBow; break;
        case "stretch": p = P({ mouth: d.actTime > 0.5 ? 0.9 : 0, eyeOpen: 0.3, tailWag: 0.2 }, POSE.playBow); break;
        case "bellyUp": p = POSE.bellyUp; break;
        case "eat": p = P({ mouth: 0.35 + 0.35 * Math.sin(t * 14) }, POSE.eat); break;
        case "dig": p = POSE.dig; break;
        case "bath": p = POSE.wet; break;
        case "shake": p = P({ earLift: Math.sin(t * 40) * 0.6, eyeOpen: 0.2 }); break;
        case "fetch": {
          const b = this.target();
          p = b && b.y - this.gy < 30 * s && Math.abs(b.x - d.x) < 80 * s ? POSE.sniff : P({ tailWag: 0.7 });
          break;
        }
        case "carry": p = P({ tailWag: 0.7 }); break;
        case "trick": p = this.trickPose(); break;
        default: p = STAND;
      }
      p = Object.assign({}, p);
      const flipping = d.act === "trick" && (d.trick === "backflip" || d.trick === "spin");
      if (d.y > 1 && !flipping) p = Object.assign({}, POSE.jump);
      p.walk = Math.min(1.6, d.speed / (95 * s));
      if (d.happyTimer > 0 || this.hover) { p.tailWag *= 1.6; p.happyEyes = 1; }
      if (d.pantTimer > 0) { p.tongue = Math.max(p.tongue, 1); p.mouth = Math.max(p.mouth, 0.35); }
      if (d.lickTimer > 0) p.tongue = Math.max(p.tongue, 0.6);
      if (d.barkTimer > 0) p.mouth = 1;
      if (this.mode === "portrait") { p.tongue = this.hover ? 1 : 0; p.mouth = this.hover ? 0.35 : 0; }
      d.tailSpeed = d.happyTimer > 0 || this.hover || d.act === "fetch" || d.act === "carry" ? 18 : 10;
      return p;
    }
    trickPose() {
      const d = this.dog, t = d.actTime;
      switch (d.trick) {
        case "speak": return P({ headAngle: -0.65 }, POSE.sit);
        case "beg": return P({ ffy: POSE.beg.ffy + Math.sin(this.time * 8) * 3 }, POSE.beg);
        case "spin": return STAND;
        case "highFive": return t > 0.35 && t < 1.5 ? P({ prx: 10, pry: 34 }, POSE.sit) : POSE.sit;
        case "rollOver": return POSE.lie;
        case "playDead": return t > 0.3 && t < 3.0 ? POSE.playDead : POSE.lie;
        case "backflip": return t < 0.3 ? POSE.crouch : POSE.jump;
        default: return POSE.sit;
      }
    }

    frame(dt) {
      if (reduceMotion.matches) {
        if (!this.drawnStatic) { this.updateFrames(); this.draw(); this.drawnStatic = true; }
        return;
      }
      this.drawnStatic = false;
      const d = this.dog;
      this.time += dt;
      d.actTime += dt;
      d.moved = false;
      if (d.y > 0 || d.vy > 0) {
        d.vy -= 1700 * dt; d.y += d.vy * dt; d.x += d.vx * dt;
        if (d.x < this.minX) { d.x = this.minX; d.vx = Math.abs(d.vx) * 0.5; }
        if (d.x > this.maxX) { d.x = this.maxX; d.vx = -Math.abs(d.vx) * 0.5; }
        if (d.y <= 0) { d.y = 0; d.vy = 0; d.vx = 0; }
      }
      if (this.mode === "hero" || this.mode === "tricks") this.heroBrain(dt);
      else this.vignetteBrain(dt);
      if (!d.moved && this.mode !== "walk") d.speed = lerp(d.speed, 0, Math.min(1, dt * 10));
      if (this.mode !== "walk") d.x = clamp(d.x, this.minX, this.maxX);

      const tp = this.targetPose();
      approach(d.pose, tp, 1 - Math.exp(-12 * dt));
      d.facingSmooth = lerp(d.facingSmooth, d.facing, 1 - Math.exp(-14 * dt));
      if (!d.rollLocked) d.roll = lerp(d.roll, tp.roll, 1 - Math.exp(-7 * dt));
      if (d.speed > 2) d.phase += Math.min(30, 3 + d.speed / (5.5 * this.s)) * dt;
      for (const k of ["happyTimer", "pantTimer", "barkTimer", "jumpCooldown", "blinking", "blinkTimer", "lickTimer"]) d[k] -= dt;
      if (d.blinkTimer <= 0) { d.blinking = 0.12; d.blinkTimer = rnd(2.5, 6); }
      this.updateFrames();

      // ball physics
      for (const b of this.items) {
        if (b === this.held) continue;
        if (b.carried) { b.x = this.mouth[0]; b.y = this.mouth[1]; continue; }
        b.vy -= 1500 * dt; b.x += b.vx * dt; b.y += b.vy * dt;
        const floor = this.gy + b.r;
        if (b.y < floor) { b.y = floor; b.vy = b.vy < -90 ? -b.vy * 0.58 : 0; b.vx *= Math.max(0, 1 - dt * 1.6); }
        if (b.x < b.r) { b.x = b.r; b.vx = Math.abs(b.vx) * 0.6; }
        if (b.x > this.w - b.r) { b.x = this.w - b.r; b.vx = -Math.abs(b.vx) * 0.6; }
        if (b.y > this.h - b.r) { b.y = this.h - b.r; b.vy = -Math.abs(b.vy) * 0.5; }
        b.spin -= b.vx * dt / b.r;
      }
      // particles
      const alive = [];
      for (const p of this.parts) {
        p.life -= dt; if (p.life <= 0) continue;
        p.vy -= p.g * dt;
        if (p.drag) { const f = Math.max(0, 1 - p.drag * dt); p.vx *= f; p.vy *= f; }
        p.x += p.vx * dt; p.y += p.vy * dt; p.rot += p.vrot * dt;
        if ((p.kind === "crumb" || p.kind === "droplet" || p.kind === "dust") && p.y < this.gy) { p.y = this.gy; p.vx = 0; p.vy = 0; p.g = 0; }
        alive.push(p);
      }
      this.parts = alive;
      if (this.bubble) { this.bubble.life -= dt; if (this.bubble.life <= 0) this.bubble = null; }
      this.draw();
    }

    updateFrames() {
      const fr = frames(this.dog, this.s, this.gy);
      this.head = fr.fromHead(0, 0);
      this.mouth = fr.fromHead(19, -11);
      const n = neck(this.dog.pose);
      this.collar = fr.fromBody(n.cx, n.cy);
      this.body = fr.fromBody(0, 0);
    }

    draw() {
      const ctx = this.ctx, d = this.dog, s = this.s;
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.clearRect(0, 0, this.canvas.width, this.canvas.height);
      ctx.setTransform(this.dpr, 0, 0, -this.dpr, 0, this.h * this.dpr);
      if (this.grass) {
        ctx.fillStyle = "rgba(96,176,84,0.9)"; ctx.fillRect(0, 0, this.w, this.gy);
        ctx.fillStyle = "rgba(76,150,66,0.9)"; ctx.fillRect(0, this.gy - 2.5, this.w, 2.5);
      }
      if (this.mode === "walk" || this.mode === "hero") for (const f of this.flowers) drawFlower(ctx, f, this.gy, s * 0.9, this.time);
      if (this.bowl) drawBowl(ctx, this.bowl, this.gy, s);
      for (const b of this.items) if (!b.carried && b !== this.held) drawBall(ctx, b.x, b.y, b.r, b.spin);

      let look = [0, 0];
      const focus = this.target() || this.held || (this.mouse ? { x: this.mouse[0], y: this.mouse[1] } : null);
      if (focus && this.head) {
        const vx = focus.x - this.head[0], vy = focus.y - this.head[1], l = Math.hypot(vx, vy) || 1;
        look = [vx / l * (d.facing >= 0 ? 1 : -1), vy / l];
      }
      drawDog(ctx, d, COATS[this.coat], s, this.gy, this.time, look);
      for (const b of this.items) if (b.carried || b === this.held) drawBall(ctx, b.x, b.y, b.r, b.spin);
      if (this.mode === "walk") drawLeash(ctx, this.collar[0], this.collar[1], this.w * 0.86, this.h + 4);
      for (const p of this.parts) drawParticle(ctx, p);
      this.drawBubble();
    }

    drawBubble() {
      const b = this.bubble; if (!b || !this.head) return;
      const ctx = this.ctx;
      ctx.save();
      ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0); // y-down for text
      const size = clamp(13 * Math.min(1.15, this.s * 0.75), 12, 15);
      ctx.font = `600 ${size}px "Geist", system-ui, -apple-system, sans-serif`;
      const tw = ctx.measureText(b.text).width, w = tw + 22, h = size + 14;
      const ax = this.head[0], ay = this.h - Math.max(this.head[1] + 26 * this.s, this.gy + 70 * this.s);
      const x = clamp(ax - w / 2, 6, this.w - w - 6), y = Math.max(6, ay - h - 10);
      const pop = Math.min(1, (this.time - b.born) / 0.15), fade = Math.min(1, b.life / 0.3);
      ctx.globalAlpha = fade;
      ctx.translate(x + w / 2, y + h); ctx.scale(0.6 + 0.4 * pop, 0.6 + 0.4 * pop); ctx.translate(-(x + w / 2), -(y + h));
      const tx = clamp(ax, x + 14, x + w - 14);
      ctx.beginPath();
      ctx.roundRect(x, y, w, h, 11);
      ctx.moveTo(tx - 7, y + h - 1); ctx.lineTo(tx + (ax - tx) * 0.5, y + h + 9); ctx.lineTo(tx + 7, y + h - 1);
      ctx.shadowColor = "rgba(20,30,50,0.22)"; ctx.shadowBlur = 8; ctx.shadowOffsetY = 2;
      ctx.fillStyle = "rgba(255,255,255,0.97)"; ctx.fill();
      ctx.shadowColor = "transparent";
      ctx.fillStyle = "#1c2030"; ctx.textBaseline = "middle"; ctx.fillText(b.text, x + 11, y + h / 2 + 0.5);
      ctx.restore();
    }

    /** Switch behaviour live (story chapters). */
    setMode(mode) {
      if (mode === this.mode) return;
      const d = this.dog;
      this.mode = mode;
      this.items = []; this.bowl = null; this.bubble = null; this.parts = [];
      d.carrying = null; d.y = 0; d.vy = 0; d.vx = 0; d.foam = 0; d.wobble = 0; d.roll = 0; d.rollLocked = false; d.xEyes = false;
      this.cycle = 0;
      this.init();
      if (mode === "walk") this.makeFlowers();
      if (reduceMotion.matches) { d.pose = Object.assign({}, this.targetPose()); d.speed = 0; this.drawnStatic = false; }
    }

    setCoat(i) { this.coat = i; this.dog.happyTimer = 1.4; this.hearts(2); }
  }

  window.DummyPet = { Stage, COATS };
})();
