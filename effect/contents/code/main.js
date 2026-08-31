"use strict";

// plasma-dropdown-any-slide — KWin effect that animates show/hide ONLY for
// windows managed by the plasma-dropdown-any KWin script, instead of
// depending on a generic third-party effect (kwin4_effect_geometry_change)
// that animates every window's geometry change system-wide.
//
// Config (kwinrc, [Effect-plasma-dropdown-any-slide]):
//   ManagedClasses      "class:Style:DurationMs,class:Style:DurationMs,..."
//                       triples — both the animation style AND duration are
//                       chosen PER SLOT (or per tile pair) in the plasmoid,
//                       not globally here. Written by config-helper.sh on
//                       every save, kept in sync with the window script's
//                       slots and tile pairs.
//   TempSlotStyle       Fallback style for temporary slots (see below).
//   TempSlotDurationMs  Fallback duration for temporary slots (see below).
//
// Temporary slots (window script feature: a slot with no fixed class,
// bound at runtime to whichever app is focused when triggered) can't be
// listed in ManagedClasses above — their class isn't known until the
// window script binds one, and this effect has no way to learn that a
// posteriori. Instead, any window NOT in ManagedClasses that has
// skipSwitcher true at the moment its geometry changes is treated as one
// of ours anyway (the window script always sets it before moving a managed
// window) and animated with the single shared TempSlotStyle/
// TempSlotDurationMs pair instead of a per-class one.
//
// NOTE: this only checks skipSwitcher, not skipTaskbar/skipPager too, even
// though the window script sets all three — confirmed against KWin's
// EffectWindow (effect/effectwindow.h) that skipTaskbar/skipPager simply
// don't exist as EffectWindow properties (only on the window-script side's
// Window class), so referencing them here is always undefined/falsy and
// silently breaks the whole check. skipSwitcher is the only one of the
// three actually exposed to effects.
//
// Trade-off: temporary slots don't get per-slot style control like regular
// slots do, and in the unlikely case some unrelated window also has
// skipSwitcher set during its own geometry change, it would get animated
// too — narrower than the old animate-everything third-party effect this
// replaced, but not as scoped as the class list.
//
// Animation approach adapted from kwin4_effect_geometry_change
// (Peter Fajdiga, GPLv3): listen for windowFrameGeometryChanged and
// interpolate old→new geometry via animate() with a Translation+Scale
// pair. The real differences are the gate (an include list — only OUR
// windows — instead of an exclude list) and per-window style/duration
// lookup below.
//
// NOTE: callDBus is NOT available in the effect scripting context (only in
// window scripts) — confirmed by a ReferenceError while debugging this.
// Use console.log (visible via `journalctl -t kwin_wayland`) here instead.
//
// Tried and dropped, kept as notes for later:
// - "Zoom" mode (scale only, no translation): this plugin's hide/show only
//   ever changes a window's POSITION, never its size, so widthRatio/
//   heightRatio are always 1 and a scale-only animation is a visual no-op
//   for these windows specifically. Would need main.js's core hide/show
//   geometry logic to also shrink size, not just move off-screen.
// - Fade in/out (Effect.CrossFadePrevious) and forced blur-during-animation
//   (Effect.WindowForceBlurRole, matching the reference effect): both
//   implemented and confirmed reading their config correctly, but neither
//   produced a visible difference worth the extra config surface — our
//   windows don't change *content*, only position, so cross-fade gets
//   masked by the move; blur only matters with the separate Blur effect
//   also enabled, unconfirmed as worthwhile.
// - A literal fog/shader-based effect was discussed and declined — real
//   GLSL shader work with no reference implementation to build from, and
//   meaningfully higher risk (a broken shader can glitch or hang the
//   compositor, not just no-op like everything else tried here).

// Style name → QEasingCurve.Type. "Flip3D" isn't its own easing shape — it
// reuses Smooth's curve (OutExpo) and adds a Y-axis rotation on top (see
// onWindowFrameGeometryChanged).
const STYLE_NAMES = ["Smooth", "Elastic", "Bounce", "Back", "Linear", "Flip3D"];
const STYLE_CURVES = {
    Smooth:  QEasingCurve.OutExpo,
    Elastic: QEasingCurve.OutElastic,
    Bounce:  QEasingCurve.OutBounce,
    Back:    QEasingCurve.OutBack,
    Linear:  QEasingCurve.Linear,
    Flip3D:  QEasingCurve.OutExpo,
};

const DEFAULT_DURATION_MS = 250;

class DropdownSlideEffect {
    constructor() {
        effect.configChanged.connect(this.loadConfig.bind(this));
        effect.animationEnded.connect(this.onAnimationEnded.bind(this));

        const manageFn = this.manage.bind(this);
        effects.windowAdded.connect(manageFn);
        effects.stackingOrder.forEach(manageFn);

        this.loadConfig();
    }

    loadConfig() {
        // "class:Style:DurationMs" triples, one per managed window class.
        const raw = effect.readConfig("ManagedClasses", "");
        this.classConfig = new Map(); // cls → { style, duration }
        raw.split(",").forEach(entry => {
            const trimmed = entry.trim();
            if (!trimmed) return;
            const parts = trimmed.split(":");
            const cls   = (parts[0] || "").trim().toLowerCase();
            if (!cls) return;
            const rawStyle = (parts[1] || "").trim();
            const style    = STYLE_NAMES.includes(rawStyle) ? rawStyle : "Smooth";
            const rawMs    = parseInt(parts[2], 10);
            const duration = animationTime(!isNaN(rawMs) && rawMs > 0 ? rawMs : DEFAULT_DURATION_MS);
            this.classConfig.set(cls, { style, duration });
        });

        // Shared fallback for temporary slots — see header comment.
        const rawTempStyle = effect.readConfig("TempSlotStyle", "Smooth");
        this.tempSlotStyle = STYLE_NAMES.includes(rawTempStyle) ? rawTempStyle : "Smooth";
        const rawTempMs = parseInt(effect.readConfig("TempSlotDurationMs", DEFAULT_DURATION_MS), 10);
        this.tempSlotDuration = animationTime(!isNaN(rawTempMs) && rawTempMs > 0 ? rawTempMs : DEFAULT_DURATION_MS);

        console.log("[dropdown-slide effect] loaded config — managedClasses=[" +
            Array.from(this.classConfig.entries())
                .map(([cls, cfg]) => cls + ":" + cfg.style + ":" + cfg.duration + "ms")
                .join(", ") + "], tempSlotFallback=" + this.tempSlotStyle + ":" + this.tempSlotDuration + "ms");
    }

    manage(window) {
        window.dropdownSlideData = { createdTime: Date.now(), animationInstances: 0 };
        window.windowFrameGeometryChanged.connect(
            this.onWindowFrameGeometryChanged.bind(this)
        );
    }

    // Returns the matched class key from classConfig (window.windowClass is
    // a space-separated "resourceClass resourceName"-style string), or null.
    matchClass(windowClass) {
        const parts = String(windowClass || "").toLowerCase().split(" ");
        for (const part of parts) {
            if (this.classConfig.has(part)) return part;
        }
        return null;
    }

    onAnimationEnded(window) {
        if (!window.dropdownSlideData) return;
        window.dropdownSlideData.animationInstances--;
    }

    onWindowFrameGeometryChanged(window, oldGeometry) {
        if (!window.dropdownSlideData) return;

        let style, duration;
        const matchedClass = this.matchClass(window.windowClass);
        if (matchedClass) {
            ({ style, duration } = this.classConfig.get(matchedClass));
        } else if (window.skipSwitcher) {
            // Not a pre-registered class — likely a temporary slot's bound
            // window (see header comment). Use the shared fallback instead
            // of leaving it unanimated.
            style = this.tempSlotStyle;
            duration = this.tempSlotDuration;
        } else {
            return; // not one of ours
        }

        // Skip the initial placement right after window creation.
        const windowAgeMs = Date.now() - window.dropdownSlideData.createdTime;
        if (windowAgeMs < 10) return;

        const newGeometry = window.geometry;
        const xDelta = newGeometry.x - oldGeometry.x;
        const yDelta = newGeometry.y - oldGeometry.y;
        const widthDelta = newGeometry.width - oldGeometry.width;
        const heightDelta = newGeometry.height - oldGeometry.height;
        if (xDelta === 0 && yDelta === 0 && widthDelta === 0 && heightDelta === 0) {
            return;
        }

        const widthRatio  = oldGeometry.width  / newGeometry.width;
        const heightRatio = oldGeometry.height / newGeometry.height;

        const animations = [
            {
                type: Effect.Translation,
                from: {
                    value1: -xDelta - widthDelta / 2,
                    value2: -yDelta - heightDelta / 2,
                },
                to: { value1: 0, value2: 0 },
            },
            {
                type: Effect.Scale,
                from: { value1: widthRatio, value2: heightRatio },
                to: { value1: 1, value2: 1 },
            },
        ];

        if (style === "Flip3D") {
            animations.push({
                type: Effect.Rotation,
                axis: Effect.YAxis,
                from: 75,
                to: 0,
            });
        }

        window.dropdownSlideData.animationInstances += animations.length;

        animate({
            window: window,
            duration: duration,
            curve: STYLE_CURVES[style] || STYLE_CURVES.Smooth,
            animations: animations,
        });
    }
}

new DropdownSlideEffect();
