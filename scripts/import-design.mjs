// Mechanical import of the user-provided Echo visual package; never changes source artwork.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = process.argv[2];
if (!source || !fs.existsSync(path.join(source, 'tokens.json'))) throw new Error('Pass the Echo visual package directory.');
const tokens = JSON.parse(fs.readFileSync(path.join(source, 'tokens.json'), 'utf8'));
const catalog = path.join(root, 'Echo101/Assets.xcassets');
const put = (file, value) => { fs.mkdirSync(path.dirname(file), { recursive: true }); fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n'); };
const info = { author: 'xcode', version: 1 };
put(path.join(catalog, 'Contents.json'), { info });
put(path.join(root, 'Design/tokens.json'), tokens);
fs.copyFileSync(path.join(source, 'Echo-Visual-Spec-v1.0.md'), path.join(root, 'Design/Echo-Visual-Spec-v1.0.md'));
const rgba = hex => ({ 'color-space': 'srgb', components: { red: `0x${hex.slice(1,3)}`, green: `0x${hex.slice(3,5)}`, blue: `0x${hex.slice(5,7)}`, alpha: '1.000' } });
for (const [key, value] of Object.entries(tokens.color.light)) {
  put(path.join(catalog, `Echo${key[0].toUpperCase()+key.slice(1)}.colorset/Contents.json`), {
    colors: [{ idiom: 'universal', color: rgba(value) }, { idiom: 'universal', appearances: [{ appearance: 'luminosity', value: 'dark' }], color: rgba(tokens.color.dark[key]) }], info
  });
}
for (const [key, value] of Object.entries(tokens.brand)) {
  put(path.join(catalog, `EchoBrand${key[0].toUpperCase()+key.slice(1)}.colorset/Contents.json`), { colors: [{ idiom: 'universal', color: rgba(value) }], info });
}
const assets = {
  'echo-logo': ['brand/lockup-horizontal-primary.png', 'brand/lockup-horizontal-reversed.png'],
  'echo-mark': ['brand/mark.png'],
  ...Object.fromEntries(['welcome','listening','demonstrate','waiting','encourage','goodbye'].map(name => [`mascot-${name}`, [`mascot/${name}.png`]])),
  ...Object.fromEntries(['toys','food','ready','bedtime'].map(name => [`scene-${name}`, [`scenes/${name}.png`]]))
};
for (const [name, files] of Object.entries(assets)) {
  const folder = path.join(catalog, `${name}.imageset`);
  fs.mkdirSync(folder, { recursive: true });
  const images = files.map((file, index) => {
    const filename = index ? 'dark.png' : 'image.png';
    fs.copyFileSync(path.join(source, 'assets', file), path.join(folder, filename));
    return { idiom: 'universal', filename, ...(index ? { appearances: [{ appearance: 'luminosity', value: 'dark' }] } : {}) };
  });
  put(path.join(folder, 'Contents.json'), { images, info });
}
const icon = path.join(catalog, 'AppIcon.appiconset');
fs.mkdirSync(icon, { recursive: true });
for (const name of ['default','dark','mono']) fs.copyFileSync(path.join(source, `assets/app-icon/${name}.png`), path.join(icon, `${name}.png`));
put(path.join(icon, 'Contents.json'), { images: [
  { idiom: 'universal', platform: 'ios', size: '1024x1024', filename: 'default.png' },
  { idiom: 'universal', platform: 'ios', size: '1024x1024', filename: 'dark.png', appearances: [{ appearance: 'luminosity', value: 'dark' }] },
  { idiom: 'universal', platform: 'ios', size: '1024x1024', filename: 'mono.png', appearances: [{ appearance: 'luminosity', value: 'tinted' }] }
], info });
console.log(`Imported ${Object.keys(assets).length} artwork sets, ${Object.keys(tokens.color.light).length} adaptive colours and app icons.`);
