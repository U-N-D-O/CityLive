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
import tkinter as tk
import webbrowser
from tkinter import messagebox, ttk
from typing import Any, Dict, List, Optional

ROOT = pathlib.Path(__file__).resolve().parents[2]
CATALOG_PATH = ROOT / "assets" / "data" / "curated_places.json"
DART_PATH = ROOT / "lib" / "src" / "data" / "nuuk_places.dart"

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


class PlaceEditor(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("Nuuk City Live Places")
        self.geometry("1040x650")
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
        for column in range(5):
            buttons.columnconfigure(column, weight=1)

        ttk.Button(buttons, text="Open image", command=self.open_image).grid(
            row=0, column=0, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Open map", command=self.open_map).grid(
            row=0, column=1, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Save place", command=self.save_current).grid(
            row=0, column=2, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Save all", command=self.save_all).grid(
            row=0, column=3, sticky="ew", padx=3
        )
        ttk.Button(buttons, text="Regenerate Dart", command=self.regenerate).grid(
            row=0, column=4, sticky="ew", padx=3
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
        return {
            "id": self.vars["id"].get().strip(),
            "name": self.vars["name"].get().strip(),
            "category": self.vars["category"].get().strip(),
            "latitude": float(self.vars["latitude"].get()),
            "longitude": float(self.vars["longitude"].get()),
            "address": self.vars["address"].get().strip(),
            "imageUrl": self.vars["imageUrl"].get().strip(),
            "phone": self.vars["phone"].get().strip(),
            "openingHours": {
                "weekdayOpen": parse_hour(self.vars["weekdayOpen"].get()),
                "weekdayClose": parse_hour(self.vars["weekdayClose"].get()),
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
        url = self.vars["imageUrl"].get().strip()
        if url:
            webbrowser.open(url)

    def open_map(self) -> None:
        latitude = self.vars["latitude"].get().strip()
        longitude = self.vars["longitude"].get().strip()
        if latitude and longitude:
            webbrowser.open(f"https://www.openstreetmap.org/?mlat={latitude}&mlon={longitude}#map=18/{latitude}/{longitude}")


if __name__ == "__main__":
    try:
        PlaceEditor().mainloop()
    except FileNotFoundError as error:
        messagebox.showerror("Missing file", str(error))
    except tk.TclError as error:
        print(f"Could not open the place editor window: {error}")
