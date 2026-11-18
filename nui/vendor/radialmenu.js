/*
 * Radial menu UI for gsc_kasippu_system.
 *
 * Copied from EZ-Scripts/ez_radialmenu, html/js/RadialMenu.js
 *   https://github.com/EZ-Scripts/ez_radialmenu  (credits the qbcore-framework qb-radialmenu project)
 * Licence: GNU General Public License v3.0 - see LICENSE-radialmenu.txt in this folder.
 * MODIFIED for gsc_kasippu_system (2026-11-13); every change is marked [gsc]:
 *   - close() posts radialClose with fetch instead of jQuery $.post(closeRadial)
 *   - image path points at nui/assets/img/radial/
 *   - document listeners are kept and removed again by the new destroy()
 *   - an unknown icon falls back to "circle-question" (the original name is missing from icos)
 *   - [2026-11-18] `icos` trimmed from all 1,385 Font Awesome icons to the 71 this resource can name (1.1 MB -> 66 KB)
 *
 * Icons: the `icos` table holds Font Awesome Free 6 icon paths
 *   (https://fontawesome.com - icons licensed CC BY 4.0, https://fontawesome.com/license/free).
 *   New icon for a menu wedge? An unknown name shows "circle-question". Copy its line
 *   (`"name": [w, h, [aliases], "unicode", "svg path"],`) from the original ez_radialmenu RadialMenu.js into `icos`.
 */
"use strict";

var DEFAULT_SIZE = 150;
var MIN_SECTORS = 3;

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
function RadialMenu(params) {
    var self = this;

    self.parent = params.parent || [];

    self.size = params.size || DEFAULT_SIZE;
    self.onClick = params.onClick || null;
    self.menuItems = params.menuItems
        ? params.menuItems
        : [
              { id: "one", title: "One" },
              { id: "two", title: "Two" },
          ];

    self.radius = 55;
    self.innerRadius = 18;
    self.sectorSpace = 3.5;
    self.sectorCount = Math.max(self.menuItems.length, MIN_SECTORS);
    self.closeOnClick = params.closeOnClick !== undefined ? !!params.closeOnClick : false;

    self.scale = 1;
    self.holder = null;
    self.parentMenu = [];
    self.parentItems = [];
    self.levelItems = null;

    self.createHolder();
    //self.addIconSymbols();

    self.currentMenu = null;
    // [gsc] keep the bound handlers so destroy() can remove them (the original added a new pair on every open)
    self._onWheel = self.onMouseWheel.bind(self);
    self._onKeyDown = self.onKeyDown.bind(self);
    document.addEventListener("wheel", self._onWheel);
    document.addEventListener("keydown", self._onKeyDown);
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.open = function () {
    var self = this;
    if (!self.currentMenu) {
        self.currentMenu = self.createMenu("menu inner", self.menuItems);
        self.holder.appendChild(self.currentMenu);

        RadialMenu.nextTick(function () {
            self.currentMenu.setAttribute("class", "menu");
        });
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// [gsc] added: remove this menu's document listeners and its holder, so a fresh menu can be built next time
RadialMenu.prototype.destroy = function () {
    var self = this;
    document.removeEventListener("wheel", self._onWheel);
    document.removeEventListener("keydown", self._onKeyDown);
    if (self.holder && self.holder.parentNode) self.holder.parentNode.removeChild(self.holder);
    self.currentMenu = null;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.close = function (bool) {
    var self = this;

    if (self.currentMenu) {
        // [gsc] no jQuery in this NUI: tell the Lua side with fetch
        fetch(`https://${GetParentResourceName()}/radialClose`, {
            method: "POST",
            headers: { "Content-Type": "application/json; charset=UTF-8" },
            body: JSON.stringify({ delay: !!bool }),
        }).catch(function () {});
        var parentMenu;
        while ((parentMenu = self.parentMenu.pop())) {
            parentMenu.remove();
        }
        self.parentItems = [];

        RadialMenu.setClassAndWaitForTransition(self.currentMenu, "menu inner").then(function () {
            if (self.currentMenu != null) {
                self.currentMenu.remove();
                self.currentMenu = null;
            }
        });
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.getParentMenu = function () {
    var self = this;
    if (self.parentMenu.length > 0) {
        return self.parentMenu[self.parentMenu.length - 1];
    } else {
        return null;
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createHolder = function () {
    var self = this;

    self.holder = document.createElement("div");
    self.holder.className = "menuHolder";
    self.holder.style.width = self.size + "px";
    self.holder.style.height = self.size + "px";

    self.parent.appendChild(self.holder);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.showNestedMenu = function (item) {
    var self = this;
    self.parentMenu.push(self.currentMenu);
    self.parentItems.push(self.levelItems);
    self.currentMenu = self.createMenu("menu inner", item.items, true);
    self.holder.appendChild(self.currentMenu);

    // wait DOM commands to apply and then set class to allow transition to take effect
    RadialMenu.nextTick(function () {
        self.getParentMenu().setAttribute("class", "menu outer");
        self.currentMenu.setAttribute("class", "menu");
        self.onClick(item);
    });
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.returnToParentMenu = function () {
    var self = this;
    // [gsc] one step back at a time: a second Esc during the fade popped the parent ring too and left no ring
    if (self._moving) return;
    self._moving = true;
    self.getParentMenu().setAttribute("class", "menu");
    RadialMenu.setClassAndWaitForTransition(self.currentMenu, "menu inner").then(function () {
        if (self.currentMenu) self.currentMenu.remove();
        self.currentMenu = self.parentMenu.pop() || null;
        self.levelItems = self.parentItems.pop();
        self._moving = false;
    });
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.handleClick = function (index) {
    var self = this;

    var selectedIndex = self.getSelectedIndex();
    if (index !== undefined) {
        selectedIndex = index - 1;
    }
    if (selectedIndex >= 0) {
        var item = self.levelItems[selectedIndex];
        if (self.levelItems[selectedIndex] != null) {
            if (item.items) {
                self.showNestedMenu(item);
            } else {
                if (self.onClick) {
                    self.onClick(item);
                }
            }
        }
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.handleCenterClick = function () {
    var self = this;
    if (self._moving) return; // [gsc] a ring is still fading back
    if (self.parentItems.length > 0) {
        self.returnToParentMenu();
    } else {
        self.close();
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createCenter = function (svg, title, icon, size) {
    var self = this;
    size = size || 8;
    var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    g.setAttribute("class", "center");

    var centerCircle = self.createCircle(0, 0, self.innerRadius - self.sectorSpace);
    g.appendChild(centerCircle);
    if (text) {
        var text = self.createText(0, 0, title);
        g.appendChild(text);
    }

    if (icon) {
        var use = self.createUseTag(0, 0, icon, g, true);
        use.setAttribute("width", size);
        use.setAttribute("height", size);
        use.setAttribute("transform", "translate(-" + RadialMenu.numberToString(size / 2) + ",-" + RadialMenu.numberToString(size / 2) + ")");
        g.appendChild(use);
    }

    svg.appendChild(g);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.getIndexOffset = function () {
    var self = this;
    if (self.levelItems.length < self.sectorCount) {
        switch (self.levelItems.length) {
            case 1:
                return -2;
            case 2:
                return -2;
            case 3:
                return -2;
            default:
                return -1;
        }
    } else {
        return -1;
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createMenu = function (classValue, levelItems, nested) {
    var self = this;

    var menuItems = 0;

    self.levelItems = levelItems;

    self.sectorCount = Math.max(self.levelItems.length, MIN_SECTORS);
    self.scale = self.calcScale();

    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", classValue);
    svg.setAttribute("viewBox", "-50 -50 100 100");
    svg.setAttribute("width", self.size);
    svg.setAttribute("height", self.size);

    var angleStep = 360 / self.sectorCount;
    var angleShift;

    for (i = 1; i < self.levelItems.length; i++) {
        menuItems = i;
    }

    if (menuItems + 1 == 1) {
        angleShift = angleStep / 2 + 241;
    } else if (menuItems + 1 == 2) {
        angleShift = angleStep / 2 + 241;
    } else if (menuItems + 1 == 3) {
        angleShift = angleStep / 2 + 241;
    } else if (menuItems + 1 == 4) {
        angleShift = angleStep / 2 + 136;
    } else if (menuItems + 1 == 5) {
        angleShift = angleStep / 2 + 145;
    } else if (menuItems + 1 == 6) {
        angleShift = angleStep / 2 + 241;
    } else if (menuItems + 1 == 7) {
        angleShift = angleStep / 2 + 241;
    } else {
        angleShift = angleStep / 2 + 241;
    }

    var indexOffset = self.getIndexOffset();

    for (var i = 0; i < self.sectorCount; ++i) {
        var startAngle = angleShift + angleStep * i;
        var endAngle = angleShift + angleStep * (i + 0.99);

        var itemIndex = RadialMenu.resolveLoopIndex(self.sectorCount - i + indexOffset, self.sectorCount);
        var item;
        if (itemIndex >= 0 && itemIndex < self.levelItems.length) {
            item = self.levelItems[itemIndex];
        } else {
            item = null;
        }

        self.appendSectorPath(startAngle, endAngle, svg, item, itemIndex);
    }

    if (nested) {
        self.createCenter(svg, "Close", "arrow-left", 10);
    } else {
        self.createCenter(svg, "Close", "circle-xmark", 10);
    }

    svg.addEventListener("mousedown", function (event) {
        var className = event.target.parentNode.getAttribute("class").split(" ")[0];
        switch (className) {
            case "sector":
                var index = parseInt(event.target.parentNode.getAttribute("data-index"));
                if (!isNaN(index)) {
                    self.setSelectedIndex(index);
                }
                break;
            default:
        }
    });

    svg.addEventListener("click", function (event) {
        var className = event.target.parentNode.getAttribute("class").split(" ")[0];
        switch (className) {
            case "sector":
                self.handleClick();
                break;
            case "center":
                self.handleCenterClick();
                break;
            default:
        }
    });
    return svg;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.selectDelta = function (indexDelta) {
    var self = this;
    var selectedIndex = self.getSelectedIndex();
    if (selectedIndex < 0) {
        selectedIndex = 0;
    }
    selectedIndex += indexDelta;

    if (selectedIndex < 0) {
        selectedIndex = self.levelItems.length + selectedIndex;
    } else if (selectedIndex >= self.levelItems.length) {
        selectedIndex -= self.levelItems.length;
    }
    self.setSelectedIndex(selectedIndex);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.onKeyDown = function (event) {
    var self = this;
    if (self.currentMenu) {
        switch (event.key) {
            case "Escape":
            case "Backspace":
                self.handleCenterClick();
                event.preventDefault();
                break;
            case "1":
            case "2":
            case "3":
            case "4":
            case "5":
            case "6":
            case "7":
            case "8":
            case "9":
                var PressedKey = parseInt(event.key);
                self.handleClick(PressedKey);
                break;
        }
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.onMouseWheel = function (event) {
    var self = this;
    if (self.currentMenu) {
        var delta = -event.deltaY;

        if (delta > 0) {
            self.selectDelta(1);
        } else {
            self.selectDelta(-1);
        }
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.getSelectedNode = function () {
    var self = this;
    var items = self.currentMenu.getElementsByClassName("selected");
    if (items.length > 0) {
        return items[0];
    } else {
        return null;
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.getSelectedIndex = function () {
    var self = this;
    var selectedNode = self.getSelectedNode();
    if (selectedNode) {
        return parseInt(selectedNode.getAttribute("data-index"));
    } else {
        return -1;
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.setSelectedIndex = function (index) {
    var self = this;
    if (index >= 0 && index < self.levelItems.length) {
        var items = self.currentMenu.querySelectorAll('g[data-index="' + index + '"]');
        if (items.length > 0) {
            var itemToSelect = items[0];
            var selectedNode = self.getSelectedNode();
            if (selectedNode) {
                selectedNode.setAttribute("class", "sector");
            }
            itemToSelect.setAttribute("class", "sector selected");
        }
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createUseTag = function (x, y, link, parent, center) {
    if (!icos[link]) {
        console.error(`Icon "${link}" could not be found, replacing a question mark.`);
        link = "circle-question"; // [gsc] the original fell back to "question-circle", which is not in icos (TypeError)
    }
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    svg.setAttribute("x", RadialMenu.numberToString(x) - 5);
    svg.setAttribute("y", RadialMenu.numberToString(y) - 8);
    if (center) {
        svg.setAttribute("y", RadialMenu.numberToString(y) - 5);
    }
    svg.setAttribute("width", "10");
    svg.setAttribute("height", "10");
    svg.setAttribute("id", link);
    svg.setAttribute("fill", "white");
    svg.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    svg.setAttribute("role", "img");
    svg.setAttribute("viewBox", `0 0 ${icos[link][0]} ${icos[link][1]}`);

    svg.setAttribute("data-id", parent.getAttribute("data-id"));
    svg.setAttribute("data-index", parent.getAttribute("data-index"));
    svg.setAttribute("class", parent.getAttribute("class"));

    path.setAttribute("d", icos[link][4]);
    svg.appendChild(path);

    return svg;
};

RadialMenu.prototype.createImage = function (x, y, href, center) {
    var image = document.createElementNS("http://www.w3.org/2000/svg", "image");
    image.setAttribute("x", RadialMenu.numberToString(x)-3);
    image.setAttribute("y", RadialMenu.numberToString(y) - 5);
    if (center) {
        image.setAttribute("y", RadialMenu.numberToString(y) - 5);
    }
    image.setAttribute("width", "15");
    image.setAttributeNS("http://www.w3.org/1999/xlink", "href", "assets/img/radial/" + href /* [gsc] this resource's own image folder (nui/assets/img/radial/, relative to index.html) */); // Sets the image source
    image.setAttribute("preserveAspectRatio", "xMidYMid meet"); // Ensures the aspect ratio is preserved
    return image;
};


////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.appendSectorPath = function (startAngleDeg, endAngleDeg, svg, item, index) {
    var self = this;

    var centerPoint = self.getSectorCenter(startAngleDeg, endAngleDeg);
    var translate = {
        x: RadialMenu.numberToString((1 - self.scale) * centerPoint.x),
        y: RadialMenu.numberToString((1 - self.scale) * centerPoint.y),
    };

    var g = document.createElementNS("http://www.w3.org/2000/svg", "g");
    g.setAttribute("transform", "translate(" + translate.x + " ," + translate.y + ") scale(" + self.scale + ")");

    var path = document.createElementNS("http://www.w3.org/2000/svg", "path");
    path.setAttribute("d", self.createSectorCmds(startAngleDeg, endAngleDeg));
    g.appendChild(path);

    if (item) {
        g.setAttribute("class", "sector");
        if (index == 0) {
            g.setAttribute("class", "sector selected");
        }
        g.setAttribute("data-id", item.id);
        g.setAttribute("data-index", index);

        if (item.title) {
            var text = self.createText(centerPoint.x, centerPoint.y, item.title);
            if (item.icon || item.image) {
                text.setAttribute("transform", "translate(0,8)");
            } else {
                text.setAttribute("transform", "translate(0,2)");
            }

            g.appendChild(text);
        }

        if (item.icon) {
            var use = self.createUseTag(centerPoint.x, centerPoint.y, item.icon, g);
            if (item.title) {
                use.setAttribute("transform", "translate(-5,-8)");
            } else {
                use.setAttribute("transform", "translate(-5,-5)");
            }
            g.appendChild(use);
        } else if (item.image) {
            var image = self.createImage(centerPoint.x, centerPoint.y, item.image);
            if (item.title) {
                image.setAttribute("transform", "translate(-5,-8)");
            } else {
                image.setAttribute("transform", "translate(-5,-5)");
            }
            g.appendChild(image);
        }
    } else {
        g.setAttribute("class", "dummy");
    }

    svg.appendChild(g);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createSectorCmds = function (startAngleDeg, endAngleDeg) {
    var self = this;

    var initPoint = RadialMenu.getDegreePos(startAngleDeg, self.radius);
    var path = "M" + RadialMenu.pointToString(initPoint);

    var radiusAfterScale = self.radius * (1 / self.scale);
    path += "A" + radiusAfterScale + " " + radiusAfterScale + " 0 0 0" + RadialMenu.pointToString(RadialMenu.getDegreePos(endAngleDeg, self.radius));
    path += "L" + RadialMenu.pointToString(RadialMenu.getDegreePos(endAngleDeg, self.innerRadius));

    var radiusDiff = self.radius - self.innerRadius;
    var radiusDelta = (radiusDiff - radiusDiff * self.scale) / 2;
    var innerRadius = (self.innerRadius + radiusDelta) * (1 / self.scale);
    path += "A" + innerRadius + " " + innerRadius + " 0 0 1 " + RadialMenu.pointToString(RadialMenu.getDegreePos(startAngleDeg, self.innerRadius));
    path += "Z";

    return path;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createText = function (x, y, title) {
    var self = this;
    var text = document.createElementNS("http://www.w3.org/2000/svg", "text");
    text.setAttribute("text-anchor", "middle");
    text.setAttribute("x", RadialMenu.numberToString(x));
    text.setAttribute("y", RadialMenu.numberToString(y));
    text.setAttribute("font-size", ".85vh");
    text.setAttribute("font-family", "Lato");
    text.innerHTML = title;
    return text;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.createCircle = function (x, y, r) {
    var circle = document.createElementNS("http://www.w3.org/2000/svg", "circle");
    circle.setAttribute("cx", RadialMenu.numberToString(x));
    circle.setAttribute("cy", RadialMenu.numberToString(y));
    circle.setAttribute("r", r);
    return circle;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.calcScale = function () {
    var self = this;
    var totalSpace = self.sectorSpace * self.sectorCount;
    var circleLength = Math.PI * 2 * self.radius;
    var radiusDelta = self.radius - (circleLength - totalSpace) / (Math.PI * 2);
    return (self.radius - radiusDelta) / self.radius;
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.getSectorCenter = function (startAngleDeg, endAngleDeg) {
    var self = this;
    return RadialMenu.getDegreePos((startAngleDeg + endAngleDeg) / 2, self.innerRadius + (self.radius - self.innerRadius) / 2);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.prototype.addIconSymbols = function () {
    var self = this;
    var svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", "icons");

    // return
    var returnSymbol = document.createElementNS("http://www.w3.org/2000/svg", "symbol");
    returnSymbol.setAttribute("id", "return");
    returnSymbol.setAttribute("viewBox", "0 0 489.394 489.394");
    var returnPath = document.createElementNS("http://www.w3.org/2000/svg", "path");
    returnPath.setAttribute("d", "M375.789,92.867H166.864l17.507-42.795c3.724-9.132,1-19.574-6.691-25.744c-7.701-6.166-18.538-6.508-26.639-0.879" + "L9.574,121.71c-6.197,4.304-9.795,11.457-9.563,18.995c0.231,7.533,4.261,14.446,10.71,18.359l147.925,89.823" + "c8.417,5.108,19.18,4.093,26.481-2.499c7.312-6.591,9.427-17.312,5.219-26.202l-19.443-41.132h204.886" + "c15.119,0,27.418,12.536,27.418,27.654v149.852c0,15.118-12.299,27.19-27.418,27.19h-226.74c-20.226,0-36.623,16.396-36.623,36.622" + "v12.942c0,20.228,16.397,36.624,36.623,36.624h226.74c62.642,0,113.604-50.732,113.604-113.379V206.709" + "C489.395,144.062,438.431,92.867,375.789,92.867z");
    returnSymbol.appendChild(returnPath);
    svg.appendChild(returnSymbol);

    var closeSymbol = document.createElementNS("http://www.w3.org/2000/svg", "symbol");
    closeSymbol.setAttribute("id", "close");
    closeSymbol.setAttribute("viewBox", "0 0 41.756 41.756");

    var closePath = document.createElementNS("http://www.w3.org/2000/svg", "path");
    closePath.setAttribute("d", "M27.948,20.878L40.291,8.536c1.953-1.953,1.953-5.119,0-7.071c-1.951-1.952-5.119-1.952-7.07,0L20.878,13.809L8.535,1.465" + "c-1.951-1.952-5.119-1.952-7.07,0c-1.953,1.953-1.953,5.119,0,7.071l12.342,12.342L1.465,33.22c-1.953,1.953-1.953,5.119,0,7.071" + "C2.44,41.268,3.721,41.755,5,41.755c1.278,0,2.56-0.487,3.535-1.464l12.343-12.342l12.343,12.343" + "c0.976,0.977,2.256,1.464,3.535,1.464s2.56-0.487,3.535-1.464c1.953-1.953,1.953-5.119,0-7.071L27.948,20.878z");
    closeSymbol.appendChild(closePath);
    svg.appendChild(closeSymbol);

    self.holder.appendChild(svg);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.getDegreePos = function (angleDeg, length) {
    return {
        x: Math.sin(RadialMenu.degToRad(angleDeg)) * length,
        y: Math.cos(RadialMenu.degToRad(angleDeg)) * length,
    };
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.pointToString = function (point) {
    return RadialMenu.numberToString(point.x) + " " + RadialMenu.numberToString(point.y);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.numberToString = function (n) {
    if (Number.isInteger(n)) {
        return n.toString();
    } else if (n) {
        var r = (+n).toFixed(5);
        if (r.match(/\./)) {
            r = r.replace(/\.?0+$/, "");
        }
        return r;
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.resolveLoopIndex = function (index, length) {
    if (index < 0) {
        index = length + index;
    }
    if (index >= length) {
        index = index - length;
    }
    if (index < length) {
        return index;
    } else {
        return null;
    }
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.degToRad = function (deg) {
    return deg * (Math.PI / 180);
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.setClassAndWaitForTransition = function (node, newClass) {
    return new Promise(function (resolve) {
        var done = false;
        function finish() {
            if (done) return;
            done = true;
            node.removeEventListener("transitionend", handler);
            resolve();
        }
        function handler(event) {
            if (event.target == node && event.propertyName == "visibility") finish();
        }
        node.addEventListener("transitionend", handler);
        node.setAttribute("class", newClass);
        setTimeout(finish, 450); // [gsc] no transitionend (hidden page, paused animations): go on anyway
    });
};

////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
RadialMenu.nextTick = function (fn) {
    setTimeout(fn, 10);
};

const icos = {
    0: [320, 512, [], "30", "M160 32.01c-88.37 0-160 71.63-160 160v127.1c0 88.37 71.63 160 160 160s160-71.63 160-160V192C320 103.6 248.4 32.01 160 32.01zM256 320c0 52.93-43.06 96-96 96c-52.93 0-96-43.07-96-96V192c0-52.94 43.07-96 96-96c52.94 0 96 43.06 96 96V320z"],
    1: [256, 512, [], "31", "M256 448c0 17.67-14.33 32-32 32H32c-17.67 0-32-14.33-32-32s14.33-32 32-32h64V123.8L49.75 154.6C35.02 164.5 15.19 160.4 5.375 145.8C-4.422 131.1-.4531 111.2 14.25 101.4l96-64c9.828-6.547 22.45-7.187 32.84-1.594C153.5 41.37 160 52.22 160 64.01v352h64C241.7 416 256 430.3 256 448z"],
    4: [384, 512, [], "34", "M384 334.2c0 17.67-14.33 32-32 32h-32v81.78c0 17.67-14.33 32-32 32s-32-14.33-32-32v-81.78H32c-10.97 0-21.17-5.625-27.05-14.89c-5.859-9.266-6.562-20.89-1.875-30.81l128-270.2C138.6 34.33 157.8 27.56 173.7 35.09c15.97 7.562 22.78 26.66 15.22 42.63L82.56 302.2H256V160c0-17.67 14.33-32 32-32s32 14.33 32 32v142.2h32C369.7 302.2 384 316.6 384 334.2z"],
    6: [320, 512, [], "36", "M167.7 160.8l64.65-76.06c11.47-13.45 9.812-33.66-3.656-45.09C222.7 34.51 215.3 32.01 208 32.01c-9.062 0-18.06 3.833-24.38 11.29C38.07 214.5 0 245.5 0 320c0 88.22 71.78 160 160 160s160-71.78 160-160C320 234.4 252.3 164.9 167.7 160.8zM160 416c-52.94 0-96-43.06-96-96s43.06-95.1 96-95.1s96 43.06 96 95.1S212.9 416 160 416z"],
    9: [320, 512, [], "39", "M160 32.01c-88.22 0-160 71.78-160 160c0 85.57 67.71 155.1 152.3 159.2l-64.65 76.06c-11.47 13.45-9.812 33.66 3.656 45.09c6 5.125 13.38 7.62 20.72 7.62c9.062 0 18.06-3.823 24.38-11.28C281.9 297.5 320 266.6 320 192C320 103.8 248.2 32.01 160 32.01zM160 288c-52.94 0-96-43.06-96-95.1s43.06-96 96-96s96 43.06 96 96S212.9 288 160 288z"],
    "arrow-down": [384, 512, [8595], "f063", "M374.6 310.6l-160 160C208.4 476.9 200.2 480 192 480s-16.38-3.125-22.62-9.375l-160-160c-12.5-12.5-12.5-32.75 0-45.25s32.75-12.5 45.25 0L160 370.8V64c0-17.69 14.33-31.1 31.1-31.1S224 46.31 224 64v306.8l105.4-105.4c12.5-12.5 32.75-12.5 45.25 0S387.1 298.1 374.6 310.6z"],
    b: [320, 512, [98], "42", "M257.1 242.4C276.1 220.1 288 191.6 288 160c0-70.58-57.42-128-128-128H32c-17.67 0-32 14.33-32 32v384c0 17.67 14.33 32 32 32l160-.0049c70.58 0 128-57.42 128-128C320 305.3 294.6 264.8 257.1 242.4zM64 96.01h96c35.3 0 64 28.7 64 64s-28.7 64-64 64H64V96.01zM192 416H64v-128h128c35.3 0 64 28.7 64 64S227.3 416 192 416z"],
    ban: [512, 512, [128683, "cancel"], "f05e", "M512 256C512 397.4 397.4 512 256 512C114.6 512 0 397.4 0 256C0 114.6 114.6 0 256 0C397.4 0 512 114.6 512 256zM99.5 144.8C77.15 176.1 64 214.5 64 256C64 362 149.1 448 256 448C297.5 448 335.9 434.9 367.2 412.5L99.5 144.8zM448 256C448 149.1 362 64 256 64C214.5 64 176.1 77.15 144.8 99.5L412.5 367.2C434.9 335.9 448 297.5 448 256V256z"],
    bold: [384, 512, [], "f032", "M321.1 242.4C340.1 220.1 352 191.6 352 160c0-70.59-57.42-128-128-128L32 32.01c-17.67 0-32 14.31-32 32s14.33 32 32 32h16v320H32c-17.67 0-32 14.31-32 32s14.33 32 32 32h224c70.58 0 128-57.41 128-128C384 305.3 358.6 264.8 321.1 242.4zM112 96.01H224c35.3 0 64 28.72 64 64s-28.7 64-64 64H112V96.01zM256 416H112v-128H256c35.3 0 64 28.71 64 63.1S291.3 416 256 416z"],
    book: [448, 512, [128212], "f02d", "M448 336v-288C448 21.49 426.5 0 400 0H96C42.98 0 0 42.98 0 96v320c0 53.02 42.98 96 96 96h320c17.67 0 32-14.33 32-31.1c0-11.72-6.607-21.52-16-27.1v-81.36C441.8 362.8 448 350.2 448 336zM143.1 128h192C344.8 128 352 135.2 352 144C352 152.8 344.8 160 336 160H143.1C135.2 160 128 152.8 128 144C128 135.2 135.2 128 143.1 128zM143.1 192h192C344.8 192 352 199.2 352 208C352 216.8 344.8 224 336 224H143.1C135.2 224 128 216.8 128 208C128 199.2 135.2 192 143.1 192zM384 448H96c-17.67 0-32-14.33-32-32c0-17.67 14.33-32 32-32h288V448z"],
    box: [448, 512, [128230], "f466", "M50.73 58.53C58.86 42.27 75.48 32 93.67 32H208V160H0L50.73 58.53zM240 160V32H354.3C372.5 32 389.1 42.27 397.3 58.53L448 160H240zM448 416C448 451.3 419.3 480 384 480H64C28.65 480 0 451.3 0 416V192H448V416z"],
    "box-open": [640, 512, [], "f49e", "M75.23 33.4L320 63.1L564.8 33.4C571.5 32.56 578 36.06 581.1 42.12L622.8 125.5C631.7 143.4 622.2 165.1 602.9 170.6L439.6 217.3C425.7 221.2 410.8 215.4 403.4 202.1L320 63.1L236.6 202.1C229.2 215.4 214.3 221.2 200.4 217.3L37.07 170.6C17.81 165.1 8.283 143.4 17.24 125.5L58.94 42.12C61.97 36.06 68.5 32.56 75.23 33.4H75.23zM321.1 128L375.9 219.4C390.8 244.2 420.5 255.1 448.4 248L576 211.6V378.5C576 400.5 561 419.7 539.6 425.1L335.5 476.1C325.3 478.7 314.7 478.7 304.5 476.1L100.4 425.1C78.99 419.7 64 400.5 64 378.5V211.6L191.6 248C219.5 255.1 249.2 244.2 264.1 219.4L318.9 128H321.1z"],
    "boxes-stacked": [576, 512, [62625, "boxes", "boxes-alt"], "f468", "M160 48C160 21.49 181.5 0 208 0H256V80C256 88.84 263.2 96 272 96H304C312.8 96 320 88.84 320 80V0H368C394.5 0 416 21.49 416 48V176C416 202.5 394.5 224 368 224H208C181.5 224 160 202.5 160 176V48zM96 288V368C96 376.8 103.2 384 112 384H144C152.8 384 160 376.8 160 368V288H208C234.5 288 256 309.5 256 336V464C256 490.5 234.5 512 208 512H48C21.49 512 0 490.5 0 464V336C0 309.5 21.49 288 48 288H96zM416 288V368C416 376.8 423.2 384 432 384H464C472.8 384 480 376.8 480 368V288H528C554.5 288 576 309.5 576 336V464C576 490.5 554.5 512 528 512H368C341.5 512 320 490.5 320 464V336C320 309.5 341.5 288 368 288H416z"],
    broom: [640, 512, [129529], "f51a", "M93.13 257.7C71.25 275.1 53 313.5 38.63 355.1L99 333.1c5.75-2.125 10.62 4.749 6.625 9.499L11 454.7C3.75 486.1 0 510.2 0 510.2s206.6 13.62 266.6-34.12c60-47.87 76.63-150.1 76.63-150.1L256.5 216.7C256.5 216.7 153.1 209.1 93.13 257.7zM633.2 12.34c-10.84-13.91-30.91-16.45-44.91-5.624l-225.7 175.6l-34.99-44.06C322.5 131.9 312.5 133.1 309 140.5L283.8 194.1l86.75 109.2l58.75-12.5c8-1.625 11.38-11.12 6.375-17.5l-33.19-41.79l225.2-175.2C641.6 46.38 644.1 26.27 633.2 12.34z"],
    bucket: [448, 512, [], "e4cf", "M96 160H48V152C48 68.05 116.1 0 200 0H248C331.9 0 400 68.05 400 152V160H352V152C352 94.56 305.4 48 248 48H200C142.6 48 96 94.56 96 152V160zM.0003 224C.0003 206.3 14.33 192 32 192H416C433.7 192 448 206.3 448 224C448 241.7 433.7 256 416 256H410.9L388.5 469C385.1 493.5 365.4 512 340.8 512H107.2C82.65 512 62.05 493.5 59.48 469L37.05 256H32C14.33 256 0 241.7 0 224H.0003z"],
    burst: [512, 512, [], "e4dc", "M200.9 116.2L233.2 16.6C236.4 6.706 245.6 .001 256 .001C266.4 .001 275.6 6.706 278.8 16.6L313.3 123.1L383.8 97.45C392.6 94.26 402.4 96.43 408.1 103C415.6 109.6 417.7 119.4 414.6 128.2L388.9 198.7L495.4 233.2C505.3 236.4 512 245.6 512 256C512 266.4 505.3 275.6 495.4 278.8L392.3 312.2L445.2 412.8C450.1 422.1 448.4 433.5 440.1 440.1C433.5 448.4 422.1 450.1 412.8 445.2L312.2 392.3L278.8 495.4C275.6 505.3 266.4 512 256 512C245.6 512 236.4 505.3 233.2 495.4L199.8 392.3L99.17 445.2C89.87 450.1 78.46 448.4 71.03 440.1C63.6 433.5 61.87 422.1 66.76 412.8L119.7 312.2L16.6 278.8C6.705 275.6 .0003 266.4 .0003 256C.0003 245.6 6.705 236.4 16.6 233.2L116.2 200.9L4.208 37.57C-2.33 28.04-1.143 15.2 7.03 7.03C15.2-1.144 28.04-2.33 37.57 4.208L200.9 116.2z"],
    c: [384, 512, [99], "43", "M352 359.8c22.46 0 31.1 19.53 31.1 31.99c0 23.14-66.96 88.23-164.5 88.23c-137.1 0-219.4-117.8-219.4-224c0-103.8 79.87-223.1 219.4-223.1c99.47 0 164.5 66.12 164.5 88.23c0 12.27-9.527 32.01-32.01 32.01c-31.32 0-45.8-56.25-132.5-56.25c-97.99 0-155.4 84.59-155.4 159.1c0 74.03 56.42 160 155.4 160C306.5 416 320.5 359.8 352 359.8z"],
    circle: [512, 512, [128308, 128309, 128992, 128993, 128994, 128995, 128996, 9898, 9899, 11044, 61708, 61915, 9679], "f111", "M512 256C512 397.4 397.4 512 256 512C114.6 512 0 397.4 0 256C0 114.6 114.6 0 256 0C397.4 0 512 114.6 512 256z"],
    "circle-question": [512, 512, [62108, "question-circle"], "f059", "M256 0C114.6 0 0 114.6 0 256s114.6 256 256 256s256-114.6 256-256S397.4 0 256 0zM256 400c-18 0-32-14-32-32s13.1-32 32-32c17.1 0 32 14 32 32S273.1 400 256 400zM325.1 258L280 286V288c0 13-11 24-24 24S232 301 232 288V272c0-8 4-16 12-21l57-34C308 213 312 206 312 198C312 186 301.1 176 289.1 176h-51.1C225.1 176 216 186 216 198c0 13-11 24-24 24s-24-11-24-24C168 159 199 128 237.1 128h51.1C329 128 360 159 360 198C360 222 347 245 325.1 258z"],
    comments: [640, 512, [61670, 128490], "f086", "M416 176C416 78.8 322.9 0 208 0S0 78.8 0 176c0 39.57 15.62 75.96 41.67 105.4c-16.39 32.76-39.23 57.32-39.59 57.68c-2.1 2.205-2.67 5.475-1.441 8.354C1.9 350.3 4.602 352 7.66 352c38.35 0 70.76-11.12 95.74-24.04C134.2 343.1 169.8 352 208 352C322.9 352 416 273.2 416 176zM599.6 443.7C624.8 413.9 640 376.6 640 336C640 238.8 554 160 448 160c-.3145 0-.6191 .041-.9336 .043C447.5 165.3 448 170.6 448 176c0 98.62-79.68 181.2-186.1 202.5C282.7 455.1 357.1 512 448 512c33.69 0 65.32-8.008 92.85-21.98C565.2 502 596.1 512 632.3 512c3.059 0 5.76-1.725 7.02-4.605c1.229-2.879 .6582-6.148-1.441-8.354C637.6 498.7 615.9 475.3 599.6 443.7z"],
    crown: [576, 512, [128081], "f521", "M576 136c0 22.09-17.91 40-40 40c-.248 0-.4551-.1266-.7031-.1305l-50.52 277.9C482 468.9 468.8 480 453.3 480H122.7c-15.46 0-28.72-11.06-31.48-26.27L40.71 175.9C40.46 175.9 40.25 176 39.1 176c-22.09 0-40-17.91-40-40S17.91 96 39.1 96s40 17.91 40 40c0 8.998-3.521 16.89-8.537 23.57l89.63 71.7c15.91 12.73 39.5 7.544 48.61-10.68l57.6-115.2C255.1 98.34 247.1 86.34 247.1 72C247.1 49.91 265.9 32 288 32s39.1 17.91 39.1 40c0 14.34-7.963 26.34-19.3 33.4l57.6 115.2c9.111 18.22 32.71 23.4 48.61 10.68l89.63-71.7C499.5 152.9 496 144.1 496 136C496 113.9 513.9 96 536 96S576 113.9 576 136z"],
    d: [384, 512, [100], "44", "M160 32.01L32 32.01c-17.67 0-32 14.33-32 32v384c0 17.67 14.33 32 32 32l128-.0073c123.5 0 224-100.5 224-224S283.5 32.01 160 32.01zM160 416H64v-320h96c88.22 0 160 71.78 160 159.1S248.2 416 160 416z"],
    droplet: [384, 512, [128167, "tint"], "f043", "M16 319.1C16 245.9 118.3 89.43 166.9 19.3C179.2 1.585 204.8 1.585 217.1 19.3C265.7 89.43 368 245.9 368 319.1C368 417.2 289.2 496 192 496C94.8 496 16 417.2 16 319.1zM112 319.1C112 311.2 104.8 303.1 96 303.1C87.16 303.1 80 311.2 80 319.1C80 381.9 130.1 432 192 432C200.8 432 208 424.8 208 416C208 407.2 200.8 400 192 400C147.8 400 112 364.2 112 319.1z"],
    explosion: [576, 512, [], "e4e9", "M499.6 11.32C506.3 .5948 520.1-3.127 531.3 2.814C542.4 8.754 547.1 22.32 541.9 33.84L404.8 338.6C406.9 340.9 409 343.3 411.1 345.7L508.2 291.1C518.7 285.2 531.9 287.9 539.1 297.5C546.4 307 545.4 320.5 536.1 328.1L449.9 415.1H378.5C365.4 378.7 329.8 351.1 288 351.1C246.2 351.1 210.6 378.7 197.5 415.1H117.8L42.34 363.7C32.59 356.1 29.23 344.1 34.43 333.5C39.64 322.8 51.84 317.6 63.16 321.1L160.4 351.5C163.3 347.6 166.5 343.8 169.7 340.2L107.4 236.3C101.4 226.3 103.5 213.3 112.5 205.7C121.5 198.1 134.7 198.1 143.6 205.8L246 293.6C247.5 293.2 249 292.8 250.5 292.4L264.1 149.7C265.3 137.4 275.6 127.1 288 127.1C300.4 127.1 310.7 137.4 311.9 149.7L325.4 291.6L499.6 11.32zM544 447.1C561.7 447.1 576 462.3 576 479.1C576 497.7 561.7 511.1 544 511.1H32C14.33 511.1 0 497.7 0 479.1C0 462.3 14.33 447.1 32 447.1H544zM288-.0046C301.3-.0046 312 10.74 312 23.1V71.1C312 85.25 301.3 95.1 288 95.1C274.7 95.1 264 85.25 264 71.1V23.1C264 10.74 274.7-.0046 288-.0046V-.0046z"],
    fill: [512, 512, [], "f575", "M168 90.74L221.1 37.66C249.2 9.539 294.8 9.539 322.9 37.66L474.3 189.1C502.5 217.2 502.5 262.8 474.3 290.9L283.9 481.4C246.4 518.9 185.6 518.9 148.1 481.4L30.63 363.9C-6.863 326.4-6.863 265.6 30.63 228.1L122.7 135.1L41.37 54.63C28.88 42.13 28.88 21.87 41.37 9.372C53.87-3.124 74.13-3.124 86.63 9.372L168 90.74zM75.88 273.4C71.69 277.6 68.9 282.6 67.52 287.1H386.7L429.1 245.7C432.2 242.5 432.2 237.5 429.1 234.3L277.7 82.91C274.5 79.79 269.5 79.79 266.3 82.91L213.3 136L262.6 185.4C275.1 197.9 275.1 218.1 262.6 230.6C250.1 243.1 229.9 243.1 217.4 230.6L168 181.3L75.88 273.4z"],
    fire: [448, 512, [128293], "f06d", "M323.5 51.25C302.8 70.5 284 90.75 267.4 111.1C240.1 73.62 206.2 35.5 168 0C69.75 91.12 0 210 0 281.6C0 408.9 100.2 512 224 512s224-103.1 224-230.4C448 228.4 396 118.5 323.5 51.25zM304.1 391.9C282.4 407 255.8 416 226.9 416c-72.13 0-130.9-47.73-130.9-125.2c0-38.63 24.24-72.64 72.74-130.8c7 8 98.88 125.4 98.88 125.4l58.63-66.88c4.125 6.75 7.867 13.52 11.24 19.9C364.9 290.6 353.4 357.4 304.1 391.9z"],
    "fire-flame-curved": [384, 512, ["fire-alt"], "f7e4", "M384 319.1C384 425.9 297.9 512 192 512s-192-86.13-192-192c0-58.67 27.82-106.8 54.57-134.1C69.54 169.3 96 179.8 96 201.5v85.5c0 35.17 27.97 64.5 63.16 64.94C194.9 352.5 224 323.6 224 288c0-88-175.1-96.12-52.15-277.2c13.5-19.72 44.15-10.77 44.15 13.03C215.1 127 384 149.7 384 319.1z"],
    flask: [448, 512, [], "f0c3", "M437.2 403.5L319.1 215L319.1 64h7.1c13.25 0 23.1-10.75 23.1-24l-.0002-16c0-13.25-10.75-24-23.1-24H120C106.8 0 96.01 10.75 96.01 24l-.0002 16c0 13.25 10.75 24 23.1 24h7.1L128 215l-117.2 188.5C-18.48 450.6 15.27 512 70.89 512h306.2C432.7 512 466.5 450.5 437.2 403.5zM137.1 320l48.15-77.63C189.8 237.3 191.9 230.8 191.9 224l.0651-160h63.99l-.06 160c0 6.875 2.25 13.25 5.875 18.38L309.9 320H137.1z"],
    g: [448, 512, [103], "47", "M448 256c0 143.4-118.6 222.3-225 222.3c-132.3 0-222.1-106.2-222.1-222.4c0-124.4 100.9-223.9 223.1-223.9c84.84 0 167.8 55.28 167.8 88.2c0 18.28-14.95 32-32 32c-31.04 0-46.79-56.16-135.8-56.16c-87.66 0-159.1 70.66-159.1 159.8c0 34.81 27.19 158.8 159.1 158.8c79.45 0 144.6-55.1 158.1-126.7h-134.1c-17.67 0-32-14.33-32-32s14.33-31.1 32-31.1H416C433.7 224 448 238.3 448 256z"],
    gauge: [512, 512, ["dashboard", "gauge-med", "tachometer-alt-average"], "f624", "M512 256C512 397.4 397.4 512 256 512C114.6 512 0 397.4 0 256C0 114.6 114.6 0 256 0C397.4 0 512 114.6 512 256zM280 292.7V88C280 74.75 269.3 64 256 64C242.7 64 232 74.75 232 88V292.7C208.5 302.1 192 325.1 192 352C192 387.3 220.7 416 256 416C291.3 416 320 387.3 320 352C320 325.1 303.5 302.1 280 292.7zM144 176C161.7 176 176 161.7 176 144C176 126.3 161.7 112 144 112C126.3 112 112 126.3 112 144C112 161.7 126.3 176 144 176zM96 224C78.33 224 64 238.3 64 256C64 273.7 78.33 288 96 288C113.7 288 128 273.7 128 256C128 238.3 113.7 224 96 224zM416 288C433.7 288 448 273.7 448 256C448 238.3 433.7 224 416 224C398.3 224 384 238.3 384 256C384 273.7 398.3 288 416 288zM368 112C350.3 112 336 126.3 336 144C336 161.7 350.3 176 368 176C385.7 176 400 161.7 400 144C400 126.3 385.7 112 368 112z"],
    gavel: [512, 512, ["legal"], "f0e3", "M512 216.3c0-6.125-2.344-12.25-7.031-16.93L482.3 176.8c-4.688-4.686-10.84-7.028-16.1-7.028s-12.31 2.343-16.1 7.028l-5.625 5.625L329.6 69.28l5.625-5.625c4.687-4.688 7.03-10.84 7.03-16.1s-2.343-12.31-7.03-16.1l-22.62-22.62C307.9 2.344 301.8 0 295.7 0s-12.15 2.344-16.84 7.031L154.2 131.5C149.6 136.2 147.2 142.3 147.2 148.5s2.344 12.25 7.031 16.94l22.62 22.62c4.688 4.688 10.84 7.031 16.1 7.031c6.156 0 12.31-2.344 16.1-7.031l5.625-5.625l113.1 113.1l-5.625 5.621c-4.688 4.688-7.031 10.84-7.031 16.1s2.344 12.31 7.031 16.1l22.62 22.62c4.688 4.688 10.81 7.031 16.94 7.031s12.25-2.344 16.94-7.031l124.5-124.6C509.7 228.5 512 222.5 512 216.3zM227.8 238.1L169.4 297.4C163.1 291.1 154.9 288 146.7 288S130.4 291.1 124.1 297.4l-114.7 114.7c-6.25 6.248-9.375 14.43-9.375 22.62s3.125 16.37 9.375 22.62l45.25 45.25C60.87 508.9 69.06 512 77.25 512s16.37-3.125 22.62-9.375l114.7-114.7c6.25-6.25 9.376-14.44 9.376-22.62c0-8.185-3.125-16.37-9.374-22.62l58.43-58.43L227.8 238.1z"],
    grip: [448, 512, ["grip-horizontal"], "f58d", "M128 184C128 206.1 110.1 224 88 224H40C17.91 224 0 206.1 0 184V136C0 113.9 17.91 96 40 96H88C110.1 96 128 113.9 128 136V184zM128 376C128 398.1 110.1 416 88 416H40C17.91 416 0 398.1 0 376V328C0 305.9 17.91 288 40 288H88C110.1 288 128 305.9 128 328V376zM160 136C160 113.9 177.9 96 200 96H248C270.1 96 288 113.9 288 136V184C288 206.1 270.1 224 248 224H200C177.9 224 160 206.1 160 184V136zM288 376C288 398.1 270.1 416 248 416H200C177.9 416 160 398.1 160 376V328C160 305.9 177.9 288 200 288H248C270.1 288 288 305.9 288 328V376zM320 136C320 113.9 337.9 96 360 96H408C430.1 96 448 113.9 448 136V184C448 206.1 430.1 224 408 224H360C337.9 224 320 206.1 320 184V136zM448 376C448 398.1 430.1 416 408 416H360C337.9 416 320 398.1 320 376V328C320 305.9 337.9 288 360 288H408C430.1 288 448 305.9 448 328V376z"],
    hammer: [576, 512, [128296], "f6e3", "M568.1 196.3l-22.62-22.62c-4.533-4.533-10.56-7.029-16.97-7.029s-12.44 2.496-16.97 7.029l-5.654 5.656l-20.12-20.12c4.596-23.46-2.652-47.9-19.47-64.73l-45.25-45.25C390.2 17.47 347.1 0 303.1 0C258.2 0 216 17.47 184.3 49.21L176.5 57.05L272.5 105.1v13.81c0 18.95 7.688 37.5 21.09 50.91l49.16 49.14c13.44 13.45 31.39 20.86 50.54 20.86c4.758 0 9.512-.4648 14.18-1.387l20.12 20.12l-5.654 5.654c-9.357 9.357-9.357 24.58-.002 33.94l22.62 22.62c4.535 4.533 10.56 7.031 16.97 7.031s12.44-2.498 16.97-7.031l90.53-90.5C578.3 220.8 578.3 205.6 568.1 196.3zM270.9 192.4c-3.846-3.846-7.197-8.113-10.37-12.49l-239.5 209.2c-28.12 28.12-28.16 73.72-.0371 101.8C35.12 505 53.56 512 71.1 512s36.84-7.031 50.91-21.09l209.1-239.4c-4.141-3.061-8.184-6.289-11.89-9.996L270.9 192.4z"],
    hand: [512, 512, [129306, 9995, "hand-paper"], "f256", "M480 128v208c0 97.05-78.95 176-176 176h-37.72c-53.42 0-103.7-20.8-141.4-58.58l-113.1-113.1C3.906 332.5 0 322.2 0 312C0 290.7 17.15 272 40 272c10.23 0 20.47 3.906 28.28 11.72L128 343.4V64c0-17.67 14.33-32 32-32s32 14.33 32 32l.0729 176C192.1 248.8 199.2 256 208 256s16.07-7.164 16.07-16L224 32c0-17.67 14.33-32 32-32s32 14.33 32 32l.0484 208c0 8.836 7.111 16 15.95 16S320 248.8 320 240L320 64c0-17.67 14.33-32 32-32s32 14.33 32 32l.0729 176c0 8.836 7.091 16 15.93 16S416 248.8 416 240V128c0-17.67 14.33-32 32-32S480 110.3 480 128z"],
    handshake: [640, 512, [], "f2b5", "M0 383.9l64 .0404c17.75 0 32-14.29 32-32.03V128.3L0 128.3V383.9zM48 320.1c8.75 0 16 7.118 16 15.99c0 8.742-7.25 15.99-16 15.99S32 344.8 32 336.1C32 327.2 39.25 320.1 48 320.1zM348.8 64c-7.941 0-15.66 2.969-21.52 8.328L228.9 162.3C228.8 162.5 228.8 162.7 228.6 162.7C212 178.3 212.3 203.2 226.5 218.7c12.75 13.1 39.38 17.62 56.13 2.75C282.8 221.3 282.9 221.3 283 221.2l79.88-73.1c6.5-5.871 16.75-5.496 22.62 1c6 6.496 5.5 16.62-1 22.62l-26.12 23.87L504 313.7c2.875 2.496 5.5 4.996 7.875 7.742V127.1c-40.98-40.96-96.48-63.88-154.4-63.88L348.8 64zM334.6 217.4l-30 27.49c-29.75 27.11-75.25 24.49-101.8-4.371C176 211.2 178.1 165.7 207.3 138.9L289.1 64H282.5C224.7 64 169.1 87.08 128.2 127.9L128 351.8l18.25 .0369l90.5 81.82c27.5 22.37 67.75 18.12 90-9.246l18.12 15.24c15.88 12.1 39.38 10.5 52.38-5.371l31.38-38.6l5.374 4.498c13.75 11 33.88 9.002 45-4.748l9.538-11.78c11.12-13.75 9.036-33.78-4.694-44.93L334.6 217.4zM544 128.4v223.6c0 17.62 14.25 32.05 31.1 32.05L640 384V128.1L544 128.4zM592 352c-8.75 0-16-7.246-16-15.99c0-8.875 7.25-15.99 16-15.99S608 327.2 608 336.1C608 344.8 600.8 352 592 352z"],
    hurricane: [448, 512, [], "f751", "M224 223.1c-17.75 0-32 14.25-32 32c0 17.75 14.25 32 32 32s32-14.25 32-32C256 238.2 241.8 223.1 224 223.1zM208 95.98l24.5-74.74c3.75-11.25-5.615-22.49-17.36-21.11C112 12.38 32 101.6 32 208c0 114.9 93.13 208 208 208l-24.5 74.73c-3.75 11.25 5.615 22.5 17.36 21.12C335.1 499.6 416 410.4 416 304C416 189.1 322.9 95.98 208 95.98zM224 351.1c-53 0-96-43-96-96s43-96 96-96s96 43 96 96S277 351.1 224 351.1z"],
    i: [320, 512, [105], "49", "M320 448c0 17.67-14.31 32-32 32H32c-17.69 0-32-14.33-32-32s14.31-32 32-32h96v-320H32c-17.69 0-32-14.33-32-32s14.31-32 32-32h256c17.69 0 32 14.33 32 32s-14.31 32-32 32h-96v320h96C305.7 416 320 430.3 320 448z"],
    info: [192, 512, [], "f129", "M160 448h-32V224c0-17.69-14.33-32-32-32L32 192c-17.67 0-32 14.31-32 32s14.33 31.1 32 31.1h32v192H32c-17.67 0-32 14.31-32 32s14.33 32 32 32h128c17.67 0 32-14.31 32-32S177.7 448 160 448zM96 128c26.51 0 48-21.49 48-48S122.5 32.01 96 32.01s-48 21.49-48 48S69.49 128 96 128z"],
    jar: [320, 512, [], "e516", "M32 32C32 14.33 46.33 0 64 0H256C273.7 0 288 14.33 288 32C288 49.67 273.7 64 256 64H64C46.33 64 32 49.67 32 32zM0 160C0 124.7 28.65 96 64 96H256C291.3 96 320 124.7 320 160V448C320 483.3 291.3 512 256 512H64C28.65 512 0 483.3 0 448V160zM256 224H64V384H256V224z"],
    key: [512, 512, [128273], "f084", "M282.3 343.7L248.1 376.1C244.5 381.5 238.4 384 232 384H192V424C192 437.3 181.3 448 168 448H128V488C128 501.3 117.3 512 104 512H24C10.75 512 0 501.3 0 488V408C0 401.6 2.529 395.5 7.029 391L168.3 229.7C162.9 212.8 160 194.7 160 176C160 78.8 238.8 0 336 0C433.2 0 512 78.8 512 176C512 273.2 433.2 352 336 352C317.3 352 299.2 349.1 282.3 343.7zM376 176C398.1 176 416 158.1 416 136C416 113.9 398.1 96 376 96C353.9 96 336 113.9 336 136C336 158.1 353.9 176 376 176z"],
    keyboard: [576, 512, [9000], "f11c", "M512 448H64c-35.35 0-64-28.65-64-64V128c0-35.35 28.65-64 64-64h448c35.35 0 64 28.65 64 64v256C576 419.3 547.3 448 512 448zM128 180v-40C128 133.4 122.6 128 116 128h-40C69.38 128 64 133.4 64 140v40C64 186.6 69.38 192 76 192h40C122.6 192 128 186.6 128 180zM224 180v-40C224 133.4 218.6 128 212 128h-40C165.4 128 160 133.4 160 140v40C160 186.6 165.4 192 172 192h40C218.6 192 224 186.6 224 180zM320 180v-40C320 133.4 314.6 128 308 128h-40C261.4 128 256 133.4 256 140v40C256 186.6 261.4 192 268 192h40C314.6 192 320 186.6 320 180zM416 180v-40C416 133.4 410.6 128 404 128h-40C357.4 128 352 133.4 352 140v40C352 186.6 357.4 192 364 192h40C410.6 192 416 186.6 416 180zM512 180v-40C512 133.4 506.6 128 500 128h-40C453.4 128 448 133.4 448 140v40C448 186.6 453.4 192 460 192h40C506.6 192 512 186.6 512 180zM128 276v-40C128 229.4 122.6 224 116 224h-40C69.38 224 64 229.4 64 236v40C64 282.6 69.38 288 76 288h40C122.6 288 128 282.6 128 276zM224 276v-40C224 229.4 218.6 224 212 224h-40C165.4 224 160 229.4 160 236v40C160 282.6 165.4 288 172 288h40C218.6 288 224 282.6 224 276zM320 276v-40C320 229.4 314.6 224 308 224h-40C261.4 224 256 229.4 256 236v40C256 282.6 261.4 288 268 288h40C314.6 288 320 282.6 320 276zM416 276v-40C416 229.4 410.6 224 404 224h-40C357.4 224 352 229.4 352 236v40C352 282.6 357.4 288 364 288h40C410.6 288 416 282.6 416 276zM512 276v-40C512 229.4 506.6 224 500 224h-40C453.4 224 448 229.4 448 236v40C448 282.6 453.4 288 460 288h40C506.6 288 512 282.6 512 276zM128 372v-40C128 325.4 122.6 320 116 320h-40C69.38 320 64 325.4 64 332v40C64 378.6 69.38 384 76 384h40C122.6 384 128 378.6 128 372zM416 372v-40C416 325.4 410.6 320 404 320h-232C165.4 320 160 325.4 160 332v40C160 378.6 165.4 384 172 384h232C410.6 384 416 378.6 416 372zM512 372v-40C512 325.4 506.6 320 500 320h-40C453.4 320 448 325.4 448 332v40C448 378.6 453.4 384 460 384h40C506.6 384 512 378.6 512 372z"],
    l: [320, 512, [108], "4c", "M320 448c0 17.67-14.31 32-32 32H64c-17.69 0-32-14.33-32-32v-384C32 46.34 46.31 32.01 64 32.01S96 46.34 96 64.01v352h192C305.7 416 320 430.3 320 448z"],
    leaf: [512, 512, [], "f06c", "M512 165.4c0 127.9-70.05 235.3-175.3 270.1c-20.04 7.938-41.83 12.46-64.69 12.46c-64.9 0-125.2-36.51-155.7-94.47c-54.13 49.93-68.71 107-68.96 108.1C44.72 472.6 34.87 480 24.02 480c-1.844 0-3.727-.2187-5.602-.6562c-12.89-3.098-20.84-16.08-17.75-28.96c9.598-39.5 90.47-226.4 335.3-226.4C344.8 224 352 216.8 352 208S344.8 192 336 192C228.6 192 151 226.6 96.29 267.6c.1934-10.82 1.242-21.84 3.535-33.05c13.47-65.81 66.04-119 131.4-134.2c28.33-6.562 55.68-6.013 80.93-.0054c56 13.32 118.2-7.412 149.3-61.24c5.664-9.828 20.02-9.516 24.66 .8282C502.7 76.76 512 121.9 512 165.4z"],
    lock: [448, 512, [128274], "f023", "M80 192V144C80 64.47 144.5 0 224 0C303.5 0 368 64.47 368 144V192H384C419.3 192 448 220.7 448 256V448C448 483.3 419.3 512 384 512H64C28.65 512 0 483.3 0 448V256C0 220.7 28.65 192 64 192H80zM144 192H304V144C304 99.82 268.2 64 224 64C179.8 64 144 99.82 144 144V192z"],
    "lock-open": [576, 512, [], "f3c1", "M352 192H384C419.3 192 448 220.7 448 256V448C448 483.3 419.3 512 384 512H64C28.65 512 0 483.3 0 448V256C0 220.7 28.65 192 64 192H288V144C288 64.47 352.5 0 432 0C511.5 0 576 64.47 576 144V192C576 209.7 561.7 224 544 224C526.3 224 512 209.7 512 192V144C512 99.82 476.2 64 432 64C387.8 64 352 99.82 352 144V192z"],
    "magnifying-glass": [512, 512, [128269, "search"], "f002", "M500.3 443.7l-119.7-119.7c27.22-40.41 40.65-90.9 33.46-144.7C401.8 87.79 326.8 13.32 235.2 1.723C99.01-15.51-15.51 99.01 1.724 235.2c11.6 91.64 86.08 166.7 177.6 178.9c53.8 7.189 104.3-6.236 144.7-33.46l119.7 119.7c15.62 15.62 40.95 15.62 56.57 0C515.9 484.7 515.9 459.3 500.3 443.7zM79.1 208c0-70.58 57.42-128 128-128s128 57.42 128 128c0 70.58-57.42 128-128 128S79.1 278.6 79.1 208z"],
    message: [512, 512, ["comment-alt"], "f27a", "M511.1 63.1v287.1c0 35.25-28.75 63.1-64 63.1h-144l-124.9 93.68c-7.875 5.75-19.12 .0497-19.12-9.7v-83.98h-96c-35.25 0-64-28.75-64-63.1V63.1c0-35.25 28.75-63.1 64-63.1h384C483.2 0 511.1 28.75 511.1 63.1z"],
    p: [320, 512, [112], "50", "M160 32.01H32c-17.69 0-32 14.33-32 32v384c0 17.67 14.31 32 32 32s32-14.33 32-32v-96h96c88.22 0 160-71.78 160-159.1S248.2 32.01 160 32.01zM160 288H64V96.01h96c52.94 0 96 43.06 96 96S212.9 288 160 288z"],
    "person-hiking": [384, 512, ["hiking"], "f6ec", "M240 96c26.5 0 48-21.5 48-48S266.5 0 240 0C213.5 0 192 21.5 192 48S213.5 96 240 96zM80.01 287.1c7.31 0 13.97-4.762 15.87-11.86L137 117c.3468-1.291 .5125-2.588 .5125-3.866c0-7.011-4.986-13.44-12.39-15.13C118.4 96.38 111.7 95.6 105.1 95.6c-36.65 0-70 23.84-79.32 59.53L.5119 253.3C.1636 254.6-.0025 255.9-.0025 257.2c0 7.003 4.961 13.42 12.36 15.11L76.01 287.5C77.35 287.8 78.69 287.1 80.01 287.1zM368 160h-15.1c-8.875 0-15.1 7.125-15.1 16V192h-34.75l-46.75-46.75C243.4 134.1 228.6 128 212.9 128C185.9 128 162.5 146.3 155.9 172.5L129 280.3C128.4 282.8 128 285.5 128 288.1c0 8.325 3.265 16.44 9.354 22.53l86.62 86.63V480c0 17.62 14.37 32 31.1 32s32-14.38 32-32v-82.75c0-17.12-6.625-33.13-18.75-45.25l-46.87-46.88c.25-.5 .5-.875 .625-1.375l19.1-79.5l22.37 22.38C271.4 252.6 279.5 256 288 256h47.1v240c0 8.875 7.125 16 15.1 16h15.1C376.9 512 384 504.9 384 496v-320C384 167.1 376.9 160 368 160zM81.01 472.3c-.672 2.63-.993 5.267-.993 7.86c0 14.29 9.749 27.29 24.24 30.89C106.9 511.8 109.5 512 112 512c14.37 0 27.37-9.75 30.1-24.25l25.25-101l-52.75-52.75L81.01 472.3z"],
    q: [448, 512, [113], "51", "M393.1 402.5c34.12-39.32 54.93-90.48 54.93-146.5c0-123.5-100.5-224-223.1-224S.0001 132.5 .0001 256s100.5 224 223.1 224c44.45 0 85.81-13.16 120.7-35.58l46.73 56.08c6.328 7.594 15.42 11.52 24.59 11.52c21.35 0 31.98-18.26 31.98-32.01c0-7.223-2.433-14.49-7.419-20.47L393.1 402.5zM224 416c-88.22 0-160-71.78-160-160s71.78-159.1 160-159.1s160 71.78 160 159.1c0 36.21-12.55 69.28-32.92 96.12L280.6 267.5c-6.338-7.597-15.44-11.53-24.61-11.53c-21.27 0-31.96 18.22-31.96 32.02c0 7.223 2.433 14.49 7.419 20.47l71.53 85.83C279.6 407.7 252.8 416 224 416z"],
    ring: [512, 512, [], "f70b", "M256 64C109.1 64 0 125.9 0 208v98.13C0 384.5 114.6 448 256 448s256-63.5 256-141.9V208C512 125.9 401.1 64 256 64zM256 288C203.1 288 155.1 279.1 120.4 264.6C155 249.9 201.6 240 256 240s101 9.875 135.6 24.62C356.9 279.1 308.9 288 256 288zM437.1 234.4C392.1 208.3 328.3 192 256 192S119.9 208.3 74.88 234.4C68 226.1 64 217.3 64 208C64 163.9 149.1 128 256 128c105.1 0 192 35.88 192 80C448 217.3 444 226.1 437.1 234.4z"],
    s: [384, 512, [115], "53", "M349.9 379.1c-6.281 36.63-25.89 65.02-56.69 82.11c-24.91 13.83-54.08 18.98-83.73 18.98c-61.86 0-125.8-22.42-157.5-35.38c-16.38-6.672-24.22-25.34-17.55-41.7c6.641-16.36 25.27-24.28 41.7-17.55c77.56 31.64 150.6 39.39 186.1 19.69c13.83-7.672 21.67-19.42 24.69-36.98c7.25-42.31-18.2-56.75-103.7-81.38C112.6 266.6 15.98 238.7 34.11 133.2c5.484-32 23.64-59.36 51.14-77.02c45.59-29.33 115-31.87 206.4-7.688c17.09 4.531 27.27 22.05 22.75 39.13s-22.06 27.23-39.13 22.75C184 86.17 140.4 96.81 119.8 110c-12.55 8.062-20.17 19.5-22.66 34c-7.266 42.31 18.19 56.75 103.7 81.38C271.4 245.7 368 273.5 349.9 379.1z"],
    "sack-dollar": [512, 512, [128176], "f81d", "M320 96H192L144.6 24.88C137.5 14.24 145.1 0 157.9 0H354.1C366.9 0 374.5 14.24 367.4 24.88L320 96zM192 128H320C323.8 130.5 328.1 133.3 332.1 136.4C389.7 172.7 512 250.9 512 416C512 469 469 512 416 512H96C42.98 512 0 469 0 416C0 250.9 122.3 172.7 179 136.4C183.9 133.3 188.2 130.5 192 128V128zM276.1 224C276.1 212.9 267.1 203.9 255.1 203.9C244.9 203.9 235.9 212.9 235.9 224V230C230.3 231.2 224.1 232.9 220 235.1C205.1 241.9 192.1 254.5 188.9 272.8C187.1 283 188.1 292.9 192.3 301.8C196.5 310.6 203 316.8 209.6 321.3C221.2 329.2 236.5 333.8 248.2 337.3L250.4 337.9C264.4 342.2 273.8 345.3 279.7 349.6C282.2 351.4 283.1 352.8 283.4 353.7C283.8 354.5 284.4 356.3 283.7 360.3C283.1 363.8 281.2 366.8 275.7 369.1C269.6 371.7 259.7 373 246.9 371C240.9 370 230.2 366.4 220.7 363.2C218.5 362.4 216.3 361.7 214.3 361C203.8 357.5 192.5 363.2 189 373.7C185.5 384.2 191.2 395.5 201.7 398.1C202.9 399.4 204.4 399.9 206.1 400.5C213.1 403.2 226.4 407.4 235.9 409.6V416C235.9 427.1 244.9 436.1 255.1 436.1C267.1 436.1 276.1 427.1 276.1 416V410.5C281.4 409.5 286.6 407.1 291.4 405.9C307.2 399.2 319.8 386.2 323.1 367.2C324.9 356.8 324.1 346.8 320.1 337.7C316.2 328.7 309.9 322.1 303.2 317.3C291.1 308.4 274.9 303.6 262.8 299.9L261.1 299.7C247.8 295.4 238.2 292.4 232.1 288.2C229.5 286.4 228.7 285.2 228.5 284.7C228.3 284.3 227.7 283.1 228.3 279.7C228.7 277.7 230.2 274.4 236.5 271.6C242.1 268.7 252.9 267.1 265.1 268.1C269.5 269.7 283 272.3 286.9 273.3C297.5 276.2 308.5 269.8 311.3 259.1C314.2 248.5 307.8 237.5 297.1 234.7C292.7 233.5 282.7 231.5 276.1 230.3L276.1 224z"],
    shower: [512, 512, [128703], "f2cc", "M288 384c-17.67 0-32 14.33-32 32c0 17.67 14.33 32 32 32s32-14.33 32-32C320 398.3 305.7 384 288 384zM416 256c-17.67 0-32 14.33-32 32c0 17.67 14.33 32 32 32s32-14.33 32-32C448 270.3 433.7 256 416 256zM480 192c-17.67 0-32 14.33-32 32c0 17.67 14.33 32 32 32s32-14.33 32-32C512 206.3 497.7 192 480 192zM288 320c0-17.67-14.33-32-32-32s-32 14.33-32 32c0 17.67 14.33 32 32 32S288 337.7 288 320zM320 224c-17.67 0-32 14.33-32 32c0 17.67 14.33 32 32 32s32-14.33 32-32C352 238.3 337.7 224 320 224zM384 224c17.67 0 32-14.33 32-32c0-17.67-14.33-32-32-32s-32 14.33-32 32C352 209.7 366.3 224 384 224zM352 320c-17.67 0-32 14.33-32 32c0 17.67 14.33 32 32 32s32-14.33 32-32C384 334.3 369.7 320 352 320zM347.3 91.31l-11.31-11.31c-6.248-6.248-16.38-6.248-22.63 0l-6.631 6.631c-35.15-26.29-81.81-29.16-119.6-8.779L170.5 61.25C132.2 22.95 63.65 18.33 21.98 71.16C7.027 90.11 0 114.3 0 138.4V464C0 472.8 7.164 480 16 480h32C56.84 480 64 472.8 64 464V131.9c0-19.78 16.09-35.87 35.88-35.87c9.438 0 18.69 3.828 25.38 10.5l16.61 16.61C121.5 160.9 124.3 207.6 150.6 242.7L144 249.4c-6.248 6.248-6.248 16.38 0 22.63l11.31 11.31c6.248 6.25 16.38 6.25 22.63 0l169.4-169.4C353.6 107.7 353.6 97.56 347.3 91.31z"],
    spoon: [512, 512, [61873, 129348, "utensil-spoon"], "f2e5", "M449.5 242.2C436.4 257.8 419.8 270 400.1 277.8C382.2 285.6 361.7 288.8 341.4 287C326.2 284.5 311.8 278.4 299.5 269.1L68.29 500.3C60.79 507.8 50.61 512 40 512C29.39 512 19.22 507.8 11.71 500.3C4.211 492.8-.0039 482.6-.0039 472C-.0039 461.4 4.211 451.2 11.71 443.7L243 212.5C233.7 200.2 227.6 185.8 225.1 170.6C223.3 150.3 226.5 129.9 234.3 111C242.1 92.22 254.3 75.56 269.9 62.47C337.8-5.437 433.1-20.28 482.7 29.35C532.3 78.95 517.4 174.2 449.5 242.2z"],
    square: [448, 512, [9723, 9724, 61590, 9632], "f0c8", "M0 96C0 60.65 28.65 32 64 32H384C419.3 32 448 60.65 448 96V416C448 451.3 419.3 480 384 480H64C28.65 480 0 451.3 0 416V96z"],
    store: [576, 512, [], "f54e", "M495.5 223.2C491.6 223.7 487.6 224 483.4 224C457.4 224 434.2 212.6 418.3 195C402.4 212.6 379.2 224 353.1 224C327 224 303.8 212.6 287.9 195C272 212.6 248.9 224 222.7 224C196.7 224 173.5 212.6 157.6 195C141.7 212.6 118.5 224 92.36 224C88.3 224 84.21 223.7 80.24 223.2C24.92 215.8-1.255 150.6 28.33 103.8L85.66 13.13C90.76 4.979 99.87 0 109.6 0H466.4C476.1 0 485.2 4.978 490.3 13.13L547.6 103.8C577.3 150.7 551 215.8 495.5 223.2H495.5zM499.7 254.9C503.1 254.4 508 253.6 512 252.6V448C512 483.3 483.3 512 448 512H128C92.66 512 64 483.3 64 448V252.6C67.87 253.6 71.86 254.4 75.97 254.9L76.09 254.9C81.35 255.6 86.83 256 92.36 256C104.8 256 116.8 254.1 128 250.6V384H448V250.7C459.2 254.1 471.1 256 483.4 256C489 256 494.4 255.6 499.7 254.9L499.7 254.9z"],
    table: [512, 512, [], "f0ce", "M448 32C483.3 32 512 60.65 512 96V416C512 451.3 483.3 480 448 480H64C28.65 480 0 451.3 0 416V96C0 60.65 28.65 32 64 32H448zM224 256V160H64V256H224zM64 320V416H224V320H64zM288 416H448V320H288V416zM448 256V160H288V256H448z"],
    tarp: [576, 512, [], "e57b", "M576 288H448C430.3 288 416 302.3 416 320V448H64C28.65 448 0 419.3 0 384V128C0 92.65 28.65 64 64 64H512C547.3 64 576 92.65 576 128V288zM96 192C113.7 192 128 177.7 128 160C128 142.3 113.7 128 96 128C78.33 128 64 142.3 64 160C64 177.7 78.33 192 96 192zM448 448V320H576L448 448z"],
    trash: [448, 512, [], "f1f8", "M135.2 17.69C140.6 6.848 151.7 0 163.8 0H284.2C296.3 0 307.4 6.848 312.8 17.69L320 32H416C433.7 32 448 46.33 448 64C448 81.67 433.7 96 416 96H32C14.33 96 0 81.67 0 64C0 46.33 14.33 32 32 32H128L135.2 17.69zM394.8 466.1C393.2 492.3 372.3 512 346.9 512H101.1C75.75 512 54.77 492.3 53.19 466.1L31.1 128H416L394.8 466.1z"],
    tree: [448, 512, [127794], "f1bb", "M413.8 447.1L256 448l0 31.99C256 497.7 241.8 512 224.1 512c-17.67 0-32.1-14.32-32.1-31.99l0-31.99l-158.9-.0099c-28.5 0-43.69-34.49-24.69-56.4l68.98-79.59H62.22c-25.41 0-39.15-29.8-22.67-49.13l60.41-70.85H89.21c-21.28 0-32.87-22.5-19.28-37.31l134.8-146.5c10.4-11.3 28.22-11.3 38.62-.0033l134.9 146.5c13.62 14.81 2.001 37.31-19.28 37.31h-10.77l60.35 70.86c16.46 19.34 2.716 49.12-22.68 49.12h-15.2l68.98 79.59C458.7 413.7 443.1 447.1 413.8 447.1z"],
    "triangle-exclamation": [512, 512, [9888, "exclamation-triangle", "warning"], "f071", "M506.3 417l-213.3-364c-16.33-28-57.54-28-73.98 0l-213.2 364C-10.59 444.9 9.849 480 42.74 480h426.6C502.1 480 522.6 445 506.3 417zM232 168c0-13.25 10.75-24 24-24S280 154.8 280 168v128c0 13.25-10.75 24-23.1 24S232 309.3 232 296V168zM256 416c-17.36 0-31.44-14.08-31.44-31.44c0-17.36 14.07-31.44 31.44-31.44s31.44 14.08 31.44 31.44C287.4 401.9 273.4 416 256 416z"],
    umbrella: [576, 512, [], "f0e9", "M255.1 301.7v130.3c0 8.814-7.188 16-16 16c-7.814 0-13.19-5.314-15.1-10.69c-5.906-16.72-24.1-25.41-40.81-19.5c-16.69 5.875-25.41 24.19-19.5 40.79C175.8 490.6 206.2 512 239.1 512C284.1 512 320 476.1 320 431.1v-130.3c-9.094-7.908-19.81-13.61-32-13.61C275.7 288.1 265.6 292.9 255.1 301.7zM575.7 280.9C547.1 144.5 437.3 62.61 320 49.91V32.01c0-17.69-14.31-32.01-32-32.01S255.1 14.31 255.1 32.01v17.91C138.3 62.61 29.48 144.5 .2949 280.9C-1.926 290.1 8.795 302.1 18.98 292.2c52-55.01 107.7-52.39 158.6 37.01c5.312 9.502 14.91 8.625 19.72 0C217.5 293.9 242.2 256 287.1 256c58.5 0 88.19 68.82 90.69 73.2c4.812 8.625 14.41 9.502 19.72 0c51-89.52 107.1-91.39 158.6-37.01C567.3 302.2 577.9 290.1 575.7 280.9z"],
    "user-group": [640, 512, [128101, "user-friends"], "f500", "M224 256c70.7 0 128-57.31 128-128S294.7 0 224 0C153.3 0 96 57.31 96 128S153.3 256 224 256zM274.7 304H173.3c-95.73 0-173.3 77.6-173.3 173.3C0 496.5 15.52 512 34.66 512H413.3C432.5 512 448 496.5 448 477.3C448 381.6 370.4 304 274.7 304zM479.1 320h-73.85C451.2 357.7 480 414.1 480 477.3C480 490.1 476.2 501.9 470 512h138C625.7 512 640 497.6 640 479.1C640 391.6 568.4 320 479.1 320zM432 256C493.9 256 544 205.9 544 144S493.9 32 432 32c-25.11 0-48.04 8.555-66.72 22.51C376.8 76.63 384 101.4 384 128c0 35.52-11.93 68.14-31.59 94.71C372.7 243.2 400.8 256 432 256z"],
    "user-xmark": [640, 512, ["user-times"], "f235", "M274.7 304H173.3C77.61 304 0 381.6 0 477.3C0 496.5 15.52 512 34.66 512h378.7C432.5 512 448 496.5 448 477.3C448 381.6 370.4 304 274.7 304zM224 256c70.7 0 128-57.31 128-128S294.7 0 224 0C153.3 0 96 57.31 96 128S153.3 256 224 256zM577.9 223.1l47.03-47.03c9.375-9.375 9.375-24.56 0-33.94s-24.56-9.375-33.94 0L544 190.1l-47.03-47.03c-9.375-9.375-24.56-9.375-33.94 0s-9.375 24.56 0 33.94l47.03 47.03l-47.03 47.03c-9.375 9.375-9.375 24.56 0 33.94c9.373 9.373 24.56 9.381 33.94 0L544 257.9l47.03 47.03c9.373 9.373 24.56 9.381 33.94 0c9.375-9.375 9.375-24.56 0-33.94L577.9 223.1z"],
    water: [576, 512, [], "f773", "M549.8 237.5c-31.23-5.719-46.84-20.06-47.13-20.31C490.4 205 470.3 205.1 457.7 216.8c-1 .9375-25.14 23-73.73 23s-72.73-22.06-73.38-22.62C298.4 204.9 278.3 205.1 265.7 216.8c-1 .9375-25.14 23-73.73 23S119.3 217.8 118.6 217.2C106.4 204.9 86.35 205 73.74 216.9C73.09 217.4 57.48 231.8 26.24 237.5c-17.38 3.188-28.89 19.84-25.72 37.22c3.188 17.38 19.78 29.09 37.25 25.72C63.1 295.8 82.49 287.1 95.96 279.2c19.5 11.53 51.47 24.68 96.04 24.68c44.55 0 76.49-13.12 96-24.65c19.52 11.53 51.45 24.59 96 24.59c44.58 0 76.55-13.09 96.05-24.62c13.47 7.938 32.86 16.62 58.19 21.25c17.56 3.375 34.06-8.344 37.25-25.72C578.7 257.4 567.2 240.7 549.8 237.5zM549.8 381.7c-31.23-5.719-46.84-20.06-47.13-20.31c-12.22-12.19-32.31-12.12-44.91-.375C456.7 361.9 432.6 384 384 384s-72.73-22.06-73.38-22.62c-12.22-12.25-32.3-12.12-44.89-.375C264.7 361.9 240.6 384 192 384s-72.73-22.06-73.38-22.62c-12.22-12.25-32.28-12.16-44.89-.3438c-.6562 .5938-16.27 14.94-47.5 20.66c-17.38 3.188-28.89 19.84-25.72 37.22C3.713 436.3 20.31 448 37.78 444.6C63.1 440 82.49 431.3 95.96 423.4c19.5 11.53 51.51 24.62 96.08 24.62c44.55 0 76.45-13.06 95.96-24.59C307.5 434.9 339.5 448 384.1 448c44.58 0 76.5-13.09 95.1-24.62c13.47 7.938 32.86 16.62 58.19 21.25C555.8 448 572.3 436.3 575.5 418.9C578.7 401.5 567.2 384.9 549.8 381.7zM37.78 156.4c25.33-4.625 44.72-13.31 58.19-21.25c19.5 11.53 51.47 24.68 96.04 24.68c44.55 0 76.49-13.12 96-24.65c19.52 11.53 51.45 24.59 96 24.59c44.58 0 76.55-13.09 96.05-24.62c13.47 7.938 32.86 16.62 58.19 21.25c17.56 3.375 34.06-8.344 37.25-25.72c3.172-17.38-8.344-34.03-25.72-37.22c-31.23-5.719-46.84-20.06-47.13-20.31c-12.22-12.19-32.31-12.12-44.91-.375c-1 .9375-25.14 23-73.73 23s-72.73-22.06-73.38-22.62c-12.22-12.25-32.3-12.12-44.89-.375c-1 .9375-25.14 23-73.73 23S119.3 73.76 118.6 73.2C106.4 60.95 86.35 61.04 73.74 72.85C73.09 73.45 57.48 87.79 26.24 93.51c-17.38 3.188-28.89 19.84-25.72 37.22C3.713 148.1 20.31 159.8 37.78 156.4z"],
    wind: [512, 512, [], "f72e", "M32 192h320c52.94 0 96-43.06 96-96s-43.06-96-96-96h-32c-17.69 0-32 14.31-32 32s14.31 32 32 32h32c17.66 0 32 14.34 32 32s-14.34 32-32 32H32C14.31 128 0 142.3 0 160S14.31 192 32 192zM160 320H32c-17.69 0-32 14.31-32 32s14.31 32 32 32h128c17.66 0 32 14.34 32 32s-14.34 32-32 32H128c-17.69 0-32 14.31-32 32s14.31 32 32 32h32c52.94 0 96-43.06 96-96S212.9 320 160 320zM416 224H32C14.31 224 0 238.3 0 256s14.31 32 32 32h384c17.66 0 32 14.34 32 32s-14.34 32-32 32h-32c-17.69 0-32 14.31-32 32s14.31 32 32 32h32c52.94 0 96-43.06 96-96S468.9 224 416 224z"],
    "wine-bottle": [512, 512, [], "f72f", "M507.3 72.57l-67.88-67.88c-6.252-6.25-16.38-6.25-22.63 0l-22.63 22.62c-6.25 6.254-6.251 16.38-.0006 22.63l-76.63 76.63c-46.63-19.75-102.4-10.75-140.4 27.25l-158.4 158.4c-25 25-25 65.51 0 90.51l90.51 90.52c25 25 65.51 25 90.51 0l158.4-158.4c38-38 47-93.76 27.25-140.4l76.63-76.63c6.25 6.25 16.5 6.25 22.75 0l22.63-22.63C513.5 88.95 513.5 78.82 507.3 72.57zM179.3 423.2l-90.51-90.51l122-122l90.51 90.52L179.3 423.2z"],
    x: [384, 512, [120], "58", "M376.6 427.5c11.31 13.58 9.484 33.75-4.094 45.06c-5.984 4.984-13.25 7.422-20.47 7.422c-9.172 0-18.27-3.922-24.59-11.52L192 305.1l-135.4 162.5c-6.328 7.594-15.42 11.52-24.59 11.52c-7.219 0-14.48-2.438-20.47-7.422c-13.58-11.31-15.41-31.48-4.094-45.06l142.9-171.5L7.422 84.5C-3.891 70.92-2.063 50.75 11.52 39.44c13.56-11.34 33.73-9.516 45.06 4.094L192 206l135.4-162.5c11.3-13.58 31.48-15.42 45.06-4.094c13.58 11.31 15.41 31.48 4.094 45.06l-142.9 171.5L376.6 427.5z"],
    xmark: [320, 512, [128473, 10005, 10006, 10060, 215, "close", "multiply", "remove", "times"], "f00d", "M310.6 361.4c12.5 12.5 12.5 32.75 0 45.25C304.4 412.9 296.2 416 288 416s-16.38-3.125-22.62-9.375L160 301.3L54.63 406.6C48.38 412.9 40.19 416 32 416S15.63 412.9 9.375 406.6c-12.5-12.5-12.5-32.75 0-45.25l105.4-105.4L9.375 150.6c-12.5-12.5-12.5-32.75 0-45.25s32.75-12.5 45.25 0L160 210.8l105.4-105.4c12.5-12.5 32.75-12.5 45.25 0s12.5 32.75 0 45.25l-105.4 105.4L310.6 361.4z"],
    y: [384, 512, [121], "59", "M378 82.61L224 298.3v149.8c0 17.67-14.31 31.1-32 31.1S160 465.7 160 448V298.3L5.969 82.61C-4.313 68.23-.9688 48.25 13.41 37.97c14.34-10.27 34.38-6.922 44.63 7.453L192 232.1l133.1-187.5c10.28-14.37 30.28-17.7 44.63-7.453C384.1 48.25 388.3 68.23 378 82.61z"],
};
