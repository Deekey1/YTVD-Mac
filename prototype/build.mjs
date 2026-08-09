// Собирает index.html из ui.template.html, подставляя SVG-контуры Obra Icons.
// Запуск:  node prototype/build.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const icons = readFileSync(join(here, "_obra-icons.json"), "utf8");
const tpl = readFileSync(join(here, "ui.template.html"), "utf8");

if (!tpl.includes("__ICONS__")) throw new Error("В шаблоне нет плейсхолдера __ICONS__");

const out = tpl.replace("__ICONS__", icons);
writeFileSync(join(here, "index.html"), out);
console.log(`ok: index.html (${(out.length / 1024).toFixed(1)} КБ)`);
