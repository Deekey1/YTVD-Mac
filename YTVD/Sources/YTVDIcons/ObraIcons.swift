// Сгенерировано scripts/gen-icons.mjs — не редактировать вручную.
// Контуры: Obra Icons, MIT, © 2025 Obra Studio BV — https://icons.obra.studio
// Star, StarFill, Playlist, Info, Share, Lock, Edit нарисованы для YTVD в той же сетке и тем же штрихом.

import CoreGraphics

/// Один контур иконки в системе координат 24×24.
public struct ObraPath: Sendable {
    public let d: String
    public let dash: [CGFloat]
    public let filled: Bool
}

public enum Icon: String, CaseIterable, Sendable {
    case add = "Add"
    case arrowDown = "ArrowDown"
    case check = "Check"
    case checkDouble = "CheckDouble"
    case chevronDown = "ChevronDown"
    case chevronRight = "ChevronRight"
    case clipboardCheck = "ClipboardCheck"
    case close = "Close"
    case copy = "Copy"
    case delete = "Delete"
    case download = "Download"
    case expand = "Expand"
    case externalLink = "ExternalLink"
    case filmSlate = "FilmSlate"
    case folder = "Folder"
    case folderDownload = "FolderDownload"
    case history = "History"
    case image = "Image"
    case layers = "Layers"
    case linkAlt = "LinkAlt"
    case minimize = "Minimize"
    case musicalNote = "MusicalNoteSingle"
    case pinAlt = "PinAlt"
    case play = "Play"
    case search = "Search"
    case settings = "Settings"
    case sparkles = "Sparkles"
    case video = "Video"
    case warningTriangle = "WarningTriangle"
    case arrowRight = "ArrowRight"
    case chevronUp = "ChevronUp"
    case clipboard = "ClipboardEmpty"
    case clock = "Clock3"
    case eye = "Eye"
    case grid = "Grid"
    case headphones = "Headphones"
    case menu = "Menu"
    case pause = "Pause"
    case playFill = "PlayFill"
    case sliders = "Sliders"
    case tv = "Tv"
    // свои, в стиле Obra
    case star = "Star"
    case starFill = "StarFill"
    case playlist = "Playlist"
    case info = "Info"
    case share = "Share"
    case lock = "Lock"
    case edit = "Edit"

    public var paths: [ObraPath] { ObraIcons.table[rawValue] ?? [] }
}

public enum ObraIcons {
    public static let table: [String: [ObraPath]] = [
        "Add": [ObraPath(d: "M12 5V19", dash: [], filled: false), ObraPath(d: "M19 12H5", dash: [], filled: false)],
        "ArrowDown": [ObraPath(d: "M12 19L12 5", dash: [], filled: false), ObraPath(d: "M18 13L12 19L6 13", dash: [], filled: false)],
        "Check": [ObraPath(d: "M4 12L9.33333 18L20 6", dash: [], filled: false)],
        "CheckDouble": [ObraPath(d: "M20 8L12 18L11.0773 16.9733", dash: [], filled: false), ObraPath(d: "M4 11L8 16L16 6", dash: [], filled: false)],
        "ChevronDown": [ObraPath(d: "M18 10L12 16L6 10", dash: [], filled: false)],
        "ChevronRight": [ObraPath(d: "M10 6L16 12L10 18", dash: [], filled: false)],
        "ClipboardCheck": [ObraPath(d: "M9 13.5L11 15.5L15 11.5", dash: [], filled: false), ObraPath(d: "M8 4H6C5.44772 4 5 4.44772 5 5V20C5 20.5523 5.44772 21 6 21H18C18.5523 21 19 20.5523 19 20V5C19 4.44772 18.5523 4 18 4H16", dash: [], filled: false), ObraPath(d: "M9 5V3C9 2.44772 9.44772 2 10 2H14C14.5523 2 15 2.44772 15 3V5C15 5.55228 14.5523 6 14 6H10C9.44772 6 9 5.55228 9 5Z", dash: [], filled: false)],
        "Close": [ObraPath(d: "M18.0001 6L6.00012 18", dash: [], filled: false), ObraPath(d: "M6.00012 6L18.0001 18", dash: [], filled: false)],
        "Copy": [ObraPath(d: "M8 10C8 8.89543 8.89543 8 10 8H19C20.1046 8 21 8.89543 21 10V19C21 20.1046 20.1046 21 19 21H10C8.89543 21 8 20.1046 8 19V10Z", dash: [], filled: false), ObraPath(d: "M5.00037 16C4.46993 16 3.96123 15.7893 3.58615 15.4142C3.21108 15.0391 3.00037 14.5304 3.00037 14V5C3.00037 4.46957 3.21108 3.96086 3.58615 3.58579C3.96123 3.21071 4.46993 3 5.00037 3H14.0004C14.5308 3 15.0395 3.21071 15.4146 3.58579C15.7897 3.96086 16.0004 4.46957 16.0004 5", dash: [], filled: false)],
        "Delete": [ObraPath(d: "M5 7L5.93366 20.0712C5.97104 20.5946 6.40648 21 6.93112 21H17.0689C17.5935 21 18.029 20.5946 18.0663 20.0712L19 7", dash: [], filled: false), ObraPath(d: "M3 7H21", dash: [], filled: false), ObraPath(d: "M8 6V4C8 3.44772 8.44772 3 9 3H15C15.5523 3 16 3.44772 16 4V6", dash: [], filled: false), ObraPath(d: "M10 11V17", dash: [], filled: false), ObraPath(d: "M14 11V17", dash: [], filled: false)],
        "Download": [ObraPath(d: "M12 16V3", dash: [], filled: false), ObraPath(d: "M16 12L12 16L8 12", dash: [], filled: false), ObraPath(d: "M5 18V20C5 20.5523 5.44772 21 6 21H18C18.5523 21 19 20.5523 19 20V18", dash: [], filled: false)],
        "Expand": [ObraPath(d: "M21 3L15 9", dash: [], filled: false), ObraPath(d: "M17 3L21 3L21 7", dash: [], filled: false), ObraPath(d: "M3 21L9 15", dash: [], filled: false), ObraPath(d: "M7 21L3 21L3 17", dash: [], filled: false)],
        "ExternalLink": [ObraPath(d: "M20 4L8.99998 15", dash: [], filled: false), ObraPath(d: "M14 4L20 4L20 10", dash: [], filled: false), ObraPath(d: "M18 14V19C18 19.5523 17.5523 20 17 20H4.99999C4.44771 20 3.99999 19.5523 3.99999 19V7C3.99999 6.44772 4.44771 6 4.99999 6H9.99999", dash: [], filled: false)],
        "FilmSlate": [ObraPath(d: "M3.75 10.5H20.25V18.75C20.25 18.9489 20.171 19.1397 20.0303 19.2803C19.8897 19.421 19.6989 19.5 19.5 19.5H4.5C4.30109 19.5 4.11032 19.421 3.96967 19.2803C3.82902 19.1397 3.75 18.9489 3.75 18.75V10.5Z", dash: [], filled: false), ObraPath(d: "M3.79032 10.5L19.5 6.35344L18.735 3.54094C18.6822 3.3532 18.5575 3.19385 18.388 3.09749C18.2184 3.00113 18.0177 2.97553 17.8294 3.02626L3.54844 6.79407C3.45511 6.81784 3.36743 6.8599 3.29048 6.91782C3.21353 6.97574 3.14885 7.04836 3.10019 7.13148C3.05152 7.21459 3.01985 7.30653 3.00699 7.40198C2.99414 7.49743 3.00037 7.59448 3.02532 7.68751L3.79032 10.5Z", dash: [], filled: false), ObraPath(d: "M6.34778 6.0553L10.8281 8.6428", dash: [], filled: false), ObraPath(d: "M11.8697 4.59845L16.35 7.18501", dash: [], filled: false)],
        "Folder": [ObraPath(d: "M3.00002 6C3.00002 5.44772 3.44773 5 4.00002 5H9.00002L11 7H20C20.5523 7 21 7.44772 21 8V18C21 18.5523 20.5523 19 20 19H4.00002C3.44773 19 3.00002 18.5523 3.00002 18V6Z", dash: [], filled: false)],
        "FolderDownload": [ObraPath(d: "M3 6C3 5.44772 3.44772 5 4 5H9L11 7H20C20.5523 7 21 7.44772 21 8V18C21 18.5523 20.5523 19 20 19H4C3.44772 19 3 18.5523 3 18V6Z", dash: [], filled: false), ObraPath(d: "M14 13.5L12 15.5M12 15.5L10 13.5M12 15.5L12 10.5", dash: [], filled: false)],
        "History": [ObraPath(d: "M12 7.19995L12 12.0999C12 12.3761 12.2239 12.5999 12.5 12.5999L16.8 12.5999", dash: [], filled: false), ObraPath(d: "M3 12C3 7.02944 7.02944 3 12 3", dash: [1, 4], filled: false), ObraPath(d: "M3 12C3 16.9706 7.02944 21 12 21C16.9706 21 21 16.9706 21 12C21 7.02944 16.9706 3 12 3", dash: [], filled: false)],
        "Image": [ObraPath(d: "M4 5C4 4.44772 4.44772 4 5 4H19C19.5523 4 20 4.44772 20 5V19C20 19.5523 19.5523 20 19 20H5C4.44772 20 4 19.5523 4 19V5Z", dash: [], filled: false), ObraPath(d: "M4 15L9 11L14 15L16 13L20 17", dash: [], filled: false), ObraPath(d: "M16.0671 8.14514H16.0791", dash: [], filled: false)],
        "Layers": [ObraPath(d: "M12 3L21 8L12 13L3 8L12 3Z", dash: [], filled: false), ObraPath(d: "M21 12L12 17L3 12", dash: [], filled: false), ObraPath(d: "M21 16L12 21L3 16", dash: [], filled: false)],
        "LinkAlt": [ObraPath(d: "M17.2 6C17.7 6 18.2 6.1 18.7 6.3C19.2 6.5 19.6 6.8 20 7.2C20.4 7.6 20.7 8 20.9 8.5C21.1 9 21.2 9.5 21.2 10C21.2 10.5 21.1 11 20.9 11.5C20.7 12 20.4 12.4 20 12.8L19 13.9L17.9 15L16.9 16L15.8 17.1C15.4 17.5 15 17.8 14.5 18C14 18.2 13.5 18.3 13 18.3C12.5 18.3 12 18.2 11.5 18C11 17.8 10.6 17.5 10.2 17.1C9.8 16.7 9.5 16.3 9.3 15.8C9.1 15.3 9 14.8 9 14.2C9 13.7 9.1 13.2 9.3 12.7C9.5 12.2 9.8 11.8 10.2 11.4L11.3 10.3", dash: [], filled: false), ObraPath(d: "M7 18.9C6.5 18.9 6 18.8 5.5 18.6C5 18.4 4.6 18.1 4.2 17.7C3.8 17.3 3.5 16.9 3.3 16.4C3.1 15.9 3 15.4 3 14.9C3 14.4 3.1 13.9 3.3 13.4C3.5 12.9 3.8 12.5 4.2 12.1L5.2 11L6.3 9.9L7.4 8.8L8.5 7.7C8.9 7.3 9.3 7 9.8 6.8C10.3 6.6 10.8 6.5 11.3 6.5C11.8 6.5 12.3 6.6 12.8 6.8C13.3 7 13.7 7.3 14.1 7.7C14.5 8.1 14.8 8.5 15 9C15.2 9.5 15.3 10 15.3 10.5C15.3 11 15.2 11.5 15 12C14.8 12.5 14.5 12.9 14.1 13.3L13 14.5", dash: [], filled: false)],
        "Minimize": [ObraPath(d: "M8.00011 3V6C8.00011 6.53043 7.7894 7.03914 7.41432 7.41421C7.03925 7.78929 6.53054 8 6.00011 8H3.00011M21.0001 8H18.0001C17.4697 8 16.961 7.78929 16.5859 7.41421C16.2108 7.03914 16.0001 6.53043 16.0001 6V3M16.0001 21V18C16.0001 17.4696 16.2108 16.9609 16.5859 16.5858C16.961 16.2107 17.4697 16 18.0001 16H21.0001M3.00011 16H6.00011C6.53054 16 7.03925 16.2107 7.41432 16.5858C7.7894 16.9609 8.00011 17.4696 8.00011 18V21", dash: [], filled: false)],
        "MusicalNoteSingle": [ObraPath(d: "M12 4V18", dash: [], filled: false), ObraPath(d: "M19 7.674V7.017C19 6.14779 18.7168 5.30223 18.1934 4.6083C17.67 3.91436 16.9348 3.40981 16.099 3.171L13.275 2.364C13.1261 2.32141 12.9694 2.31398 12.8171 2.3423C12.6649 2.37062 12.5213 2.4339 12.3977 2.52717C12.2741 2.62044 12.1738 2.74114 12.1048 2.87976C12.0358 3.01839 11.9999 3.17114 12 3.326V7L17.725 8.63599C17.8739 8.67858 18.0306 8.68601 18.1829 8.65769C18.3351 8.62937 18.4787 8.56609 18.6023 8.47282C18.7259 8.37955 18.8262 8.25885 18.8952 8.12023C18.9642 7.9816 19.0001 7.82885 19 7.674Z", dash: [], filled: false), ObraPath(d: "M12 18C12 18.7956 11.6839 19.5587 11.1213 20.1213C10.5587 20.6839 9.79565 21 9 21C8.20435 21 7.44129 20.6839 6.87868 20.1213C6.31607 19.5587 6 18.7956 6 18C6 16.343 7.343 16 9 16C10.657 16 12 16.343 12 18Z", dash: [], filled: false)],
        "PinAlt": [ObraPath(d: "M5 10.726L2 11.231L11.23 2L10.726 5M12 16.881L11.23 18.923L18.923 11.231L16.881 12M15.077 15.077L21 21M3.538 9.692L9.692 3.538L9.928 3.879C12.0722 6.97606 14.5453 9.83201 17.304 12.397L17.539 12.615L12.615 17.538L12.397 17.304C9.83233 14.5454 6.97671 12.0723 3.88 9.928L3.54 9.692H3.538Z", dash: [], filled: false)],
        "Play": [ObraPath(d: "M7 6.74104C7 5.96925 7.83721 5.48838 8.50387 5.87726L17.5192 11.1362C18.1807 11.5221 18.1807 12.4779 17.5192 12.8638L8.50387 18.1227C7.83721 18.5116 7 18.0308 7 17.259V6.74104Z", dash: [], filled: false)],
        "Search": [ObraPath(d: "M17 10C17 13.866 13.866 17 10 17C6.13401 17 3 13.866 3 10C3 6.13401 6.13401 3 10 3C13.866 3 17 6.13401 17 10Z", dash: [], filled: false), ObraPath(d: "M21 21L15 15", dash: [], filled: false)],
        "Settings": [ObraPath(d: "M10.287 4.13982C10.719 2.33897 13.2809 2.33897 13.713 4.13982C13.9923 5.3038 15.3262 5.85632 16.3467 5.23073C17.9256 4.26286 19.7372 6.07439 18.7693 7.65331C18.1437 8.67383 18.6962 10.0077 19.8602 10.287C21.661 10.7191 21.661 13.281 19.8602 13.713C18.6962 13.9923 18.1437 15.3262 18.7693 16.3467C19.7372 17.9256 17.9256 19.7372 16.3467 18.7693C15.3262 18.1437 13.9923 18.6962 13.713 19.8602C13.2809 21.6611 10.719 21.6611 10.287 19.8602C10.0077 18.6962 8.67382 18.1437 7.65329 18.7693C6.07438 19.7372 4.26284 17.9256 5.23072 16.3467C5.8563 15.3262 5.30378 13.9923 4.13981 13.713C2.33896 13.281 2.33896 10.7191 4.13981 10.287C5.30378 10.0077 5.8563 8.67384 5.23072 7.65331C4.26284 6.07439 6.07438 4.26286 7.65329 5.23073C8.67382 5.85632 10.0077 5.3038 10.287 4.13982Z", dash: [], filled: false), ObraPath(d: "M15 12C15 12.7956 14.6839 13.5587 14.1213 14.1213C13.5587 14.6839 12.7956 15 12 15C11.2044 15 10.4413 14.6839 9.87868 14.1213C9.31607 13.5587 9 12.7956 9 12C9 11.2044 9.31607 10.4413 9.87868 9.87868C10.4413 9.31607 11.2044 9 12 9C12.7956 9 13.5587 9.31607 14.1213 9.87868C14.6839 10.4413 15 11.2044 15 12V12Z", dash: [], filled: false)],
        "Sparkles": [ObraPath(d: "M11.7845 10.0777L12 9L12.2155 10.0777C12.6906 12.4528 14.5472 14.3094 16.9223 14.7845L18 15L16.9223 15.2155C14.5472 15.6906 12.6906 17.5472 12.2155 19.9223L12 21L11.7845 19.9223C11.3094 17.5472 9.45284 15.6906 7.07768 15.2155L6 15L7.07768 14.7845C9.45285 14.3094 11.3094 12.4528 11.7845 10.0777Z", dash: [], filled: false), ObraPath(d: "M5.89223 3.53884L6 3L6.10777 3.53884C6.34528 4.72642 7.27358 5.65472 8.46116 5.89223L9 6L8.46116 6.10777C7.27358 6.34528 6.34528 7.27358 6.10777 8.46116L6 9L5.89223 8.46116C5.65472 7.27358 4.72642 6.34528 3.53884 6.10777L3 6L3.53884 5.89223C4.72642 5.65472 5.65472 4.72642 5.89223 3.53884Z", dash: [], filled: false), ObraPath(d: "M17.9282 4.35923L18 4L18.0718 4.35923C18.2302 5.15095 18.8491 5.76981 19.6408 5.92815L20 6L19.6408 6.07185C18.8491 6.23019 18.2302 6.84905 18.0718 7.64077L18 8L17.9282 7.64077C17.7698 6.84905 17.1509 6.23019 16.3592 6.07185L16 6L16.3592 5.92815C17.1509 5.76981 17.7698 5.15095 17.9282 4.35923Z", dash: [], filled: false)],
        "Video": [ObraPath(d: "M19 4H5C4.44772 4 4 4.44772 4 5V19C4 19.5523 4.44772 20 5 20H19C19.5523 20 20 19.5523 20 19V5C20 4.44772 19.5523 4 19 4Z", dash: [], filled: false), ObraPath(d: "M19 4H5C4.44772 4 4 4.44772 4 5V11C4 11.5523 4.44772 12 5 12H19C19.5523 12 20 11.5523 20 11V5C20 4.44772 19.5523 4 19 4Z", dash: [], filled: false), ObraPath(d: "M8 4H5C4.44772 4 4 4.44772 4 5V19C4 19.5523 4.44772 20 5 20H8V4Z", dash: [], filled: false), ObraPath(d: "M8 4H5C4.44772 4 4 4.44772 4 5V7C4 7.55228 4.44772 8 5 8H8V4Z", dash: [], filled: false), ObraPath(d: "M8 8H4V12H8V8Z", dash: [], filled: false), ObraPath(d: "M8 12H4V16H8V12Z", dash: [], filled: false), ObraPath(d: "M19 4H16V20H19C19.5523 20 20 19.5523 20 19V5C20 4.44772 19.5523 4 19 4Z", dash: [], filled: false), ObraPath(d: "M19 4H16V7C16 7.55228 16.4477 8 17 8H20V5C20 4.44772 19.5523 4 19 4Z", dash: [], filled: false), ObraPath(d: "M20 8H16V12H20V8Z", dash: [], filled: false), ObraPath(d: "M20 12H16V16H20V12Z", dash: [], filled: false)],
        "WarningTriangle": [ObraPath(d: "M11.8737 13.5L11.8737 9.97894", dash: [], filled: false), ObraPath(d: "M10.8118 4.41764C11.2617 3.56283 12.4857 3.56283 12.9356 4.41764L20.4216 18.6411C20.8422 19.4402 20.2627 20.4 19.3597 20.4H4.38764C3.48462 20.4 2.90516 19.4402 3.32574 18.6411L10.8118 4.41764Z", dash: [], filled: false), ObraPath(d: "M11.8736 16.6105H11.8825", dash: [], filled: false)],
        "ArrowRight": [ObraPath(d: "M19 12L5 12", dash: [], filled: false), ObraPath(d: "M13 6L19 12L13 18", dash: [], filled: false)],
        "ChevronUp": [ObraPath(d: "M6 14L12 8L18 14", dash: [], filled: false)],
        "ClipboardEmpty": [ObraPath(d: "M8 4H6C5.44772 4 5 4.44772 5 5V20C5 20.5523 5.44772 21 6 21H18C18.5523 21 19 20.5523 19 20V5C19 4.44772 18.5523 4 18 4H16", dash: [], filled: false), ObraPath(d: "M9 5V3C9 2.44772 9.44772 2 10 2H14C14.5523 2 15 2.44772 15 3V5C15 5.55228 14.5523 6 14 6H10C9.44772 6 9 5.55228 9 5Z", dash: [], filled: false)],
        "Clock3": [ObraPath(d: "M12 7.19995L12 12.0999C12 12.3761 12.2239 12.5999 12.5 12.5999L16.8 12.5999", dash: [], filled: false)],
        "Eye": [ObraPath(d: "M3 12C7 4 17 4 21 12C17 20 7 20 3 12Z", dash: [], filled: false), ObraPath(d: "M12 15C13.6569 15 15 13.6569 15 12C15 10.3431 13.6569 9 12 9C10.3431 9 9 10.3431 9 12C9 13.6569 10.3431 15 12 15Z", dash: [], filled: true)],
        "Grid": [ObraPath(d: "M19 4H15C14.4477 4 14 4.44772 14 5V9C14 9.55228 14.4477 10 15 10H19C19.5523 10 20 9.55228 20 9V5C20 4.44772 19.5523 4 19 4Z", dash: [], filled: false), ObraPath(d: "M19 14H15C14.4477 14 14 14.4477 14 15V19C14 19.5523 14.4477 20 15 20H19C19.5523 20 20 19.5523 20 19V15C20 14.4477 19.5523 14 19 14Z", dash: [], filled: false), ObraPath(d: "M9 4H5C4.44772 4 4 4.44772 4 5V9C4 9.55228 4.44772 10 5 10H9C9.55228 10 10 9.55228 10 9V5C10 4.44772 9.55228 4 9 4Z", dash: [], filled: false), ObraPath(d: "M9 14H5C4.44772 14 4 14.4477 4 15V19C4 19.5523 4.44772 20 5 20H9C9.55228 20 10 19.5523 10 19V15C10 14.4477 9.55228 14 9 14Z", dash: [], filled: false)],
        "Headphones": [ObraPath(d: "M20.0614 16.7897L19.8026 17.7556C19.3738 19.356 17.7288 20.3057 16.1284 19.8769L15.1624 19.6181L16.9742 12.8566L17.9401 13.1154C19.5405 13.5443 20.4902 15.1893 20.0614 16.7897ZM20.0614 16.7897C20.0614 16.7897 21.1667 15.0002 21 12.0002C20.8334 9.00017 18.9 3.00017 12.5 3.00017L11.4585 3.00017C5.05848 3.00017 3.12515 9.00017 2.95848 12.0002C2.79182 15.0002 3.89712 16.7897 3.89712 16.7897M3.89712 16.7897L4.15594 17.7556C4.58476 19.356 6.22977 20.3057 7.83017 19.8769L8.7961 19.6181L6.98436 12.8566L6.01844 13.1154C4.41804 13.5443 3.46829 15.1893 3.89712 16.7897Z", dash: [], filled: false)],
        "Menu": [ObraPath(d: "M19 12H5", dash: [], filled: false), ObraPath(d: "M19 7H5", dash: [], filled: false), ObraPath(d: "M19 17H5", dash: [], filled: false)],
        "Pause": [ObraPath(d: "M9 7V17", dash: [], filled: false), ObraPath(d: "M15 7V17", dash: [], filled: false)],
        "PlayFill": [ObraPath(d: "M9.00774 5.01349C7.67443 4.23573 6 5.19747 6 6.74105V17.259C6 18.8026 7.67443 19.7643 9.00774 18.9865L18.0231 13.7276C19.3461 12.9558 19.3461 11.0442 18.0231 10.2725L9.00774 5.01349Z", dash: [], filled: true)],
        "Sliders": [ObraPath(d: "M4.00012 21V14", dash: [], filled: false), ObraPath(d: "M4.00012 10V3", dash: [], filled: false), ObraPath(d: "M12.0001 21V12", dash: [], filled: false), ObraPath(d: "M12.0001 8V3", dash: [], filled: false), ObraPath(d: "M20.0004 21V16", dash: [], filled: false), ObraPath(d: "M20.0004 12V3", dash: [], filled: false), ObraPath(d: "M1.00012 14H7.00012", dash: [], filled: false), ObraPath(d: "M9.00012 8H15.0001", dash: [], filled: false), ObraPath(d: "M17.0004 16H23.0004", dash: [], filled: false)],
        "Tv": [ObraPath(d: "M19.9999 3H3.99988C2.89531 3 1.99988 3.89543 1.99988 5V15C1.99988 16.1046 2.89531 17 3.99988 17H19.9999C21.1044 17 21.9999 16.1046 21.9999 15V5C21.9999 3.89543 21.1044 3 19.9999 3Z", dash: [], filled: false), ObraPath(d: "M4.99988 21H18.9999", dash: [], filled: false)],
        "Star": [ObraPath(d: "M12 3.5L14.63 8.83L20.51 9.69L16.25 13.84L17.26 19.7L12 16.93L6.74 19.7L7.75 13.84L3.49 9.69L9.37 8.83L12 3.5Z", dash: [], filled: false)],
        "StarFill": [ObraPath(d: "M12 3.5L14.63 8.83L20.51 9.69L16.25 13.84L17.26 19.7L12 16.93L6.74 19.7L7.75 13.84L3.49 9.69L9.37 8.83L12 3.5Z", dash: [], filled: true)],
        "Playlist": [ObraPath(d: "M4 6H17", dash: [], filled: false), ObraPath(d: "M4 11H17", dash: [], filled: false), ObraPath(d: "M4 16H10", dash: [], filled: false), ObraPath(d: "M14 14.2V20.3C14 20.68 14.41 20.92 14.74 20.73L19.93 17.68C20.26 17.49 20.26 17.01 19.93 16.82L14.74 13.77C14.41 13.58 14 13.82 14 14.2Z", dash: [], filled: false)],
        "Info": [ObraPath(d: "M21 12C21 16.9706 16.9706 21 12 21C7.02944 21 3 16.9706 3 12C3 7.02944 7.02944 3 12 3C16.9706 3 21 7.02944 21 12Z", dash: [], filled: false), ObraPath(d: "M12 11V16.5", dash: [], filled: false), ObraPath(d: "M12 7.5H12.01", dash: [], filled: false)],
        "Share": [ObraPath(d: "M12 3V15", dash: [], filled: false), ObraPath(d: "M8 7L12 3L16 7", dash: [], filled: false), ObraPath(d: "M8 11H6C5.44772 11 5 11.4477 5 12V20C5 20.5523 5.44772 21 6 21H18C18.5523 21 19 20.5523 19 20V12C19 11.4477 18.5523 11 18 11H16", dash: [], filled: false)],
        "Lock": [ObraPath(d: "M6 11C6 10.4477 6.44772 10 7 10H17C17.5523 10 18 10.4477 18 11V19C18 19.5523 17.5523 20 17 20H7C6.44772 20 6 19.5523 6 19V11Z", dash: [], filled: false), ObraPath(d: "M8.5 10V7.5C8.5 5.567 10.067 4 12 4C13.933 4 15.5 5.567 15.5 7.5V10", dash: [], filled: false)],
        "Edit": [ObraPath(d: "M4 20H8L18.5 9.5C19.33 8.67 19.33 7.33 18.5 6.5L17.5 5.5C16.67 4.67 15.33 4.67 14.5 5.5L4 16V20Z", dash: [], filled: false), ObraPath(d: "M13 7L17 11", dash: [], filled: false)],
    ]
}
