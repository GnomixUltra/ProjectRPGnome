# RPG Base — заготовка 3D RPG на Godot 4.x

База для 3D-игры от первого лица. Открывается в **Godot 4.7** (и любом 4.x).

## Быстрый старт
1. Откройте Godot → **Import** → выберите `game/project.godot`.
2. Нажмите **Run Project** (F5).

## Готовый .exe (Windows)

**Самый простой способ:** скачайте сборку из GitHub Releases:
https://github.com/GnomixUltra/ProjectRPGnome/releases/tag/latest-exe
(архив `ProjectRPG_windows.zip` → распакуйте → запустите `ProjectRPG.exe`).

CI пересобирает exe автоматически при каждом пуше в `main`
(workflow `.github/workflows/build-exe.yml`, Godot 4.7.2 + export templates).

**Собрать самому в Godot 4.7.2:**
1. Editor → Manage Export Templates → Download (или Install from file) — нужны шаблоны **4.7.2.stable**.
2. Project → Export → пресет **Windows Desktop** (уже в `export_presets.cfg`; PCK встроен в exe).
3. Export Project → `ProjectRPG.exe`.

CLI-сборка (Linux/headless):
```
godot --headless --import
godot --headless --export-release "Windows Desktop" ProjectRPG.exe
```

## Структура
```
game/
├── project.godot        # конфигурация проекта + связи ввода (WASD, Shift, Space)
├── scenes/main.tscn     # стартовая сцена: земля, ящик, игрок, HUD
├── scripts/
│   ├── player.gd        # CharacterBody3D: движение, прыжок, бег, выносливость
│   ├── hud.gd           # полоски HP и выносливости
│   └── main.gd          # логика сцены (спавн игрока)
└── assets/              # текстуры .png: grass, dirt, sky_night
```

## Управление
| Клавиша | Действие |
|---|---|
| **W A S D** | Движение |
| **Мышь** | Обзор (клик по окну — захват мыши) |
| **SHIFT** | Бег (тратит выносливость) |
| **ПРОБЕЛ** | Прыжок |
| **ESC / ENTER** | Отпустить / захватить мышь |

## Выносливость
- Максимум 100, тратится на бег (~22/с), восстанавливается в покое (~14/с).
- На нуле — **истощение**: бег недоступен, пока шкала не восстановится выше 40.
- Все параметры — `@export` в `player.gd`, настраиваются в инспекторе.

## Текстуры
Используются png из репозитория:
- `assets/grass.png` — трава (земля, тайлится через `uv1_scale`);
- `assets/dirt.png` — земля (материал ящика-пример коллайдера);
- `assets/sky_night.png` — ночное небо (панорамный скайбокс в `WorldEnvironment`).

## Физические слои
- Layer 1 «World» — окружение;
- Layer 2 «Player» — игрок (маска: только World).
