// Генерирует Sources/YTVDCore/Generated/ObraIcons.swift из выгрузки Obra Icons.
// Запуск: node scripts/gen-icons.mjs
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");
const src = JSON.parse(readFileSync(join(root, "../prototype/_obra-icons.json"), "utf8"));

// имя в наборе -> case в Swift
const USED = {
  Add: "add", ArrowDown: "arrowDown", Check: "check", CheckDouble: "checkDouble",
  ChevronDown: "chevronDown", ChevronRight: "chevronRight", ClipboardCheck: "clipboardCheck",
  Close: "close", Copy: "copy", Delete: "delete", Download: "download", Expand: "expand",
  ExternalLink: "externalLink", FilmSlate: "filmSlate", Folder: "folder",
  FolderDownload: "folderDownload", History: "history", Image: "image", Layers: "layers",
  LinkAlt: "linkAlt", Minimize: "minimize", MusicalNoteSingle: "musicalNote", PinAlt: "pinAlt",
  Play: "play", Search: "search", Settings: "settings", Sparkles: "sparkles", Video: "video",
  WarningTriangle: "warningTriangle",
};

const attr = (el, name) => (el.match(new RegExp(`${name}="([^"]*)"`)) || [, null])[1];

const out = [];
out.push(`// Сгенерировано scripts/gen-icons.mjs — не редактировать вручную.`);
out.push(`// Контуры: Obra Icons, MIT, © 2025 Obra Studio BV — https://icons.obra.studio`);
out.push(``);
out.push(`import CoreGraphics`);
out.push(``);
out.push(`/// Один контур иконки в системе координат 24×24.`);
out.push(`public struct ObraPath: Sendable {`);
out.push(`    public let d: String`);
out.push(`    public let dash: [CGFloat]`);
out.push(`    public let filled: Bool`);
out.push(`}`);
out.push(``);
out.push(`public enum Icon: String, CaseIterable, Sendable {`);
for (const [name, swiftCase] of Object.entries(USED)) out.push(`    case ${swiftCase} = "${name}"`);
out.push(``);
out.push(`    public var paths: [ObraPath] { ObraIcons.table[rawValue] ?? [] }`);
out.push(`}`);
out.push(``);
out.push(`public enum ObraIcons {`);
out.push(`    public static let table: [String: [ObraPath]] = [`);

let missing = [];
for (const name of Object.keys(USED)) {
  const body = src[name];
  if (!body) { missing.push(name); continue; }
  const els = body.match(/<path[^>]*\/>/g) || [];
  const items = els.map(el => {
    const d = attr(el, "d");
    const dash = (attr(el, "stroke-dasharray") || "").trim();
    const fill = attr(el, "fill");
    const dashArr = dash ? dash.split(/[\s,]+/).map(Number).filter(n => !isNaN(n)) : [];
    const filled = fill != null && fill !== "none";
    return `ObraPath(d: "${d}", dash: [${dashArr.join(", ")}], filled: ${filled})`;
  });
  out.push(`        "${name}": [${items.join(", ")}],`);
}
out.push(`    ]`);
out.push(`}`);

if (missing.length) throw new Error("нет контуров для: " + missing.join(", "));

const dest = join(root, "Sources/YTVDCore/Generated/ObraIcons.swift");
writeFileSync(dest, out.join("\n") + "\n");
console.log(`ok: ${dest} (${Object.keys(USED).length} иконок)`);
