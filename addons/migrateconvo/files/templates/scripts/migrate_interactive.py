# ==Save: Uniwersalna migracja z fallbackami gdy nie wykryje sciezek==
"""
Interaktywny skrypt do migracji konwersacji Claude Code.
AUTOMATYCZNIE wykrywa wszystkie komputery z nazw folderow - zero konfiguracji!
Jesli nie moze wykryc sciezek, pyta uzytkownika.

Uzycie:
    python migrate_interactive.py
"""

import os
import json
import re
from pathlib import Path
from datetime import datetime
import tkinter as tk
from tkinter import filedialog, messagebox

# Automatyczne wykrycie obecnego komputera
CURRENT_USER = os.environ.get("USERNAME", "")
USERPROFILE = os.environ.get("USERPROFILE", "")
CLAUDE_DIR = Path(USERPROFILE) / ".claude"

# Cache dla odpowiedzi uzytkownika
USER_PROVIDED_PATHS = {
    "workdrive": None,  # Sciezka do WorkDrive jesli nie wykryto
    "folder_mappings": {}  # {old_folder_name: new_folder_name}
}

def extract_username_from_folder(folder_name: str) -> str | None:
    """Wyciaga username/komputer z nazwy folderu projektu.

    C--Users-DELL-Zoho-WorkDrive--... -> DELL
    C--Users-kamil-WorkDrive-Eu-... -> kamil
    D--Projekty-StriX-... -> StriX
    D--Projekty-DELL-KG-... -> DELL
    """
    # Wzorzec 1: C--Users-<username>-
    match = re.match(r"C--Users-([^-]+)-", folder_name)
    if match:
        return match.group(1)

    # Wzorzec 2: D--Projekty-<komputer>- (np. D--Projekty-StriX-KFG)
    match = re.match(r"D--Projekty-([^-]+)-", folder_name)
    if match:
        return match.group(1)

    return None


def ask_user_for_folder(title: str, message: str, mustexist: bool = True) -> str:
    """Pyta uzytkownika o folder przez GUI lub console."""
    # Sprobuj GUI (tkinter)
    try:
        root = tk.Tk()
        root.withdraw()

        if messagebox.askyesno(title, f"{message}\n\nCzy chcesz wskazac folder recznie?"):
            folder = filedialog.askdirectory(title=title)
            root.destroy()
            if folder:
                return folder
        else:
            root.destroy()
            return ""
    except:
        pass

    # Fallback do console
    print(f"\n{title}")
    print(f"{message}")
    response = input("Podaj pelna sciezke do folderu (lub Enter aby pominac): ").strip()

    if response and mustexist:
        if not Path(response).exists():
            print(f"UWAGA: Folder nie istnieje: {response}")
            if input("Uzyc mimo to? (t/n): ").lower() != 't':
                return ""

    return response

def find_current_workdrive() -> str:
    """Znajduje sciezke WorkDrive na obecnym komputerze."""
    # Sprawdz cache
    if USER_PROVIDED_PATHS["workdrive"]:
        return USER_PROVIDED_PATHS["workdrive"]

    # Szukaj roznych wariantow
    possible = [
        Path(USERPROFILE) / "WorkDrive.Eu",
        Path(USERPROFILE),
    ]

    for base in possible:
        if not base.exists():
            continue
        # Szukaj folderu Zoho WorkDrive
        for item in base.iterdir():
            if item.is_dir() and "Zoho WorkDrive" in item.name:
                return str(item)

    # Nie znaleziono - pytaj uzytkownika
    print(f"\nNie znaleziono folderu Zoho WorkDrive dla uzytkownika {CURRENT_USER}")
    print(f"Szukano w: {USERPROFILE}/WorkDrive.Eu/ i {USERPROFILE}/")

    folder = ask_user_for_folder(
        "Zoho WorkDrive nie znaleziony",
        f"Nie moglem automatycznie znalezc folderu Zoho WorkDrive.\n"
        f"Szukano w:\n- {USERPROFILE}\\WorkDrive.Eu\\\n- {USERPROFILE}\\\n\n"
        f"Jesli nie masz Zoho WorkDrive, kliknij Nie.\n"
        f"Migracja bedzie uzywac ogolnego mapowania folderow.",
        mustexist=False
    )

    USER_PROVIDED_PATHS["workdrive"] = folder
    return folder

def scan_foreign_computers() -> dict[str, dict]:
    """Skanuje foldery projektow i wykrywa inne komputery.

    Zwraca dict: {username: {folder_prefix}}
    """
    projects_dir = CLAUDE_DIR / "projects"
    if not projects_dir.exists():
        return {}

    computers = {}

    for folder in projects_dir.iterdir():
        if not folder.is_dir():
            continue

        # Wyciagnij username z nazwy folderu
        username = extract_username_from_folder(folder.name)

        if not username:
            continue

        # Pomin obecnego uzytkownika (case-insensitive)
        if username.lower() == CURRENT_USER.lower():
            continue

        # Zapisz jesli jeszcze nie mamy tego usera
        if username not in computers:
            # Wyciagnij prefix (czesc przed --General-VSCloude-Code)
            # UWAGA: szukamy "--General" (podwojny myslnik) nie "-General"
            if "--General-VSCloude-Code" in folder.name:
                prefix = folder.name.split("--General-VSCloude-Code")[0]
            elif "-General-VSCloude-Code" in folder.name:
                # Fallback dla starszego formatu
                prefix = folder.name.split("-General-VSCloude-Code")[0]
            else:
                prefix = folder.name.rstrip("-")

            computers[username] = {
                "folder_prefix": prefix,
                "example_folder": folder.name,
            }

    return computers

def encode_current_prefix() -> str:
    """Generuje prefix folderu dla obecnego komputera.

    Format nazwy folderu:
    C:\\Users\\kamil\\WorkDrive.Eu\\Zoho WorkDrive (Schody dla Ciebie, Kmylpenter)\\General\\VSCloude Code
    -> C--Users-kamil-WorkDrive-Eu-Zoho-WorkDrive--Schody-dla-Ciebie--Kmylpenter--General-VSCloude-Code

    Reguly:
    - " (" -> "--" (poczatek nawiasu)
    - ", " -> "--" (separator w nawiasie)
    - ")\\" -> "--" (koniec nawiasu przed kolejnym folderem)
    - ")" na koncu -> "" (usun)
    - " " -> "-"
    - "\\" -> "-"
    - ":" -> "-"
    - "." -> "-"
    """
    current_wd = find_current_workdrive()
    if not current_wd:
        return ""

    prefix = current_wd

    # Kolejnosc jest wazna!
    # 1. Zamien " (" na "--" (poczatek nawiasu)
    prefix = prefix.replace(" (", "--")
    # 2. Zamien ", " na "--" (separator w nawiasie)
    prefix = prefix.replace(", ", "--")
    # 3. Zamien ")\\" na "--" (koniec nawiasu + backslash = podwojny myslnik)
    prefix = prefix.replace(")\\", "--")
    # 4. Usun ")" na koncu (jesli zostal)
    prefix = prefix.replace(")", "")
    # 5. Zamien spacje na "-"
    prefix = prefix.replace(" ", "-")
    # 6. Zamien "\" na "-"
    prefix = prefix.replace("\\", "-")
    # 7. Zamien ":" na "-"
    prefix = prefix.replace(":", "-")
    # 8. Zamien "." na "-" (dla WorkDrive.Eu)
    prefix = prefix.replace(".", "-")

    return prefix

def build_dynamic_mappings() -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Buduje mapowania dynamicznie na podstawie wykrytych komputerow.

    Mapowania sciezek sa generyczne - zamieniaja C:\\Users\\<foreign_user>\\
    na C:\\Users\\<current_user>\\ co wystarcza dla wiekszosci przypadkow.
    """
    current_workdrive = find_current_workdrive()
    if not current_workdrive:
        return [], []

    current_prefix = encode_current_prefix()
    foreign_computers = scan_foreign_computers()

    path_mappings = []
    folder_mappings = []

    for username, data in foreign_computers.items():
        old_prefix = data["folder_prefix"]

        # Mapowania sciezek - generyczne dla calego user folderu
        old_user = f"C:\\Users\\{username}\\"
        new_user = USERPROFILE + "\\"

        # Dodaj oba warianty slash (dla JSON z escaped slashes)
        path_mappings.append((old_user, new_user))
        path_mappings.append((
            old_user.replace("\\", "\\\\"),
            new_user.replace("\\", "\\\\")
        ))

        # Mapowanie nazw folderow projektow
        if old_prefix and current_prefix:
            folder_mappings.append((old_prefix, current_prefix))

    return path_mappings, folder_mappings

# Dynamiczne mapowania (budowane przy imporcie)
PATH_MAPPINGS, FOLDER_NAME_MAPPINGS = build_dynamic_mappings()

def replace_paths_in_text(text: str) -> str:
    result = text
    for old_path, new_path in PATH_MAPPINGS:
        result = result.replace(old_path, new_path)
    return result

def get_new_folder_name(folder_name: str) -> str | None:
    """Zwraca nowa nazwe folderu na podstawie mapowania.

    Jesli nie znajdzie mapowania, pyta uzytkownika lub tworzy ogolne.
    """
    # Sprawdz standardowe mapowania
    for old_prefix, new_prefix in FOLDER_NAME_MAPPINGS:
        if folder_name.startswith(old_prefix):
            return folder_name.replace(old_prefix, new_prefix, 1)

    # Sprawdz cache uzytkownika
    if folder_name in USER_PROVIDED_PATHS["folder_mappings"]:
        return USER_PROVIDED_PATHS["folder_mappings"][folder_name]

    # Nie znaleziono mapowania - sprobuj ogolne (zmien tylko username)
    username = extract_username_from_folder(folder_name)
    if username and username.lower() != CURRENT_USER.lower():
        # Generyczne mapowanie: C--Users-DELL-... -> C--Users-kamil-...
        generic_new_name = folder_name.replace(
            f"C--Users-{username}-",
            f"C--Users-{CURRENT_USER}-",
            1
        )

        print(f"\n Nie znaleziono mapowania dla: {folder_name}")
        print(f" Zaproponowane mapowanie: {generic_new_name}")

        # Pytaj uzytkownika (tylko w trybie interaktywnym)
        try:
            response = input(" Uzyc tego mapowania? (t/n/w - wpisz wlasne): ").strip().lower()

            if response == 't' or response == '':
                USER_PROVIDED_PATHS["folder_mappings"][folder_name] = generic_new_name
                return generic_new_name
            elif response == 'w':
                custom = input(" Podaj nowa nazwe folderu: ").strip()
                if custom:
                    USER_PROVIDED_PATHS["folder_mappings"][folder_name] = custom
                    return custom
        except:
            # Brak interakcji (GUI mode) - uzyj generycznego
            USER_PROVIDED_PATHS["folder_mappings"][folder_name] = generic_new_name
            return generic_new_name

    return None

def get_conversation_info(jsonl_path: Path) -> dict:
    """Pobiera informacje o konwersacji z pliku JSONL.

    Poprawiony parser v2.0:
    - Lepsze wyciaganie first_message z roznych formatow
    - Obsluga pustych plikow (0 bajtow)
    - Wyciaganie daty z pierwszej linii jesli brak pozniej
    """
    info = {
        "path": jsonl_path,
        "title": jsonl_path.stem,
        "messages": 0,
        "last_date": None,
        "first_date": None,  # Nowe: data pierwszej wiadomosci
        "first_message": None,
        "needs_migration": False,
        "is_empty": False,  # Nowe: czy plik pusty
        "file_size": 0  # Nowe: rozmiar pliku
    }

    # Sprawdz rozmiar pliku
    try:
        info["file_size"] = jsonl_path.stat().st_size
        if info["file_size"] == 0:
            info["is_empty"] = True
            return info
    except:
        pass

    try:
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            for line in f:
                if not line.strip():
                    continue
                info["messages"] += 1

                # Sprawdz czy wymaga migracji
                if "DELL" in line:
                    info["needs_migration"] = True

                try:
                    data = json.loads(line)

                    # Pobierz tytul z summary
                    if data.get("type") == "summary" and "summary" in data:
                        info["title"] = data["summary"][:60]

                    # Pobierz pierwszy user message - rozszerzona logika
                    if info["first_message"] is None and data.get("type") == "user":
                        msg = data.get("message", {})
                        content = _extract_text_content(msg)
                        if content:
                            # Filtruj komendy systemowe
                            if not content.startswith(("<command-name>", "<local-command")):
                                info["first_message"] = content[:80]

                    # Pobierz date - zapisz pierwsza i ostatnia
                    if "timestamp" in data:
                        ts = data["timestamp"]
                        date_str = None
                        if isinstance(ts, str):
                            date_str = ts[:10]
                        elif isinstance(ts, (int, float)):
                            date_str = datetime.fromtimestamp(ts/1000).strftime("%Y-%m-%d")

                        if date_str:
                            if info["first_date"] is None:
                                info["first_date"] = date_str
                            info["last_date"] = date_str
                except:
                    pass
    except:
        pass

    # Fallback: uzyj first_message jako title jesli title to UUID
    if info["title"] == jsonl_path.stem and info["first_message"]:
        info["title"] = info["first_message"]

    # Jesli brak last_date, uzyj first_date
    if not info["last_date"] and info["first_date"]:
        info["last_date"] = info["first_date"]

    return info


def _extract_text_content(message) -> str:
    """Wyciaga tekst z message (helper dla get_conversation_info).

    Obsluguje rozne formaty:
    - string bezposredni
    - dict z "content" jako string
    - dict z "content" jako lista [{type: "text", text: "..."}]
    """
    if isinstance(message, str):
        return message.strip()

    if isinstance(message, dict):
        content = message.get("content", "")

        if isinstance(content, str):
            return content.strip()

        if isinstance(content, list):
            texts = []
            for item in content:
                if isinstance(item, str):
                    texts.append(item)
                elif isinstance(item, dict):
                    # Rozne typy blokow
                    if "text" in item:
                        texts.append(item["text"])
                    elif item.get("type") == "text" and "text" in item:
                        texts.append(item["text"])
            return " ".join(texts).strip()

    return ""


def _is_not_conversation(jsonl_path: Path) -> bool:
    """Sprawdza czy plik NIE jest prawdziwa konwersacja.

    Filtruje:
    - summary-only (skompaktowane bez oryginalnych wiadomosci)
    - system-only (tylko wpisy konfiguracyjne)
    - file-history-snapshot (historia edycji plikow)

    Prawdziwa konwersacja musi miec wpisy type=user lub type=assistant.
    """
    try:
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            # Przeskanuj plik szukajac wpisow user/assistant
            has_conversation = False

            for i, line in enumerate(f):
                if i >= 100:  # Limit skanowania
                    break
                try:
                    entry = json.loads(line)
                    entry_type = entry.get('type', '')

                    # Jesli znajdziemy user lub assistant - to prawdziwa konwersacja
                    if entry_type in ('user', 'assistant'):
                        has_conversation = True
                        break
                except:
                    pass

            # Jesli nie znaleziono user/assistant - to nie konwersacja
            return not has_conversation
    except:
        return True  # W razie bledu, filtruj (bezpieczniej)


def find_foreign_conversations(include_current: bool = False) -> list[dict]:
    """Znajduje wszystkie konwersacje z innych komputerow.

    Args:
        include_current: Jesli True, zwraca tez konwersacje z obecnego komputera
    """
    conversations = []
    projects_dir = CLAUDE_DIR / "projects"

    if not projects_dir.exists():
        return conversations

    for folder in projects_dir.iterdir():
        if not folder.is_dir():
            continue

        # Wyciagnij username z nazwy folderu
        username = extract_username_from_folder(folder.name)

        if not username:
            continue

        # Pomin obecnego uzytkownika (chyba ze include_current=True)
        if username.lower() == CURRENT_USER.lower() and not include_current:
            continue

        # Pobierz nazwe projektu
        if "-General-VSCloude-Code" in folder.name:
            # Format: C--Users-kamil-...-General-VSCloude-Code-ProjectName
            project_name = folder.name.split("-General-VSCloude-Code")[-1]
            if project_name.startswith("-"):
                project_name = project_name[1:]
            project_name = project_name.replace("-", " ") if project_name else "Glowny"
        else:
            # Format: D--Projekty-StriX-ProjectName -> ostatni segment
            parts = folder.name.split("-")
            # Znajdz ostatni niepusty segment
            project_name = parts[-1] if parts[-1] else parts[-2] if len(parts) > 1 else folder.name

        # Znajdz konwersacje (filtruj niepotrzebne)
        for jsonl_file in folder.glob("*.jsonl"):
            # Pomin agent files (logi Task tool)
            if jsonl_file.name.startswith("agent-"):
                continue

            # Pomin puste pliki (0 bytes)
            if jsonl_file.stat().st_size == 0:
                continue

            # Pomin pliki ktore nie sa konwersacjami (summary-only, system, file-history)
            if _is_not_conversation(jsonl_file):
                continue

            info = get_conversation_info(jsonl_file)

            # Dodatkowe sprawdzenie - czy ma jakies wiadomosci
            if info.get("messages", 0) == 0:
                continue

            info["project"] = project_name
            info["folder"] = folder
            conversations.append(info)

    # Sortuj po dacie (najnowsze pierwsze)
    conversations.sort(key=lambda x: x["last_date"] or "", reverse=True)
    return conversations

def migrate_conversation(conv: dict) -> bool:
    """Migruje pojedyncza konwersacje.

    NIE kopiuje plikow - tylko zamienia sciezki wewnatrz pliku.
    Plik zostaje w tym samym miejscu.
    """
    jsonl_path = conv["path"]

    try:
        # Przeczytaj plik
        with open(jsonl_path, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        # Zamien sciezki
        new_lines = [replace_paths_in_text(line) for line in lines]

        # Sprawdz czy cos sie zmienilo
        if lines == new_lines:
            print(f"  Brak zmian (sciezki juz poprawne)")
            return True

        # Zapisz backup (jesli jeszcze nie istnieje)
        backup_path = jsonl_path.with_suffix(".jsonl.backup")
        if not backup_path.exists():
            with open(backup_path, 'w', encoding='utf-8') as f:
                f.writelines(lines)

        # Zapisz zmodyfikowany plik W TYM SAMYM MIEJSCU
        with open(jsonl_path, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

        print(f"  Zamieniono sciezki w pliku")
        return True
    except Exception as e:
        print(f"  Blad: {e}")
        return False

def migrate_folder(folder: Path) -> bool:
    """Przemianowuje folder projektu."""
    new_name = get_new_folder_name(folder.name)
    if not new_name:
        return False

    new_folder = folder.parent / new_name
    if new_folder.exists():
        print(f"  Folder docelowy juz istnieje: {new_name}")
        return False

    try:
        folder.rename(new_folder)
        return True
    except Exception as e:
        print(f"  Blad przy zmianie nazwy: {e}")
        return False

def update_history_jsonl(folders_to_update: set[Path]):
    """Aktualizuje history.jsonl dla zmienionych folderow."""
    history_file = CLAUDE_DIR / "history.jsonl"
    if not history_file.exists():
        return

    try:
        with open(history_file, 'r', encoding='utf-8') as f:
            lines = f.readlines()

        new_lines = [replace_paths_in_text(line) for line in lines]

        # Backup
        backup_path = history_file.with_suffix(".jsonl.backup")
        with open(backup_path, 'w', encoding='utf-8') as f:
            f.writelines(lines)

        with open(history_file, 'w', encoding='utf-8') as f:
            f.writelines(new_lines)

        print("  Zaktualizowano history.jsonl")
    except Exception as e:
        print(f"  Blad przy aktualizacji history.jsonl: {e}")

def clear_screen():
    os.system('cls' if os.name == 'nt' else 'clear')

def get_session_id(conv: dict) -> str:
    """Pobiera session ID z nazwy pliku."""
    return conv["path"].stem

def paginate_menu(items: list, page_size: int = 15) -> int | None:
    """Wyswietla menu z paginacja. Zwraca wybrany indeks lub None."""
    page = 0
    total_pages = (len(items) + page_size - 1) // page_size

    while True:
        clear_screen()
        start = page * page_size
        end = min(start + page_size, len(items))

        print(f"Strona {page + 1}/{total_pages} ({len(items)} pozycji)")
        print("-" * 60)

        for i in range(start, end):
            item = items[i]
            print(f"  {i + 1:3}. {item}")

        print("-" * 60)
        print("Opcje: [numer] wybierz | [n]astepna | [p]oprzednia | [q]wyjscie")

        choice = input("\nWybor: ").strip().lower()

        if choice == 'q':
            return None
        elif choice == 'n' and page < total_pages - 1:
            page += 1
        elif choice == 'p' and page > 0:
            page -= 1
        elif choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(items):
                return idx
            print(f"Nieprawidlowy numer. Zakres: 1-{len(items)}")
            input("Enter aby kontynuowac...")


def main():
    clear_screen()
    print("=" * 70)
    print(f"  MIGRACJA KONWERSACJI CLAUDE CODE")
    print(f"  Obecny komputer: {CURRENT_USER}")
    print("=" * 70)
    print("\nSzukam konwersacji z innych komputerow...")

    conversations = find_foreign_conversations()

    if not conversations:
        print("\nNie znaleziono konwersacji do migracji.")
        return

    # === KROK 1: Grupuj po komputerze ===
    by_computer = {}
    for conv in conversations:
        # Wyciagnij username z folderu
        folder_name = conv["folder"].name
        match = re.match(r"C--Users-([^-]+)-", folder_name)
        computer = match.group(1) if match else "Unknown"
        if computer not in by_computer:
            by_computer[computer] = []
        by_computer[computer].append(conv)

    # Wybor komputera (jesli wiecej niz 1)
    computers = list(by_computer.keys())
    if len(computers) > 1:
        print(f"\nZnaleziono {len(computers)} komputerow:\n")
        for i, comp in enumerate(computers, 1):
            count = len(by_computer[comp])
            print(f"  {i}. {comp} ({count} konwersacji)")
        print(f"  0. Wszystkie ({len(conversations)} konwersacji)")

        while True:
            choice = input("\nWybierz komputer [0-{}]: ".format(len(computers))).strip()
            if choice == '0':
                selected_convs = conversations
                break
            elif choice.isdigit() and 1 <= int(choice) <= len(computers):
                selected_convs = by_computer[computers[int(choice) - 1]]
                break
            print("Nieprawidlowy wybor.")
    else:
        selected_convs = conversations
        print(f"\nKomputer: {computers[0]} ({len(selected_convs)} konwersacji)")

    # === KROK 2: Grupuj po projekcie ===
    by_project = {}
    for conv in selected_convs:
        proj = conv["project"]
        if proj not in by_project:
            by_project[proj] = []
        by_project[proj].append(conv)

    # Wybor projektu
    projects = sorted(by_project.keys(), key=lambda p: -len(by_project[p]))
    print(f"\n{len(projects)} projektow:\n")
    for i, proj in enumerate(projects, 1):
        count = len(by_project[proj])
        print(f"  {i}. {proj} ({count})")
    print(f"  0. Wszystkie projekty ({len(selected_convs)} konwersacji)")

    while True:
        choice = input("\nWybierz projekt [0-{}]: ".format(len(projects))).strip()
        if choice == '0':
            project_convs = selected_convs
            break
        elif choice.isdigit() and 1 <= int(choice) <= len(projects):
            project_convs = by_project[projects[int(choice) - 1]]
            break
        print("Nieprawidlowy wybor.")

    # === KROK 3: Wybor konwersacji ===
    # Sortuj po dacie (najnowsze pierwsze)
    project_convs.sort(key=lambda x: x["last_date"] or "", reverse=True)

    # Przygotuj liste do wyswietlenia
    conv_labels = []
    for conv in project_convs:
        date = conv["last_date"] or "????"
        title = conv["title"][:40]
        mark = "*" if conv["needs_migration"] else " "
        conv_labels.append(f"{mark}[{date}] {title}")

    print(f"\n{len(project_convs)} konwersacji (* = wymaga migracji sciezek):")
    print("  0. Migruj WSZYSTKIE z tego projektu")
    print("  lub wybierz pojedyncza:\n")

    # Pokaz z paginacja
    selected_idx = paginate_menu(conv_labels)

    if selected_idx is None:
        # User wpisal 0 lub q w menu - sprawdz co
        choice = input("\nMigruj wszystkie? (tak/nie): ").strip().lower()
        if choice == 'tak':
            to_migrate = project_convs
        else:
            print("Anulowano.")
            return
    else:
        to_migrate = [project_convs[selected_idx]]

    # === KROK 4: Migracja ===
    print(f"\n{'=' * 60}")
    print(f"MIGRACJA: {len(to_migrate)} konwersacji")
    print("=" * 60)

    migrated_folders = set()
    success = 0

    for conv in to_migrate:
        title = conv["title"][:45]
        print(f"\n> {title}...")

        if migrate_conversation(conv):
            print("  OK")
            success += 1
            migrated_folders.add(conv["folder"])
        else:
            print("  BLAD")

    # Aktualizuj history.jsonl
    if migrated_folders:
        print("\nAktualizacja history.jsonl...")
        update_history_jsonl(migrated_folders)

    # Przemianuj foldery
    renamed = 0
    for folder in migrated_folders:
        if migrate_folder(folder):
            renamed += 1

    print(f"\n{'=' * 60}")
    print(f"GOTOWE: {success} zmigrowanych, {renamed} folderow przemianowanych")
    print("Kopie zapasowe: *.jsonl.backup")
    print("=" * 60)

    # Pokaz session_id
    if len(to_migrate) == 1:
        conv = to_migrate[0]
        session_id = get_session_id(conv)
        print(f"\nAby wznowic: claude --resume {session_id}")
    elif len(to_migrate) <= 5:
        print("\nSession IDs:")
        for conv in to_migrate:
            sid = get_session_id(conv)
            print(f"  {sid} - {conv['title'][:35]}")

if __name__ == "__main__":
    main()
