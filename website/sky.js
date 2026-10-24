/* DummyPet WebGL sky: one fragment shader draws the sky gradient, sun, moon, clouds,
   stars, shooting stars and three parallax hill layers over a flat ground strip.
   uDay runs 0 (morning) -> 0.4 (noon) -> 0.75 (sunset) -> 1 (night). */
(() => {
  "use strict";
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

  const VERT = `
    attribute vec2 aPos;
    void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
  `;

  const FRAG = `
    precision highp float;
    uniform vec2 uRes;
    uniform float uTime;
    uniform float uDay;
    uniform float uScroll;
    uniform float uGround;
    uniform float uDpr;
    uniform vec2 uMouse;
    uniform float uShoot;
    uniform float uHills;

    float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
    float noise(vec2 p) {
      vec2 i = floor(p), f = fract(p);
      vec2 u = f * f * (3.0 - 2.0 * f);
      return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
    }
    float fbm(vec2 p) {
      // Rotate each octave so value-noise grid lines never stack up into boxy shapes.
      float v = 0.0, a = 0.5;
      mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
      for (int i = 0; i < 5; i++) { v += a * noise(p); p = m * p + 3.1; a *= 0.5; }
      return v;
    }
    vec3 pal(vec3 a, vec3 b, vec3 c, vec3 d, float t) {
      if (t < 0.4) return mix(a, b, t / 0.4);
      if (t < 0.75) return mix(b, c, (t - 0.4) / 0.35);
      return mix(c, d, (t - 0.75) / 0.25);
    }
    #define C(r, g, b) vec3(r, g, b) / 255.0

    void main() {
      vec2 px = gl_FragCoord.xy;
      vec2 uv = px / uRes;
      float aspect = uRes.x / uRes.y;
      vec2 q = vec2(uv.x * aspect, uv.y);
      float d = uDay;

      vec3 top = pal(C(143.0, 196.0, 255.0), C(86.0, 164.0, 255.0), C(78.0, 92.0, 170.0), C(10.0, 18.0, 46.0), d);
      vec3 bot = pal(C(255.0, 226.0, 196.0), C(208.0, 232.0, 255.0), C(255.0, 158.0, 110.0), C(40.0, 56.0, 104.0), d);
      vec3 farC = pal(C(168.0, 206.0, 200.0), C(150.0, 196.0, 214.0), C(150.0, 118.0, 160.0), C(36.0, 52.0, 92.0), d);
      vec3 midC = pal(C(122.0, 188.0, 124.0), C(110.0, 184.0, 108.0), C(108.0, 96.0, 122.0), C(28.0, 44.0, 74.0), d);
      vec3 nearC = pal(C(98.0, 172.0, 94.0), C(86.0, 166.0, 82.0), C(78.0, 92.0, 88.0), C(22.0, 40.0, 54.0), d);
      vec3 groundC = pal(C(106.0, 182.0, 92.0), C(98.0, 178.0, 86.0), C(86.0, 108.0, 74.0), C(28.0, 52.0, 48.0), d);

      float hy = uGround / uRes.y;
      float sy = clamp((uv.y - hy) / max(0.001, 1.0 - hy), 0.0, 1.0);
      vec3 col = mix(bot, top, pow(sy, 0.8));

      // Sun: arcs down toward the horizon by sunset, gone at night.
      // On portrait screens the headline fills the sky, so the sun and moon step aside.
      float portrait = 1.0 - smoothstep(0.9, 1.2, aspect);
      vec2 sp = vec2(mix(0.74, 0.9, d) * aspect, mix(0.8, 0.22, smoothstep(0.3, 0.85, d)));
      float sd = length(q - sp);
      float sunVis = (1.0 - smoothstep(0.8, 0.9, d)) * (1.0 - portrait);
      vec3 sunCol = mix(vec3(1.0, 0.96, 0.82), vec3(1.0, 0.62, 0.36), smoothstep(0.4, 0.8, d));
      col += sunCol * (smoothstep(0.058, 0.052, sd) * 0.9 + 0.32 * exp(-sd * 6.0)) * sunVis;

      // Moon (crescent) and night glow.
      float moonVis = smoothstep(0.8, 0.95, d) * (1.0 - portrait);
      vec2 mp = vec2(0.8 * aspect, 0.8);
      float md = length(q - mp);
      float disc = smoothstep(0.046, 0.041, md);
      float bite = smoothstep(0.046, 0.041, length(q - mp - vec2(0.02, 0.014)));
      col = mix(col, vec3(1.0, 0.97, 0.86), disc * (1.0 - bite * 0.9) * moonVis);
      col += vec3(0.55, 0.65, 1.0) * 0.1 * exp(-md * 7.0) * moonVis;

      // Stars.
      float starVis = smoothstep(0.78, 1.0, d) * smoothstep(0.0, 0.25, sy);
      float cellSize = 34.0 * uDpr;
      vec2 cell = floor(px / cellSize);
      vec2 f = fract(px / cellSize) - 0.5;
      float h = hash(cell);
      if (h > 0.8) {
        vec2 o = vec2(hash(cell + 1.3), hash(cell + 7.1)) - 0.5;
        float r = length(f - o * 0.7);
        float tw = 0.55 + 0.45 * sin(uTime * (1.0 + h * 3.0) + h * 40.0);
        col += vec3(1.0, 0.98, 0.9) * smoothstep(0.07, 0.0, r) * tw * starVis * (h - 0.8) * 5.0;
      }

      // Shooting star every few seconds.
      if (uShoot > 0.5) {
        float sid = floor(uTime / 4.5);
        float st = fract(uTime / 4.5);
        vec2 s0 = vec2((0.35 + 0.5 * hash(vec2(sid, 1.0))) * aspect, 0.92 - 0.18 * hash(vec2(sid, 2.0)));
        vec2 dir = normalize(vec2(-0.85, -0.35));
        vec2 head = s0 + dir * st * 1.4;
        vec2 tail = head - dir * 0.16;
        vec2 pa = q - tail, ba = head - tail;
        float k = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
        float dist = length(pa - ba * k);
        float vis = (1.0 - smoothstep(0.0, 0.22, st)) * starVis;
        col += vec3(1.0) * smoothstep(0.004, 0.0, dist) * k * vis;
      }

      // Clouds drift slowly; dimmer and bluer at night.
      float cloudVis = 1.0 - smoothstep(0.78, 1.0, d) * 0.8;
      vec2 cp = vec2(uv.x * aspect * 1.7 + uTime * 0.012 + uMouse.x * 0.03, uv.y * 4.2 + uScroll * 0.6);
      cp += 0.35 * vec2(fbm(cp * 0.7 + 7.0), fbm(cp * 0.7 - 3.0));
      float c = fbm(cp);
      float band = smoothstep(hy + 0.18, hy + 0.5, uv.y) * (1.0 - smoothstep(0.92, 1.0, uv.y));
      float cm = smoothstep(0.56, 0.78, c) * band;
      vec3 cloudCol = mix(vec3(1.0), mix(bot, vec3(1.0, 0.82, 0.78), 0.5), smoothstep(0.5, 0.78, d));
      cloudCol = mix(cloudCol, vec3(0.35, 0.42, 0.62), smoothstep(0.85, 1.0, d));
      col = mix(col, cloudCol, cm * 0.85 * cloudVis);

      // Parallax hills (shapes in CSS px so they look the same at any DPR).
      float x = px.x / uDpr, y = px.y / uDpr;
      float G = uGround / uDpr, H = uRes.y / uDpr;
      float m = uMouse.x, par = uScroll;
      float aa = 1.2;
      if (uHills > 0.5) {
        float hf = G + H * 0.2 + 40.0 * sin(x * 0.0042 + 1.3 + m * 0.06) + 30.0 * fbm(vec2(x * 0.004, 1.0)) - par * 24.0;
        float hm = G + H * 0.1 + 32.0 * sin(x * 0.0062 + 4.0 + m * 0.12) + 22.0 * fbm(vec2(x * 0.008, 5.0)) - par * 50.0;
        float hn = G + max(14.0, H * 0.035) + 16.0 * sin(x * 0.009 + 0.5 + m * 0.2) + 10.0 * fbm(vec2(x * 0.015, 9.0)) - par * 85.0;
        col = mix(col, mix(farC, top, 0.22), smoothstep(aa, -aa, y - hf));
        col = mix(col, midC, smoothstep(aa, -aa, y - hm));
        col = mix(col, nearC, smoothstep(aa, -aa, y - hn));
      }
      float gr = smoothstep(aa, -aa, y - G);
      vec3 gcol = groundC * (0.93 + 0.09 * noise(vec2(x * 0.09, y * 0.35)));
      col = mix(col, gcol, gr);
      col = mix(col, groundC * 0.8, smoothstep(3.0, 0.0, abs(y - G + 1.5)) * 0.7);

      col += (hash(px + uTime) - 0.5) / 255.0;
      gl_FragColor = vec4(col, 1.0);
    }
  `;

  const skies = new Set();
  let last = performance.now();
  function loop(now) {
    const dt = Math.min((now - last) / 1000, 0.05);
    last = now;
    for (const s of skies) if (s.visible) s.frame(dt);
    requestAnimationFrame(loop);
  }
  requestAnimationFrame(loop);

  let mouse = [0, 0];
  window.addEventListener("pointermove", (e) => {
    mouse = [(e.clientX / window.innerWidth) * 2 - 1, (e.clientY / window.innerHeight) * 2 - 1];
  }, { passive: true });

  class Sky {
    constructor(canvas, opts = {}) {
      this.canvas = canvas;
      this.day = opts.day ?? 0;
      this.dayTarget = this.day;
      this.scroll = 0;
      this.shoot = opts.shoot ? 1 : 0;
      this.hills = opts.hills === false ? 0 : 1;
      this.groundFn = typeof opts.ground === "function" ? opts.ground : () => opts.ground ?? 100;
      this.time = Math.random() * 100;
      this.mouse = [0, 0];
      this.visible = true;
      this.dirty = true;
      const gl = canvas.getContext("webgl", { antialias: false, alpha: false, powerPreference: "low-power" });
      if (!gl || !this.setup(gl)) { canvas.classList.add("no-gl"); this.ok = false; return; }
      this.ok = true;
      this.resize();
      new ResizeObserver(() => this.resize()).observe(canvas);
      new IntersectionObserver((es) => { this.visible = es[0].isIntersecting; }, { rootMargin: "120px" }).observe(canvas);
      skies.add(this);
    }

    setup(gl) {
      const sh = (type, src) => {
        const s = gl.createShader(type);
        gl.shaderSource(s, src); gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) { console.warn(gl.getShaderInfoLog(s)); return null; }
        return s;
      };
      const vs = sh(gl.VERTEX_SHADER, VERT), fs = sh(gl.FRAGMENT_SHADER, FRAG);
      if (!vs || !fs) return false;
      const prog = gl.createProgram();
      gl.attachShader(prog, vs); gl.attachShader(prog, fs); gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) { console.warn(gl.getProgramInfoLog(prog)); return false; }
      gl.useProgram(prog);
      const buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      const loc = gl.getAttribLocation(prog, "aPos");
      gl.enableVertexAttribArray(loc);
      gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
      this.u = {};
      for (const n of ["uRes", "uTime", "uDay", "uScroll", "uGround", "uDpr", "uMouse", "uShoot", "uHills"]) this.u[n] = gl.getUniformLocation(prog, n);
      this.gl = gl;
      this.canvas.addEventListener("webglcontextlost", (e) => { e.preventDefault(); skies.delete(this); this.canvas.classList.add("no-gl"); });
      return true;
    }

    resize() {
      const r = this.canvas.getBoundingClientRect();
      this.dpr = Math.min(window.devicePixelRatio || 1, 1.5);
      this.w = Math.max(2, r.width); this.h = Math.max(2, r.height);
      this.canvas.width = Math.round(this.w * this.dpr);
      this.canvas.height = Math.round(this.h * this.dpr);
      this.ground = this.groundFn(this.w, this.h);
      this.gl.viewport(0, 0, this.canvas.width, this.canvas.height);
      this.dirty = true;
    }

    setDay(v, instant = false) {
      this.dayTarget = Math.min(1, Math.max(0, v));
      if (instant) this.day = this.dayTarget;
      this.dirty = true;
    }
    setScroll(v) { this.scroll = v; this.dirty = true; }

    frame(dt) {
      const still = reduceMotion.matches;
      if (still && !this.dirty && Math.abs(this.day - this.dayTarget) < 0.001) return;
      if (!still) this.time += dt;
      const k = still ? 1 : 1 - Math.exp(-6 * dt);
      this.day += (this.dayTarget - this.day) * k;
      this.mouse[0] += (mouse[0] - this.mouse[0]) * (still ? 0 : 1 - Math.exp(-3 * dt));
      const gl = this.gl, u = this.u;
      gl.uniform2f(u.uRes, this.canvas.width, this.canvas.height);
      gl.uniform1f(u.uTime, this.time);
      gl.uniform1f(u.uDay, this.day);
      gl.uniform1f(u.uScroll, this.scroll);
      gl.uniform1f(u.uGround, this.ground * this.dpr);
      gl.uniform1f(u.uDpr, this.dpr);
      gl.uniform2f(u.uMouse, this.mouse[0], this.mouse[1]);
      gl.uniform1f(u.uShoot, this.shoot);
      gl.uniform1f(u.uHills, this.hills);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      this.dirty = false;
    }
  }

  window.DummySky = { Sky };
})();
