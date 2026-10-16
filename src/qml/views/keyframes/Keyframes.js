/*
 * Copyright (c) 2017-2023 Meltytech, LLC
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

function trackHeight(isCurves) {
    return isCurves? (multitrack.trackHeight * 2) : (multitrack.trackHeight < 30)? 20 : 48
}

function scrollIfNeeded(center, continuous) {
    var x = producer.position * timeScale;
    if (!tracksFlickable) return;
    if (center) {
        if (x > tracksFlickable.contentX + tracksFlickable.width * 0.5)
            tracksFlickable.contentX = x - tracksFlickable.width * 0.5;
        else if (x < tracksFlickable.width * 0.5)
            tracksFlickable.contentX = 0;
        else if (x < tracksFlickable.contentX + tracksFlickable.width * 0.5)
            tracksFlickable.contentX = x - tracksFlickable.width * 0.5;
    } else if (tracksContainer.width > tracksFlickable.width) {
        if (continuous) {
            if (x > tracksFlickable.contentX + tracksFlickable.width - 50)
                tracksFlickable.contentX = x - tracksFlickable.width + 50;
            else if (x < 50)
                tracksFlickable.contentX = 0;
            else if (x < tracksFlickable.contentX + 50)
                tracksFlickable.contentX = x - 50;
        } else {
            // paginated
            var leftLimit = tracksFlickable.contentX + 50
            var pageCount = Math.floor((x - leftLimit)/(tracksFlickable.width - 100))
            tracksFlickable.contentX = Math.max(tracksFlickable.contentX + pageCount*(tracksFlickable.width - 100), 0);
        }
    }
}

function seekPreviousSimple() {
    var position = producer.position + producer.in
    if (position > filter.out)
        position = filter.out
    else if (position > filter.out - filter.animateOut)
        position = filter.out - filter.animateOut
    else if (position > filter.in + filter.animateIn)
        position = filter.in + filter.animateIn
    else if (position > filter.in)
        position = filter.in
    else
        position = 0
    producer.position = position - producer.in
}

function seekNextSimple() {
    var position = producer.position + producer.in
    if (position < filter.in)
        position = filter.in
    else if (position < filter.in + filter.animateIn)
        position = filter.in + filter.animateIn
    else if (position < filter.out - filter.animateOut)
        position = filter.out - filter.animateOut
    else if (position < filter.out)
        position = filter.out
    else
        position = producer.out
    producer.position = Math.min(position - producer.in, producer.duration - 1)
}

function clamp(x, minimum, maximum) {
    return Math.min(Math.max(x, minimum), maximum)
}

function scrollMax() {
    var maxWidth = Math.max(tracksFlickable.contentWidth - tracksFlickable.width + 14, 0)
    var maxHeight = Math.max(tracksFlickable.contentHeight - tracksFlickable.height + 14, 0)
    return Qt.point(maxWidth, maxHeight)
}

function onMouseWheel(wheel) {
    // Debut Pro (Premiere-style mouse wheel):
    //   wheel                      scroll through time (track pads scroll freely)
    //   Alt/Option + wheel         zoom (Ctrl/Cmd + wheel also zooms)
    //   Shift + wheel              track height
    //   Ctrl/Cmd + Shift + wheel   scroll tracks up/down
    var n
    const mods = wheel.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.ShiftModifier)
    // Some platforms turn a vertical wheel into horizontal deltas while Shift or Alt is held.
    const delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x
    if (mods === Qt.AltModifier || mods === Qt.ControlModifier) {
        adjustZoom(delta / 2000, wheel.x)
    } else if (mods === Qt.ShiftModifier) {
        multitrack.trackHeight = Math.max(10, multitrack.trackHeight + delta / 25)
    } else if (mods === (Qt.ControlModifier | Qt.ShiftModifier)) {
        n = Math.round(delta / 2)
        tracksFlickable.contentY = clamp(tracksFlickable.contentY - n, 0, scrollMax().y)
    } else if ((wheel.pixelDelta.x || wheel.pixelDelta.y) && mods === 0) {
        // Track pads provide both horizontal and vertical.
        let x = wheel.pixelDelta.x
        let y = wheel.pixelDelta.y
        if (!y || Math.abs(x) > 2)
            tracksFlickable.contentX = clamp(tracksFlickable.contentX - x, 0, scrollMax().x)
        tracksFlickable.contentY = clamp(tracksFlickable.contentY - y, 0, scrollMax().y)
    } else {
        n = Math.round(delta / 2)
        tracksFlickable.contentX = clamp(tracksFlickable.contentX - n, 0, scrollMax().x)
    }
}
