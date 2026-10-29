/* annotatekit.com hero demo: demo.mp4 is AnnotateKit's own overlay code performing a scripted session
   in the Simulator (a reel app drives the real controller: draw, tap, type, send; the agent answers
   through the CLI), recorded with the black screen mask so its corners sit flush in the bezel. It is a
   video, so it looks the same in every browser and layout. Claude's terminal prints in step with it. */
(function () {
  "use strict";

  var mount = document.getElementById("demo");
  if (!mount) return;

  function line(cls, glyph, html) {
    return '<div class="ak-line ' + cls + '"><span class="ak-g">' + glyph + "</span>" + html + "</div>";
  }

  mount.innerHTML =
    '<div class="ak-demo" aria-hidden="true">' +
      '<div class="ak-mesh"><i></i><i></i><i></i><i></i></div>' +
      '<div class="ak-stage">' +
      '<div class="ak-phone"><div class="ak-screen">' +
        '<video class="ak-video" src="demo.mp4" poster="demo-poster.jpg" muted playsinline loop preload="auto"></video>' +
      "</div></div>" +
      '<div class="ak-term"><div class="ak-term-head"><i></i><i></i><i></i><span class="ak-term-title"><svg class="ak-claude" viewBox="0 0 24 24"><path fill="currentColor" d="m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"/></svg>Claude</span></div><div class="ak-term-body">' +
        line("", '<span class="ak-dim-t">&gt;</span>', "Apply my annotations as they come in") +
        line("ak-dim-t", '<span class="ak-live">⏺</span>', "Listening for notes from the app…") +
        line("ak-later ak-t-recv", '<span class="ak-c-blue">⏺</span>', '<span class="ak-b">2 pins</span> on 1 screen · iPhone 17 Pro') +
        line("ak-later ak-t-edit", '<span class="ak-c-green">⏺</span>', '<span class="ak-b">Edit</span> TodayView.swift') +
        line("ak-later ak-t-edit2 ak-dim-t", "", "⎿  Updated 2 lines") +
        line("ak-later ak-t-r1", '<span class="ak-c-green">⏺</span>', '<span class="ak-b">annotation_resolve</span> 1 <span class="ak-str">"title → .largeTitle"</span>') +
        line("ak-later ak-t-r2", '<span class="ak-c-green">⏺</span>', '<span class="ak-b">annotation_resolve</span> 2 <span class="ak-str">"button → accent"</span>') +
        line("ak-later ak-t-work ak-c-orange", '<span class="ak-star">✻</span>', "Working…") +
      "</div></div>" +
    "</div></div>";

  var root = mount.firstChild;
  function $(sel) { return root.querySelector(sel); }
  var stage = $(".ak-stage"), video = $(".ak-video"), term = $(".ak-term");

  // ---------- Layout: the stage has a fixed size and is scaled to the column ----------

  // Phones stack the terminal under the phone. From 1000px the demo fills the fixed preview pane:
  // the phone-only stage (260 x 528) is centered and scaled above a terminal docked full width
  // along the bottom at real pixel size, like an IDE's built-in terminal.
  var narrowQuery = window.matchMedia("(max-width: 479px)");
  var dockedQuery = window.matchMedia("(min-width: 1000px)");
  function layout() {
    var narrow = narrowQuery.matches, docked = dockedQuery.matches;
    root.classList.toggle("ak-narrow", narrow);
    root.classList.toggle("ak-docked", docked);
    var home = docked ? root : stage;
    if (term.parentNode !== home) home.appendChild(term);
    if (docked) {
      var aw = root.clientWidth, ah = root.clientHeight - term.offsetHeight;
      if (!aw || ah <= 0) return;
      var s = Math.min(aw / 300, ah / 568);
      root.style.setProperty("--ak-scale", String(s));
      root.style.setProperty("--ak-x", (aw - 260 * s) / 2 + "px");
      root.style.setProperty("--ak-y", (ah - 528 * s) / 2 + "px");
      return;
    }
    var w = root.clientWidth || mount.clientWidth;
    if (w) root.style.setProperty("--ak-scale", String(w / (narrow ? 340 : 560)));
  }
  layout();
  if ("ResizeObserver" in window) new ResizeObserver(layout).observe(root);
  else window.addEventListener("resize", layout);
  if (narrowQuery.addEventListener) {
    narrowQuery.addEventListener("change", layout);
    dockedQuery.addEventListener("change", layout);
  }

  // ---------- Terminal in step with the video ----------

  // When each line prints, in demo.mp4 seconds, read off the reel: send at 18.3, received 20.5,
  // working 21.3, pin 1 resolved 23.5, pin 2 at 24.3, done 25.8.
  var CUES = [
    [".ak-t-recv", 20.4], [".ak-t-work", 21.3], [".ak-t-edit", 21.6],
    [".ak-t-edit2", 21.9], [".ak-t-r1", 23.5], [".ak-t-r2", 24.3]
  ].map(function (c) { return [$(c[0]), c[1]]; });
  var WORK_DONE = 25.8;
  var work = $(".ak-t-work");

  function sync() {
    var t = video.currentTime;
    CUES.forEach(function (c) { c[0].classList.toggle("ak-on", t >= c[1]); });
    work.classList.toggle("ak-gone", t >= WORK_DONE);
  }
  function tick() {
    sync();
    if ("requestVideoFrameCallback" in video) video.requestVideoFrameCallback(tick);
  }
  if ("requestVideoFrameCallback" in video) video.requestVideoFrameCallback(tick);
  else video.addEventListener("timeupdate", sync);
  video.addEventListener("seeked", sync);

  // ---------- Play only while visible; reduced motion gets the finished frame ----------

  var reduceQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
  var inView = false;

  function update() {
    if (reduceQuery.matches) {
      video.pause();
      video.poster = "demo-still.jpg";
      video.removeAttribute("src");
      video.load();
      CUES.forEach(function (c) { c[0].classList.add("ak-on"); });
      work.classList.add("ak-gone");
      return;
    }
    if (!video.getAttribute("src")) { video.src = "demo.mp4"; video.poster = "demo-poster.jpg"; }
    var playing = inView && !document.hidden;
    root.classList.toggle("ak-paused", !playing);
    if (playing) {
      var p = video.play();
      if (p && p.catch) p.catch(function () {});
    } else {
      video.pause();
    }
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      inView = entries[entries.length - 1].isIntersecting;
      update();
    }, { threshold: 0.15 }).observe(mount);
  } else {
    inView = true;
  }
  document.addEventListener("visibilitychange", update);
  if (reduceQuery.addEventListener) reduceQuery.addEventListener("change", update);
  update();
})();
