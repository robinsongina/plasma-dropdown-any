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
//
// Animation approach adapted from kwin4_effect_geometry_change
// (Peter Fajdiga, GPLv3): listen for windowFrameGeometryChanged and
// interpolate old→new geometry via a Translation+Scale pair. The only
// real difference is the gate — an include list (only OUR windows)
// instead of an exclude list (every window except a few).

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

        const raw = effect.readConfig("ManagedClasses", "");
        this.managedClasses = raw
            .split(",")
            .map(c => c.trim().toLowerCase())
            .filter(c => c.length > 0);
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

        window.dropdownSlideData.animationInstances += animations.length;

        animate({
            window: window,
            duration: this.duration,
            curve: QEasingCurve.OutExpo,
            animations: animations,
        });
    }
}

new DropdownSlideEffect();
