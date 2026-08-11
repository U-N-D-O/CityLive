#!/usr/bin/env python3
"""Preview and edit curated Nuuk City Live places.

Run from the repository root:

    python tool/places/preview_places.py

The editor saves assets/data/curated_places.json and regenerates
lib/src/data/nuuk_places.dart so the Flutter app picks up the same changes.
"""

from __future__ import annotations

import json
import pathlib
import hashlib
import re
import shutil
import sys
import tkinter as tk
import unicodedata
import webbrowser
from tkinter import filedialog, messagebox, ttk
from typing import Any, Dict, List, Optional

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "assets" / "data" / "curated_places.json"
SEARCH_INDEX_PATH = ROOT / "assets" / "data" / "nuuk_search_index.json"
DART_PATH = ROOT / "lib" / "src" / "data" / "nuuk_places.dart"
PLACE_PICTURES_DIR = ROOT / "assets" / "pictures" / "places"

CATEGORIES = [
    "groceries",
    "cafe",
    "pharmacy",
    "fuel",
    "culture",
    "publicService",
]

FIELDS = [
    "id",
    "name",
    "category",
    "latitude",
    "longitude",
    "address",
    "imageUrl",
    "phone",
    "weekdayOpen",
    "weekdayClose",
    "saturdayOpen",
    "saturdayClose",
    "sundayOpen",
    "sundayClose",
]

DEFAULT_OPENING_HOURS = {
    "weekdayOpen": 0,
    "weekdayClose": 0,
    "saturdayOpen": None,
    "saturdayClose": None,
    "sundayOpen": None,
    "sundayClose": None,
}


def dart_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def nullable_hour(value: object) -> str:
    if value in (None, ""):
        return "null"
    return str(int(value))


def load_places() -> List[Dict[str, Any]]:
    with CATALOG_PATH.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def load_search_index_entries() -> List[Dict[str, Any]]:
    with SEARCH_INDEX_PATH.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    return data.get("entries", [])


def save_places(places: List[Dict[str, Any]]) -> None:
    CATALOG_PATH.write_text(
        json.dumps(places, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def generate_dart(places: List[Dict[str, Any]]) -> None:
    lines = [
        "import 'package:latlong2/latlong.dart';",
        "",
        "import '../models/opening_hours.dart';",
        "import '../models/place.dart';",
        "",
        "const nuukPlaces = <Place>[",
    ]

    for place in places:
        hours = place["openingHours"]
        phone = str(place.get("phone") or "")
        lines.extend(
            [
                "  Place(",
                f"    id: {dart_string(str(place['id']))},",
                f"    name: {dart_string(str(place['name']))},",
                f"    category: PlaceCategory.{place['category']},",
                f"    coordinate: LatLng({place['latitude']}, {place['longitude']}),",
                f"    address: {dart_string(str(place['address']))},",
                "    openingHours: OpeningHours(",
                f"      weekdayOpen: {int(hours['weekdayOpen'])},",
                f"      weekdayClose: {int(hours['weekdayClose'])},",
                f"      saturdayOpen: {nullable_hour(hours.get('saturdayOpen'))},",
                f"      saturdayClose: {nullable_hour(hours.get('saturdayClose'))},",
                f"      sundayOpen: {nullable_hour(hours.get('sundayOpen'))},",
                f"      sundayClose: {nullable_hour(hours.get('sundayClose'))},",
                "    ),",
                f"    imageUrl: {dart_string(str(place['imageUrl']))},",
            ]
        )
        if phone:
            lines.append(f"    phone: {dart_string(phone)},")
        lines.extend(["  ),"])

    lines.append("];")
    lines.append("")
    DART_PATH.write_text("\n".join(lines), encoding="utf-8")


def parse_hour(value: str) -> Optional[int]:
    stripped = value.strip()
    if not stripped:
        return None
    hour = int(stripped)
    if hour < 0 or hour > 24:
        raise ValueError("hours must be between 0 and 24")
    return hour


def slugify(value: str) -> str:
    ascii_value = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii")
    slug = re.sub(r"[^a-z0-9]+", "-", ascii_value.lower()).strip("-")
    return slug[:48].strip("-") or "place"


def index_place_id(entry: Dict[str, Any]) -> str:
    source_id = str(entry.get("id") or entry.get("searchText") or entry.get("label") or "place")
    digest = hashlib.sha1(source_id.encode("utf-8")).hexdigest()[:8]
    return f"index-{slugify(str(entry.get('label') or 'place'))}-{digest}"


def category_for_index_entry(entry: Dict[str, Any]) -> str:
    category = str(entry.get("category") or "").lower()
    group = str(entry.get("group") or "").lower()
    icon = str(entry.get("icon") or "").lower()

    if any(value in category for value in ["grocery", "convenience", "supermarket"]):
        return "groceries"
    if group == "food & drink" or any(
        value in category for value in ["restaurant", "cafe", "fast food", "bar"]
    ):
        return "cafe"
    if "pharmacy" in category:
        return "pharmacy"
    if "fuel" in category or icon == "fuel":
        return "fuel"
    if group == "attractions" or any(
        value in category
        for value in ["museum", "theatre", "artwork", "culture", "community centre"]
    ):
        return "culture"
    return "publicService"


def place_from_index_entry(entry: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "id": index_place_id(entry),
        "name": str(entry.get("label") or "Unnamed place"),
        "category": category_for_index_entry(entry),
        "latitude": float(entry["latitude"]),
        "longitude": float(entry["longitude"]),
        "address": str(entry.get("address") or entry.get("subcategory") or entry.get("category") or ""),
        "imageUrl": "",
        "phone": "",
        "openingHours": dict(DEFAULT_OPENING_HOURS),
    }


def import_index_places(places: List[Dict[str, Any]]) -> int:
    existing_ids = {str(place.get("id")) for place in places}
    imported = []
    for entry in load_search_index_entries():
        if entry.get("group") == "Address" or entry.get("category") == "Place":
            continue
        if not entry.get("label") or "latitude" not in entry or "longitude" not in entry:
            continue
        place = place_from_index_entry(entry)
        if place["id"] in existing_ids:
            continue
        existing_ids.add(place["id"])
        imported.append(place)

    imported.sort(key=lambda place: (place["category"], place["name"].casefold()))
    places.extend(imported)
    return len(imported)


class PlaceEditor(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Nuuk City Live Places")
        self.geometry("1180x680")
        self.places = load_places()
        self.selected_index = 0
        self.vars: Dict[str, tk.StringVar] = {
            field: tk.StringVar() for field in FIELDS
        }

        self.columnconfigure(1, weight=1)
        self.rowconfigure(0, weight=1)

        self.place_list = tk.Listbox(self, exportselection=False)
        self.place_list.grid(row=0, column=0, sticky="nsew", padx=(12, 8), pady=12)
        self.place_list.bind("<<ListboxSelect>>", self.on_select)

        editor = ttk.Frame(self)
        editor.grid(row=0, column=1, sticky="nsew", padx=(0, 12), pady=12)
        editor.columnconfigure(1, weight=1)

        row = 0
        for field in FIELDS:
            ttk.Label(editor, text=field).grid(row=row, column=0, sticky="w", pady=4)
            if field == "category":
                control = ttk.Combobox(
                    editor,
                    textvariable=self.vars[field],
                    values=CATEGORIES,
                    state="readonly",
                )
            else:
                control = ttk.Entry(editor, textvariable=self.vars[field])
            control.grid(row=row, column=1, sticky="ew", pady=4)
            row += 1

        buttons = ttk.Frame(editor)
        buttons.grid(row=row, column=0, columnspan=2, sticky="ew", pady=(14, 0))
        for column in range(9):
            buttons.columnconfigure(column, weight=1)

        ttk.Button(buttons, text="Add place", command=self.add_place).grid(
            row=0, column=0, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Remove place", command=self.remove_place).grid(
            row=0, column=1, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Import index", command=self.import_index).grid(
            row=0, column=2, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Choose picture", command=self.choose_picture).grid(
            row=0, column=3, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Open image", command=self.open_image).grid(
            row=0, column=4, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Open map", command=self.open_map).grid(
            row=0, column=5, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Save place", command=self.save_current).grid(
            row=0, column=6, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Save all", command=self.save_all).grid(
            row=0, column=7, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Regenerate Dart", command=self.regenerate).grid(
            row=0, column=8, sticky="ew", padx=3
        )

        self.refresh_list()
        self.select_index(0)

    def refresh_list(self) -> None:
        self.place_list.delete(0, tk.END)
        for place in self.places:
            self.place_list.insert(tk.END, f"{place['name']}  -  {place['category']}")

    def select_index(self, index: int) -> None:
        if not self.places:
            return
        index = max(0, min(index, len(self.places) - 1))
        self.selected_index = index
        self.place_list.selection_clear(0, tk.END)
        self.place_list.selection_set(index)
        self.place_list.activate(index)
        place = self.places[index]
        hours = place["openingHours"]
        values = {
            "id": place.get("id", ""),
            "name": place.get("name", ""),
            "category": place.get("category", CATEGORIES[0]),
            "latitude": place.get("latitude", ""),
            "longitude": place.get("longitude", ""),
            "address": place.get("address", ""),
            "imageUrl": place.get("imageUrl", ""),
            "phone": place.get("phone", ""),
            "weekdayOpen": hours.get("weekdayOpen", ""),
            "weekdayClose": hours.get("weekdayClose", ""),
            "saturdayOpen": hours.get("saturdayOpen", ""),
            "saturdayClose": hours.get("saturdayClose", ""),
            "sundayOpen": hours.get("sundayOpen", ""),
            "sundayClose": hours.get("sundayClose", ""),
        }
        for field, value in values.items():
            self.vars[field].set("" if value is None else str(value))

    def on_select(self, _event: tk.Event) -> None:
        selection = self.place_list.curselection()
        if selection:
            self.select_index(selection[0])

    def place_from_form(self) -> Dict[str, Any]:
        place_id = self.vars["id"].get().strip()
        name = self.vars["name"].get().strip()
        category = self.vars["category"].get().strip()
        if not place_id:
            raise ValueError("id is required")
        if not name:
            raise ValueError("name is required")
        if category not in CATEGORIES:
            raise ValueError(f"category must be one of: {', '.join(CATEGORIES)}")

        weekday_open = parse_hour(self.vars["weekdayOpen"].get())
        weekday_close = parse_hour(self.vars["weekdayClose"].get())
        return {
            "id": place_id,
            "name": name,
            "category": category,
            "latitude": float(self.vars["latitude"].get()),
            "longitude": float(self.vars["longitude"].get()),
            "address": self.vars["address"].get().strip(),
            "imageUrl": self.vars["imageUrl"].get().strip(),
            "phone": self.vars["phone"].get().strip(),
            "openingHours": {
                "weekdayOpen": 0 if weekday_open is None else weekday_open,
                "weekdayClose": 0 if weekday_close is None else weekday_close,
                "saturdayOpen": parse_hour(self.vars["saturdayOpen"].get()),
                "saturdayClose": parse_hour(self.vars["saturdayClose"].get()),
                "sundayOpen": parse_hour(self.vars["sundayOpen"].get()),
                "sundayClose": parse_hour(self.vars["sundayClose"].get()),
            },
        }

    def save_current(self) -> None:
        try:
            self.places[self.selected_index] = self.place_from_form()
        except Exception as error:
            messagebox.showerror("Could not save place", str(error))
            return
        self.refresh_list()
        self.select_index(self.selected_index)

    def next_custom_id(self) -> str:
        existing_ids = {str(place.get("id")) for place in self.places}
        index = 1
        while True:
            place_id = f"new-place-{index}"
            if place_id not in existing_ids:
                return place_id
            index += 1

    def add_place(self) -> None:
        if self.places:
            try:
                self.places[self.selected_index] = self.place_from_form()
            except Exception as error:
                messagebox.showerror("Could not save current place", str(error))
                return

        self.places.append(
            {
                "id": self.next_custom_id(),
                "name": "New place",
                "category": "publicService",
                "latitude": 64.17734,
                "longitude": -51.68750,
                "address": "",
                "imageUrl": "",
                "phone": "",
                "openingHours": dict(DEFAULT_OPENING_HOURS),
            }
        )
        self.refresh_list()
        self.select_index(len(self.places) - 1)

    def remove_place(self) -> None:
        if not self.places:
            return
        place = self.places[self.selected_index]
        if not messagebox.askyesno("Remove place", f"Remove {place.get('name', 'this place')}?"):
            return
        del self.places[self.selected_index]
        self.refresh_list()
        if self.places:
            self.select_index(self.selected_index)
        else:
            for var in self.vars.values():
                var.set("")

    def import_index(self) -> None:
        if self.places:
            try:
                self.places[self.selected_index] = self.place_from_form()
            except Exception as error:
                messagebox.showerror("Could not save current place", str(error))
                return
        added = import_index_places(self.places)
        save_places(self.places)
        generate_dart(self.places)
        self.refresh_list()
        self.select_index(self.selected_index)
        messagebox.showinfo("Import complete", f"Added {added} places from the offline index.")

    def save_all(self) -> None:
        self.save_current()
        save_places(self.places)
        generate_dart(self.places)
        messagebox.showinfo("Saved", "Saved JSON and regenerated Dart places.")

    def regenerate(self) -> None:
        self.save_current()
        generate_dart(self.places)
        messagebox.showinfo("Generated", f"Updated {DART_PATH.relative_to(ROOT)}")

    def open_image(self) -> None:
        image_path = self.vars["imageUrl"].get().strip()
        if not image_path:
            return

        if image_path.startswith("assets/"):
            local_path = ROOT / image_path
            if not local_path.exists():
                messagebox.showerror("Missing image", str(local_path))
                return
            webbrowser.open(local_path.resolve().as_uri())
            return

        webbrowser.open(image_path)

    def choose_picture(self) -> None:
        place_id = self.vars["id"].get().strip()
        if not place_id:
            messagebox.showerror("Missing id", "Set the place id before choosing a picture.")
            return

        source = filedialog.askopenfilename(
            title="Choose place picture",
            filetypes=[
                ("Image files", "*.png *.jpg *.jpeg *.webp"),
                ("PNG files", "*.png"),
                ("JPEG files", "*.jpg *.jpeg"),
                ("WebP files", "*.webp"),
                ("All files", "*.*"),
            ],
        )
        if not source:
            return

        source_path = pathlib.Path(source)
        suffix = source_path.suffix.lower() or ".png"
        destination = PLACE_PICTURES_DIR / f"{place_id}{suffix}"
        PLACE_PICTURES_DIR.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination)

        asset_path = destination.relative_to(ROOT).as_posix()
        self.vars["imageUrl"].set(asset_path)
        self.save_current()
        messagebox.showinfo("Picture copied", f"Updated imageUrl to {asset_path}")

    def open_map(self) -> None:
        latitude = self.vars["latitude"].get().strip()
        longitude = self.vars["longitude"].get().strip()
        if latitude and longitude:
            webbrowser.open(f"https://www.openstreetmap.org/?mlat={latitude}&mlon={longitude}#map=18/{latitude}/{longitude}")


if __name__ == "__main__":
    if "--import-index" in sys.argv:
        current_places = load_places()
        imported_count = import_index_places(current_places)
        save_places(current_places)
        generate_dart(current_places)
        print(f"Imported {imported_count} places from {SEARCH_INDEX_PATH.relative_to(ROOT)}")
        sys.exit(0)

    try:
        PlaceEditor().mainloop()
    except FileNotFoundError as error:
        messagebox.showerror("Missing file", str(error))
    except tk.TclError as error:
        print(f"Could not open the place editor window: {error}")
