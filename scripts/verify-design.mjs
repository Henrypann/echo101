import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const tokens = JSON.parse(fs.readFileSync(path.join(root, 'Design/tokens.json')));
const catalog = path.join(root, 'Echo101/Assets.xcassets');
const pairs = [['text','background'],['text','surface'],['textSecondary','surface'],['onAction','action'],['onAccent','accent'],['accentText','accentSoft'],['success','successSurface'],['warning','warningSurface'],['danger','dangerSurface'],['onDisabled','disabled'],['controlBorder','surface'],['focus','surface']];
const luminance = hex => hex.slice(1).match(/../g).map(c => parseInt(c,16)/255).map(c => c <= .04045 ? c / 12.92 : ((c+.055)/1.055)**2.4).reduce((sum,c,i) => sum + c*[.2126,.7152,.0722][i],0);
let checked = 0;
for (const theme of ['light','dark']) {
  for (const [foreground, background] of pairs) {
    const a = luminance(tokens.color[theme][foreground]), b = luminance(tokens.color[theme][background]);
    const ratio = (Math.max(a,b)+.05)/(Math.min(a,b)+.05);
    assert(ratio >= (['controlBorder','focus'].includes(foreground) ? 3 : 4.5), `${theme}: ${foreground}/${background} has insufficient contrast`);
    checked++;
  }
}
for (const [key, value] of Object.entries(tokens.color.light)) {
  const set = JSON.parse(fs.readFileSync(path.join(catalog,`Echo${key[0].toUpperCase()+key.slice(1)}.colorset/Contents.json`)));
  for (const [index, hex] of [value,tokens.color.dark[key]].entries()) {
    const c=set.colors[index].color.components;
    assert.equal('#'+[c.red,c.green,c.blue].map(v => Number(v).toString(16).padStart(2,'0')).join('').toUpperCase(), hex);
  }
  assert.equal(set.colors[1].appearances[0].value,'dark');
}
for (const name of ['echo-logo','echo-mark',...['welcome','listening','demonstrate','waiting','encourage','goodbye'].map(s=>'mascot-'+s),...['toys','food','ready','bedtime'].map(s=>'scene-'+s)]) {
  const folder=path.join(catalog,name+'.imageset');
  const set=JSON.parse(fs.readFileSync(path.join(folder,'Contents.json')));
  for (const image of set.images) assert(fs.statSync(path.join(folder,image.filename)).size>0);
}
for (const name of ['default','dark','mono']) {
  const png=fs.readFileSync(path.join(catalog,`AppIcon.appiconset/${name}.png`));
  assert.equal(png.subarray(1,4).toString(),'PNG'); assert.equal(png.readUInt32BE(16),1024); assert.equal(png.readUInt32BE(20),1024);
}
console.log(`PASS: ${checked} contrast pairs, ${Object.keys(tokens.color.light).length} adaptive colour sets, 12 artwork sets, 3 app icon variants.`);
