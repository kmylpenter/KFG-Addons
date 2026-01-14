# ==Save: GUI Tkinter do migracji konwersacji Claude Code==
"""
GUI do migracji konwersacji Claude Code miedzy komputerami.
Uruchamia sie w osobnym oknie, wynik zapisuje do JSON.

Uzycie:
    python migrate_gui.py [docelowy_katalog]

Przyklad:
    python migrate_gui.py "D:\\Projekty StriX\\KFG"
"""

import tkinter as tk
from tkinter import ttk, messagebox
import json
import re
from pathlib import Path
import os
from datetime import datetime

# Import funkcji migracji
import sys
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR))

from migrate_interactive import (
    find_foreign_conversations,
    get_session_id,
    CURRENT_USER,
    CLAUDE_DIR,
    extract_username_from_folder
)

RESULT_FILE = CLAUDE_DIR / "migration_result.json"
CONFIG_FILE = CLAUDE_DIR / "migrate_config.json"


def load_projects_root() -> str:
    """Wczytuje zapisany folder glowny projektow."""
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                config = json.load(f)
                return config.get("projects_root", "")
        except:
            pass
    return ""


def save_projects_root(path: str):
    """Zapisuje folder glowny projektow."""
    config = {}
    if CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                config = json.load(f)
        except:
            pass
    config["projects_root"] = path
    with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
        json.dump(config, f, indent=2, ensure_ascii=False)


def path_to_folder_name(path: str) -> str:
    r"""Konwertuje sciezke na nazwe folderu projektu Claude.

    D:\Projekty StriX\KFG -> D--Projekty-StriX-KFG
    """
    result = path
    result = result.replace(" (", "--")
    result = result.replace(", ", "--")
    result = result.replace(")\\", "--")
    result = result.replace(")", "")
    result = result.replace(" ", "-")
    result = result.replace("\\", "-")
    result = result.replace("/", "-")
    result = result.replace(":", "-")
    result = result.replace(".", "-")
    return result


class MigrationGUI:
    def __init__(self, root, target_dir: str = None):
        self.root = root
        self.target_dir = target_dir
        self.target_folder_name = path_to_folder_name(target_dir) if target_dir else None

        title = f"Migracja Claude Code ({CURRENT_USER})"
        if target_dir:
            short_target = Path(target_dir).name
            title = f"Migracja do: {short_target}"

        self.root.title(title)
        self.root.geometry("1000x700")
        self.root.resizable(True, True)

        # Dane
        self.conversations = []
        self.by_computer = {}
        self.by_project = {}
        self.current_computer = None
        self.current_project = None

        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        # Main frame
        main = ttk.Frame(self.root, padding=10)
        main.pack(fill=tk.BOTH, expand=True)

        # === Wiersz 0: Info o docelowym projekcie ===
        if self.target_dir:
            target_frame = ttk.LabelFrame(main, text="Docelowy projekt", padding=5)
            target_frame.pack(fill=tk.X, pady=(0, 10))
            ttk.Label(target_frame, text=f"Katalog: {self.target_dir}",
                      font=("TkDefaultFont", 9, "bold")).pack(anchor=tk.W)
            ttk.Label(target_frame, text=f"Folder: {self.target_folder_name}",
                      foreground="#666666").pack(anchor=tk.W)

        # === Wiersz 1: Komputer i Projekt ===
        top_frame = ttk.Frame(main)
        top_frame.pack(fill=tk.X, pady=(0, 10))

        # Komputer
        comp_frame = ttk.LabelFrame(top_frame, text="Komputer", padding=5)
        comp_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 5))

        self.computer_listbox = tk.Listbox(comp_frame, height=5, exportselection=False)
        self.computer_listbox.pack(fill=tk.BOTH, expand=True)
        self.computer_listbox.bind('<<ListboxSelect>>', self.on_computer_select)

        # Projekt
        proj_frame = ttk.LabelFrame(top_frame, text="Projekt", padding=5)
        proj_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(5, 0))

        self.project_listbox = tk.Listbox(proj_frame, height=5, exportselection=False)
        self.project_listbox.pack(fill=tk.BOTH, expand=True)
        self.project_listbox.bind('<<ListboxSelect>>', self.on_project_select)

        # === Wiersz 2: Konwersacje i Podglad ===
        middle_frame = ttk.Frame(main)
        middle_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        # Lista konwersacji (lewa strona)
        conv_frame = ttk.LabelFrame(middle_frame, text="Konwersacje", padding=5)
        conv_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 5))

        conv_scroll = ttk.Scrollbar(conv_frame)
        conv_scroll.pack(side=tk.RIGHT, fill=tk.Y)

        self.conv_listbox = tk.Listbox(conv_frame, height=15, selectmode=tk.EXTENDED,
                                        yscrollcommand=conv_scroll.set, exportselection=False)
        self.conv_listbox.pack(fill=tk.BOTH, expand=True)
        conv_scroll.config(command=self.conv_listbox.yview)
        self.conv_listbox.bind('<<ListboxSelect>>', self.on_conv_select)

        # Podglad konwersacji (prawa strona)
        preview_frame = ttk.LabelFrame(middle_frame, text="Podglad", padding=5)
        preview_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(5, 0))

        # Przycisk switch poczatek/koniec
        preview_btn_frame = ttk.Frame(preview_frame)
        preview_btn_frame.pack(fill=tk.X, pady=(0, 5))

        self.preview_mode = tk.StringVar(value="start")
        self.preview_btn = ttk.Button(preview_btn_frame, text="Pokaz koniec", command=self.toggle_preview)
        self.preview_btn.pack(side=tk.LEFT)

        self.preview_label = ttk.Label(preview_btn_frame, text="(poczatek)")
        self.preview_label.pack(side=tk.LEFT, padx=(10, 0))

        preview_scroll = ttk.Scrollbar(preview_frame)
        preview_scroll.pack(side=tk.RIGHT, fill=tk.Y)

        self.preview_text = tk.Text(preview_frame, height=20, width=50, wrap=tk.WORD,
                                     yscrollcommand=preview_scroll.set, state=tk.DISABLED)
        self.preview_text.pack(fill=tk.BOTH, expand=True)
        preview_scroll.config(command=self.preview_text.yview)

        # Tagi do kolorowania
        self.preview_text.tag_config("user", foreground="#0066cc", font=("TkDefaultFont", 9, "bold"))
        self.preview_text.tag_config("assistant", foreground="#006600")
        self.preview_text.tag_config("separator", foreground="#999999")

        # Cache aktualnej konwersacji
        self.current_preview_conv = None

        # === Wiersz 3: Przyciski ===
        btn_frame = ttk.Frame(main)
        btn_frame.pack(fill=tk.X)

        self.status_label = ttk.Label(btn_frame, text="Wybierz konwersacje do migracji")
        self.status_label.pack(side=tk.LEFT)

        ttk.Button(btn_frame, text="Anuluj", command=self.cancel).pack(side=tk.RIGHT, padx=(5, 0))
        ttk.Button(btn_frame, text="Migruj wybrane", command=self.migrate).pack(side=tk.RIGHT)
        ttk.Button(btn_frame, text="Zaznacz wszystkie", command=self.select_all).pack(side=tk.RIGHT, padx=(0, 5))
        ttk.Button(btn_frame, text="Reset config", command=self.reset_config).pack(side=tk.RIGHT, padx=(0, 5))

    def load_data(self):
        """Laduje dane o konwersacjach."""
        self.status_label.config(text="Ladowanie...")
        self.root.update()

        # Zaladuj wszystkie konwersacje (wlacznie z obecnym komputerem)
        self.conversations = find_foreign_conversations(include_current=True)

        if not self.conversations:
            messagebox.showinfo("Info", "Nie znaleziono konwersacji.")
            self.save_result(None, "Brak konwersacji")
            self.root.destroy()
            return

        # Grupuj po komputerze
        self.by_computer = {}
        for conv in self.conversations:
            folder_name = conv["folder"].name
            computer = extract_username_from_folder(folder_name) or "Unknown"
            if computer not in self.by_computer:
                self.by_computer[computer] = []
            self.by_computer[computer].append(conv)

        # Wypelnij liste komputerow (obecny na gorze z oznaczeniem)
        sorted_computers = sorted(self.by_computer.keys())
        # Przesun obecny komputer na gore
        if CURRENT_USER in sorted_computers:
            sorted_computers.remove(CURRENT_USER)
            sorted_computers.insert(0, CURRENT_USER)

        for comp in sorted_computers:
            count = len(self.by_computer[comp])
            # Oznacz obecny komputer
            marker = " (obecny)" if comp.lower() == CURRENT_USER.lower() else ""
            self.computer_listbox.insert(tk.END, f"{comp}{marker} ({count})")

        # Auto-wybierz jesli tylko 1 komputer
        if len(self.by_computer) == 1:
            self.computer_listbox.selection_set(0)
            self.on_computer_select(None)

        self.status_label.config(text=f"Znaleziono {len(self.conversations)} konwersacji")

    def on_computer_select(self, event):
        """Obsluga wyboru komputera."""
        sel = self.computer_listbox.curselection()
        if not sel:
            return

        # Pobierz nazwe z listbox i wyciagnij sama nazwe komputera
        listbox_text = self.computer_listbox.get(sel[0])
        # Usun " (obecny)" jesli jest i " (N)" na koncu
        comp_name = listbox_text.split(" (obecny)")[0].rsplit(" (", 1)[0]
        self.current_computer = comp_name

        # Grupuj po projekcie
        self.by_project = {}
        for conv in self.by_computer[comp_name]:
            proj = conv["project"]
            if proj not in self.by_project:
                self.by_project[proj] = []
            self.by_project[proj].append(conv)

        # Wypelnij liste projektow
        self.project_listbox.delete(0, tk.END)
        self.conv_listbox.delete(0, tk.END)

        for proj in sorted(self.by_project.keys(), key=lambda p: -len(self.by_project[p])):
            count = len(self.by_project[proj])
            self.project_listbox.insert(tk.END, f"{proj} ({count})")

    def on_project_select(self, event):
        """Obsluga wyboru projektu."""
        sel = self.project_listbox.curselection()
        if not sel:
            return

        # Pobierz nazwe projektu (bez licznika)
        proj_text = self.project_listbox.get(sel[0])
        proj_name = proj_text.rsplit(" (", 1)[0]
        self.current_project = proj_name

        # Wypelnij liste konwersacji
        self.conv_listbox.delete(0, tk.END)

        convs = self.by_project.get(proj_name, [])
        # Sortuj po dacie
        convs.sort(key=lambda x: x["last_date"] or "", reverse=True)

        for conv in convs:
            date = conv["last_date"] or "brak-daty"
            msgs = conv.get("messages", 0)

            # Lepsze wyswietlanie tytulu
            title = conv["title"]
            # Jesli title to UUID (36 znakow z myslnikami), pokaz first_message lub "(pusty)"
            if len(title) == 36 and title.count("-") == 4:
                if conv.get("first_message"):
                    title = conv["first_message"][:50]
                else:
                    title = f"(pusty - {msgs} msg)"
            else:
                title = title[:50]

            mark = "*" if conv.get("needs_migration") else " "
            self.conv_listbox.insert(tk.END, f"{mark}[{date}] {title}")

    def on_conv_select(self, event):
        """Obsluga wyboru konwersacji - pokaz podglad."""
        sel = self.conv_listbox.curselection()
        if not sel:
            return

        # Pobierz pierwsza zaznaczona konwersacje
        proj_name = self.current_project
        convs = self.by_project.get(proj_name, [])
        convs.sort(key=lambda x: x["last_date"] or "", reverse=True)

        conv = convs[sel[0]]
        self.current_preview_conv = conv
        self.load_preview(conv)

    def toggle_preview(self):
        """Przelacza miedzy poczatkiem a koncem konwersacji."""
        if self.preview_mode.get() == "start":
            self.preview_mode.set("end")
            self.preview_btn.config(text="Pokaz poczatek")
            self.preview_label.config(text="(koniec)")
        else:
            self.preview_mode.set("start")
            self.preview_btn.config(text="Pokaz koniec")
            self.preview_label.config(text="(poczatek)")

        if self.current_preview_conv:
            self.load_preview(self.current_preview_conv)

    def load_preview(self, conv):
        """Laduje podglad konwersacji."""
        self.preview_text.config(state=tk.NORMAL)
        self.preview_text.delete(1.0, tk.END)

        try:
            path = conv["path"]
            messages = []

            with open(path, 'r', encoding='utf-8') as f:
                for line in f:
                    if not line.strip():
                        continue
                    try:
                        data = json.loads(line)
                        msg_type = data.get("type")

                        if msg_type == "user":
                            content = self._extract_text_only(data.get("message", {}))
                            if content:
                                messages.append(("user", content))

                        elif msg_type == "assistant":
                            content = self._extract_text_only(data.get("message", {}))
                            if content:
                                messages.append(("assistant", content))
                    except:
                        pass

            # Pokaz wszystkie wiadomosci (bez limitu)
            display_msgs = messages

            for role, content in display_msgs:
                if role == "user":
                    self.preview_text.insert(tk.END, "USER: ", "user")
                    self.preview_text.insert(tk.END, content + "\n\n")
                else:
                    self.preview_text.insert(tk.END, "CLAUDE: ", "assistant")
                    self.preview_text.insert(tk.END, content + "\n\n")

        except Exception as e:
            self.preview_text.insert(tk.END, f"Blad: {e}")

        self.preview_text.config(state=tk.DISABLED)

        # Przeskocz na poczatek lub koniec
        if self.preview_mode.get() == "end":
            self.preview_text.see(tk.END)
        else:
            self.preview_text.see("1.0")

    def _extract_content(self, message):
        """Wyciaga tekst z message (legacy - pelna wersja)."""
        if isinstance(message, str):
            return message
        if isinstance(message, dict):
            content = message.get("content", "")
            if isinstance(content, str):
                return content
            if isinstance(content, list):
                texts = []
                for item in content:
                    if isinstance(item, dict):
                        if "text" in item:
                            texts.append(item["text"])
                    elif isinstance(item, str):
                        texts.append(item)
                return " ".join(texts) if texts else ""
        return ""

    def _get_cwd_from_conv(self, conv: dict) -> str:
        """Pobiera cwd z konwersacji (szuka w pierwszych 20 liniach)."""
        try:
            with open(conv["path"], 'r', encoding='utf-8') as f:
                for i, line in enumerate(f):
                    if i >= 20:
                        break
                    if not line.strip():
                        continue
                    try:
                        data = json.loads(line)
                        if "cwd" in data:
                            return data["cwd"]
                    except:
                        continue
        except:
            pass
        return None

    def _extract_text_only(self, message):
        """Wyciaga TYLKO prawdziwy tekst - bez tool_use, tool_result, thinking."""
        if isinstance(message, str):
            return message.strip()
        if isinstance(message, dict):
            content = message.get("content", "")
            if isinstance(content, str):
                return content.strip()
            if isinstance(content, list):
                texts = []
                for item in content:
                    if isinstance(item, dict):
                        item_type = item.get("type", "")
                        # Tylko bloki tekstowe - ignoruj tool_use, tool_result, thinking
                        if item_type == "text" and "text" in item:
                            texts.append(item["text"])
                        elif "text" in item and item_type not in ("tool_use", "tool_result", "thinking"):
                            texts.append(item["text"])
                    elif isinstance(item, str):
                        texts.append(item)
                return " ".join(texts).strip() if texts else ""
        return ""

    def select_all(self):
        """Zaznacza wszystkie konwersacje."""
        self.conv_listbox.selection_set(0, tk.END)

    def reset_config(self):
        """Resetuje zapisana sciezke folderu glownego."""
        if CONFIG_FILE.exists():
            CONFIG_FILE.unlink()
            messagebox.showinfo("Reset", "Usunieto zapisana konfiguracje.\nPrzy nastepnej migracji zostaniesz zapytany o folder glowny.")
        else:
            messagebox.showinfo("Reset", "Brak zapisanej konfiguracji.")

    def migrate(self):
        """Wykonuje migracje wybranych konwersacji."""
        sel = self.conv_listbox.curselection()
        if not sel:
            messagebox.showwarning("Uwaga", "Wybierz co najmniej jedna konwersacje.")
            return

        # Pobierz wybrane konwersacje
        proj_name = self.current_project
        convs = self.by_project.get(proj_name, [])
        convs.sort(key=lambda x: x["last_date"] or "", reverse=True)

        to_migrate = [convs[i] for i in sel]

        # Jesli nie ma target_dir, uzyj zapisanego folderu glownego lub zapytaj
        if not self.target_dir:
            old_cwd = self._get_cwd_from_conv(to_migrate[0])
            project_name = Path(old_cwd).name if old_cwd else None

            # Sprawdz zapisany folder glowny
            projects_root = load_projects_root()

            if not projects_root:
                # Pierwszy raz - zapytaj o folder GLOWNY projektow
                from tkinter import filedialog
                messagebox.showinfo(
                    "Konfiguracja",
                    "Wybierz FOLDER GLOWNY projektow na tym komputerze.\n\n"
                    "Np. D:\\Projekty DELL KG\\\n\n"
                    "Ten folder zostanie zapamietany."
                )
                projects_root = filedialog.askdirectory(title="Wybierz folder GLOWNY projektow")
                if not projects_root:
                    return  # Anulowano

                save_projects_root(projects_root)

            # Zloz sciezke docelowa: folder_glowny + nazwa_projektu
            if project_name:
                self.target_dir = str(Path(projects_root) / project_name)
            else:
                # Fallback - zapytaj o pelna sciezke
                from tkinter import filedialog
                self.target_dir = filedialog.askdirectory(title="Wybierz folder docelowy projektu")
                if not self.target_dir:
                    return

        # Potwierdzenie
        if not messagebox.askyesno("Potwierdzenie",
                                   f"Zmigrowac {len(to_migrate)} konwersacji?\n"
                                   f"Docelowa sciezka: {self.target_dir}"):
            return

        # Migracja
        self.status_label.config(text="Migrowanie...")
        self.root.update()

        success = 0
        session_ids = []

        for conv in to_migrate:
            if self.migrate_to_target(conv):
                success += 1
                session_ids.append(get_session_id(conv))

        # Zapisz wynik
        result = {
            "success": success,
            "total": len(to_migrate),
            "target_dir": self.target_dir,
            "session_ids": session_ids,
            "titles": [c["title"][:50] for c in to_migrate]
        }
        self.save_result(result, "OK")

        messagebox.showinfo("Gotowe",
                           f"Zamieniono sciezki w {success}/{len(to_migrate)} konwersacjach.")

        self.root.destroy()

    def migrate_to_target(self, conv: dict) -> bool:
        """Migruje konwersacje - zamienia sciezki wewnatrz pliku.

        NIE kopiuje plikow - edytuje w miejscu.
        Jesli podano target_dir, zamienia stara sciezke na nowa.
        """
        jsonl_path = conv["path"]

        try:
            # Przeczytaj plik
            with open(jsonl_path, 'r', encoding='utf-8') as f:
                content = f.read()

            original_content = content

            # Zamien sciezki (jesli docelowy dir podany)
            if self.target_dir:
                # Znajdz stara sciezke projektu - szukaj w pierwszych liniach
                old_cwd = None
                for line in content.split('\n')[:20]:
                    if not line.strip():
                        continue
                    try:
                        data = json.loads(line)
                        if "cwd" in data:
                            old_cwd = data["cwd"]
                            break
                    except:
                        continue

                if old_cwd and old_cwd != self.target_dir:
                    # Normalizuj sciezki (uzyj backslash jak Windows)
                    target_normalized = self.target_dir.replace("/", "\\")

                    # Zamien sciezke (oba warianty slash)
                    content = content.replace(old_cwd, target_normalized)
                    content = content.replace(
                        old_cwd.replace("\\", "\\\\"),
                        target_normalized.replace("\\", "\\\\")
                    )
            else:
                # Uzyj ogolnych mapowań z migrate_interactive
                from migrate_interactive import replace_paths_in_text
                content = replace_paths_in_text(content)

            # Zapisz backup (jesli jeszcze nie istnieje)
            backup_path = jsonl_path.with_suffix(".jsonl.backup")
            if not backup_path.exists() and content != original_content:
                with open(backup_path, 'w', encoding='utf-8') as f:
                    f.write(original_content)

            # Oblicz docelowy folder na podstawie target_dir
            if self.target_dir:
                target_folder_name = path_to_folder_name(self.target_dir)
                dest_folder = CLAUDE_DIR / "projects" / target_folder_name
                dest_folder.mkdir(parents=True, exist_ok=True)
                dest_path = dest_folder / jsonl_path.name

                # Zapisz zmodyfikowany plik w NOWYM FOLDERZE
                with open(dest_path, 'w', encoding='utf-8') as f:
                    f.write(content)

                # Przenies subfolder z subagentami jesli istnieje
                subagents_folder = jsonl_path.parent / jsonl_path.stem
                if subagents_folder.exists() and subagents_folder.is_dir():
                    import shutil
                    dest_subagents = dest_folder / jsonl_path.stem
                    if dest_subagents.exists():
                        shutil.rmtree(dest_subagents)
                    shutil.move(str(subagents_folder), str(dest_subagents))

                # Usun stary plik (przeniesiony)
                jsonl_path.unlink()

                print(f"  Przeniesiono do: {target_folder_name}")
            else:
                # Bez target_dir - tylko zamien sciezki w miejscu
                with open(jsonl_path, 'w', encoding='utf-8') as f:
                    f.write(content)
                print(f"  Zamieniono sciezki w pliku")

            return True
        except Exception as e:
            print(f"  Blad: {e}")
            return False

    def cancel(self):
        """Anuluje i zamyka okno."""
        self.save_result(None, "Anulowano")
        self.root.destroy()

    def save_result(self, result, status):
        """Zapisuje wynik do pliku JSON."""
        data = {
            "status": status,
            "result": result,
            "timestamp": datetime.now().isoformat()
        }
        with open(RESULT_FILE, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)


def main():
    # Pobierz docelowy katalog z argumentow
    target_dir = None
    if len(sys.argv) > 1:
        target_dir = sys.argv[1]
        # Normalizuj sciezke
        target_dir = str(Path(target_dir).resolve())

    root = tk.Tk()
    app = MigrationGUI(root, target_dir=target_dir)
    root.mainloop()


if __name__ == "__main__":
    main()
