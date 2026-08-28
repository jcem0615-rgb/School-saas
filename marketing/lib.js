const { icon } = require('./icons');

const C = {
  ink:    '1E2761',
  deep:   '141B3D',
  mist:   'CADCFC',
  paper:  'FFFFFF',
  canvas: 'F3F6FD',
  accent: 'E8A33D',
  slate:  '55608A',
  line:   'DCE4F5',
};
const F = { head: 'Cambria', body: 'Calibri' };
const W = 13.33, H = 7.5, M = 0.7, CW = W - 2 * M;

const shadow = () => ({ type: 'outer', color: '1E2761', opacity: 0.10, blur: 10, offset: 2, angle: 90 });

function bg(slide, color) { slide.background = { color }; }

/** Kicker + big title, the top block every content slide shares. */
function heading(slide, kicker, title, opts = {}) {
  const dark = !!opts.dark;
  slide.addText(kicker.toUpperCase(), {
    x: M, y: 0.48, w: CW, h: 0.26, isTextBox: true, margin: 0,
    fontFace: F.body, fontSize: 11, bold: true, charSpacing: 2.4,
    color: C.accent, align: 'left',
  });
  // Long titles step down a size rather than wrapping onto the lede
  // underneath them, which is what a fixed 32pt does at this width.
  slide.addText(title, {
    x: M, y: 0.76, w: CW, h: 0.72, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: title.length > 44 ? 28 : 32, bold: true,
    color: dark ? C.paper : C.ink, align: 'left', valign: 'top',
  });
  if (opts.lede) {
    slide.addText(opts.lede, {
      x: M, y: 1.5, w: opts.ledeW || CW * 0.82, h: 0.4, isTextBox: true, margin: 0,
      fontFace: F.body, fontSize: 13.5, color: dark ? C.mist : C.slate,
    });
  }
}

/** A rounded card with an icon disc, a heading and a short body. */
async function card(slide, it, x, y, w, h, opts = {}) {
  const tint = opts.tint || C.canvas;
  slide.addShape('roundRect', {
    x, y, w, h, rectRadius: 0.10, fill: { color: tint },
    line: { color: opts.line || C.line, width: 0.75 }, shadow: shadow(),
  });
  const discColor = opts.discColor || C.ink;
  slide.addShape('ellipse', {
    x: x + 0.26, y: y + 0.24, w: 0.52, h: 0.52,
    fill: { color: discColor }, line: { color: discColor, width: 0 },
  });
  slide.addImage({
    data: await icon(it.icon, opts.glyph || 'FFFFFF'),
    x: x + 0.385, y: y + 0.365, w: 0.25, h: 0.25,
  });
  slide.addText(it.h, {
    x: x + 0.26, y: y + 0.86, w: w - 0.52, h: 0.3, isTextBox: true, margin: 0,
    fontFace: F.body, fontSize: 14, bold: true, color: opts.headColor || C.ink,
  });
  slide.addText(it.b, {
    x: x + 0.26, y: y + 1.17, w: w - 0.52, h: h - 1.4, isTextBox: true, margin: 0,
    fontFace: F.body, fontSize: 11, color: opts.bodyColor || C.slate, lineSpacing: 15,
  });
}

/** Rows of cards. items: [{icon,h,b}] */
async function cardGrid(slide, items, o = {}) {
  const cols = o.cols || 3, gap = o.gap || 0.23;
  const y0 = o.y || 1.95, h = o.h || 2.4, vgap = o.vgap || 0.25;
  const w = (CW - gap * (cols - 1)) / cols;
  for (let i = 0; i < items.length; i++) {
    const r = Math.floor(i / cols), c = i % cols;
    await card(slide, items[i], M + c * (w + gap), y0 + r * (h + vgap), w, h, o);
  }
}

/** Compact icon + label + description rows, laid out in columns. */
async function rowList(slide, items, o = {}) {
  const cols = o.cols || 2, gap = o.gap || 0.5;
  const y0 = o.y || 1.9, rh = o.rh || 0.72;
  const per = Math.ceil(items.length / cols);
  const w = (CW - gap * (cols - 1)) / cols;
  for (let i = 0; i < items.length; i++) {
    const c = Math.floor(i / per), r = i % per;
    const x = M + c * (w + gap), y = y0 + r * rh;
    slide.addShape('ellipse', {
      x, y: y + 0.04, w: 0.42, h: 0.42,
      fill: { color: o.disc || C.mist }, line: { color: o.disc || C.mist, width: 0 },
    });
    slide.addImage({ data: await icon(items[i].icon, o.glyph || C.ink), x: x + 0.115, y: y + 0.155, w: 0.19, h: 0.19 });
    slide.addText(items[i].h, {
      x: x + 0.56, y: y - 0.02, w: w - 0.56, h: 0.26, isTextBox: true, margin: 0,
      fontFace: F.body, fontSize: 12.5, bold: true, color: o.headColor || C.ink,
    });
    slide.addText(items[i].b, {
      x: x + 0.56, y: y + 0.235, w: w - 0.56, h: 0.4, isTextBox: true, margin: 0,
      fontFace: F.body, fontSize: 10, color: o.bodyColor || C.slate, lineSpacing: 12.5,
    });
  }
}

/** A full-width tinted band for the one sentence a slide should end on. */
async function callout(slide, iconName, text, o = {}) {
  const y = o.y || 5.5, h = o.h || 0.95;
  slide.addShape('roundRect', {
    x: M, y, w: CW, h, rectRadius: 0.10,
    fill: { color: o.fill || C.ink }, line: { color: o.fill || C.ink, width: 0 },
  });
  slide.addShape('ellipse', {
    x: M + 0.32, y: y + (h - 0.5) / 2, w: 0.5, h: 0.5,
    fill: { color: C.accent }, line: { width: 0 },
  });
  slide.addImage({ data: await icon(iconName, '141B3D'),
    x: M + 0.445, y: y + (h - 0.5) / 2 + 0.125, w: 0.25, h: 0.25 });
  slide.addText(text, {
    x: M + 1.05, y, w: CW - 1.45, h, isTextBox: true, margin: 0,
    fontFace: F.head, fontSize: 15, italic: true, color: o.color || C.mist, valign: 'middle',
  });
}

module.exports = { C, F, W, H, M, CW, bg, heading, card, cardGrid, rowList, callout, shadow, icon };
