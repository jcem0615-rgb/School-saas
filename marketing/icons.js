const React = require('react');
const { renderToStaticMarkup } = require('react-dom/server');
const Fi = require('react-icons/fi');
const sharp = require('sharp');

const cache = new Map();

/** Feather icon as a base64 PNG, sized for a slide at 256px. */
async function icon(name, color) {
  const key = name + color;
  if (cache.has(key)) return cache.get(key);
  const Cmp = Fi[name];
  if (!Cmp) throw new Error('no icon named ' + name);
  const svg = renderToStaticMarkup(
    React.createElement(Cmp, { color: '#' + color, size: 256, strokeWidth: 2 })
  );
  const buf = await sharp(Buffer.from(svg)).resize(256, 256).png().toBuffer();
  const data = 'image/png;base64,' + buf.toString('base64');
  cache.set(key, data);
  return data;
}
module.exports = { icon };
