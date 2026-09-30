// Генерирует Sources/YTVDIcons/ObraIcons.swift из выгрузки Obra Icons — общий для Mac и iPhone.
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
  // для приложения на iPhone
  ArrowRight: "arrowRight", ChevronUp: "chevronUp", ClipboardEmpty: "clipboard", Clock3: "clock",
  Eye: "eye", Grid: "grid", Headphones: "headphones", Menu: "menu", Pause: "pause",
  PlayFill: "playFill", Sliders: "sliders", Tv: "tv",
};

// Своих в выгрузке нет — нарисованы в той же сетке 24×24 и тем же штрихом, что Obra.
const CUSTOM = {
  Star: ["star", [["M12 3.5L14.63 8.83L20.51 9.69L16.25 13.84L17.26 19.7L12 16.93L6.74 19.7L7.75 13.84L3.49 9.69L9.37 8.83L12 3.5Z", false]]],
  StarFill: ["starFill", [["M12 3.5L14.63 8.83L20.51 9.69L16.25 13.84L17.26 19.7L12 16.93L6.74 19.7L7.75 13.84L3.49 9.69L9.37 8.83L12 3.5Z", true]]],
  Playlist: ["playlist", [["M4 6H17", false], ["M4 11H17", false], ["M4 16H10", false],
    ["M14 14.2V20.3C14 20.68 14.41 20.92 14.74 20.73L19.93 17.68C20.26 17.49 20.26 17.01 19.93 16.82L14.74 13.77C14.41 13.58 14 13.82 14 14.2Z", false]]],
  Info: ["info", [["M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z", false],
    ["M12 11V16.5", false], ["M12 7.5H12.01", false]]],
  Share: ["share", [["M12 3V15", false], ["M8 7L12 3L16 7", false],
    ["M8 11H6C5.44772 11 5 11.4477 5 12V20C5 20.5523 5.44772 21 6 21H18C18.5523 21 19 20.5523 19 20V12C19 11.4477 18.5523 11 18 11H16", false]]],
  Lock: ["lock", [["M6 11C6 10.4477 6.44772 10 7 10H17C17.5523 10 18 10.4477 18 11V19C18 19.5523 17.5523 20 17 20H7C6.44772 20 6 19.5523 6 19V11Z", false],
    ["M8.5 10V7.5C8.5 5.567 10.067 4 12 4C13.933 4 15.5 5.567 15.5 7.5V10", false]]],
  Edit: ["edit", [["M4 20H8L18.5 9.5C19.33 8.67 19.33 7.33 18.5 6.5L17.5 5.5C16.67 4.67 15.33 4.67 14.5 5.5L4 16V20Z", false],
    ["M13 7L17 11", false]]],
};

const attr = (el, name) => (el.match(new RegExp(`${name}="([^"]*)"`)) || [, null])[1];

const out = [];
out.push(`// Сгенерировано scripts/gen-icons.mjs — не редактировать вручную.`);
out.push(`// Контуры: Obra Icons, MIT, © 2025 Obra Studio BV — https://icons.obra.studio`);
out.push(`// Star, StarFill, Playlist, Info, Share, Lock, Edit нарисованы для YTVD в той же сетке и тем же штрихом.`);
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
out.push(`    // свои, в стиле Obra`);
for (const [name, [swiftCase]] of Object.entries(CUSTOM)) out.push(`    case ${swiftCase} = "${name}"`);
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
for (const [name, [, paths]] of Object.entries(CUSTOM)) {
  const items = paths.map(([d, filled]) => `ObraPath(d: "${d}", dash: [], filled: ${filled})`);
  out.push(`        "${name}": [${items.join(", ")}],`);
}
out.push(`    ]`);
out.push(`}`);

if (missing.length) throw new Error("нет контуров для: " + missing.join(", "));

const dest = join(root, "Sources/YTVDIcons/ObraIcons.swift");
writeFileSync(dest, out.join("\n") + "\n");
console.log(`ok: ${dest} (${Object.keys(USED).length} из Obra + ${Object.keys(CUSTOM).length} своих)`);
