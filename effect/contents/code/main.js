"use strict";

// plasma-dropdown-any-slide — KWin effect that animates show/hide ONLY for
// windows managed by the plasma-dropdown-any KWin script, instead of
// depending on a generic third-party effect (kwin4_effect_geometry_change)
// that animates every window's geometry change system-wide.
//
// Config (kwinrc, [Effect-plasma-dropdown-any-slide]):
//   ManagedClasses  comma-separated window classes to animate. Written by
//                   config-helper.sh on every save, kept in sync with the
//                   window script's slots + tile pairs.
//   Duration        animation length in ms (default 250).
//   AnimationCurve  easing curve, see CURVE_LIST below.
//
// Animation approach adapted from kwin4_effect_geometry_change
// (Peter Fajdiga, GPLv3): listen for windowFrameGeometryChanged and
// interpolate old→new geometry via animate() with a Translation+Scale
// pair. The only real difference is the gate — an include list (only OUR
// windows) instead of an exclude list (every window except a few).
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

// AnimationCurve choice INDEX (config/main.xml <choices>, 0-based, in
// declaration order) → QEasingCurve.Type. effect.readConfig() returns
// EITHER the numeric index as a string OR the choice name, inconsistently —
// confirmed via live testing (one round read back "1" for "Elastic", a
// later round read back the literal name for the same widget/entry type).
// resolveEnumIndex() below handles both. Index 0 matches the original
// hardcoded default (OutExpo).
// "Flip3D" isn't its own easing shape — it reuses Smooth's curve (OutExpo)
// and adds a Y-axis rotation on top (see onWindowFrameGeometryChanged).
const CURVE_NAMES = ["Smooth", "Elastic", "Bounce", "Back", "Linear", "Flip3D"];
const CURVE_LIST = [
    QEasingCurve.OutExpo,
    QEasingCurve.OutElastic,
    QEasingCurve.OutBounce,
    QEasingCurve.OutBack,
    QEasingCurve.Linear,
    QEasingCurve.OutExpo,
];

// Resolves an Enum-typed config value to its 0-based index, accepting
// either the choice name or a numeric index string (see note above).
function resolveEnumIndex(rawValue, names) {
    const byName = names.indexOf(rawValue);
    if (byName >= 0) return byName;
    const idx = parseInt(rawValue, 10);
    return (!isNaN(idx) && idx >= 0 && idx < names.length) ? idx : 0;
}

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
        const duration = effect.readConfig("Duration", 250);
        this.duration = animationTime(duration);

        const curveIndex = resolveEnumIndex(effect.readConfig("AnimationCurve", "Smooth"), CURVE_NAMES);
        this.curve = CURVE_LIST[curveIndex];
        this.rotateOnToggle = CURVE_NAMES[curveIndex] === "Flip3D";

        const raw = effect.readConfig("ManagedClasses", "");
        this.managedClasses = raw
            .split(",")
            .map(c => c.trim().toLowerCase())
            .filter(c => c.length > 0);

        console.log("[dropdown-slide effect] loaded config — duration=" +
            this.duration + "ms curve=" + (CURVE_NAMES[curveIndex] || "Smooth") +
            " managedClasses=[" + this.managedClasses.join(", ") + "]");
    }

    manage(window) {
        window.dropdownSlideData = { createdTime: Date.now(), animationInstances: 0 };
        window.windowFrameGeometryChanged.connect(
            this.onWindowFrameGeometryChanged.bind(this)
        );
    }

    isManaged(windowClass) {
        const parts = String(windowClass || "").toLowerCase().split(" ");
        return this.managedClasses.some(c => parts.includes(c));
    }

    onAnimationEnded(window) {
        if (!window.dropdownSlideData) return;
        window.dropdownSlideData.animationInstances--;
    }

    onWindowFrameGeometryChanged(window, oldGeometry) {
        if (!window.dropdownSlideData) return;
        if (this.managedClasses.length === 0) return;
        if (!this.isManaged(window.windowClass)) return;

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

        if (this.rotateOnToggle) {
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
            duration: this.duration,
            curve: this.curve,
            animations: animations,
        });
    }
}

new DropdownSlideEffect();
