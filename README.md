# NIGHTREALM

3D RPG от первого лица в духе **Skyrim / Two Worlds / Dark Messiah**.
Ночной открытый мир: холмы, деревья, камни, враги с ИИ ближнего боя, меч.

## Управление
- **WASD** — движение
- **Мышь** — обзор (клик по окну захватывает мышь)
- **SHIFT** — бег (тратит выносливость; на нуле — истощение)
- **ЛКМ** — удар мечом
- **ESC** — меню, **ENTER** — старт, **R** — возродиться после смерти

## HUD
Полоски **HP** (красная) и **выносливости** (жёлтая) внизу экрана, счётчик убийств и FPS.

## Текстуры (в репозитории только они + код)
- `assets/grass.png` — трава
- `assets/dirt.png` — земля
- `assets/sky_night.png` — ночное небо

## Запуск из исходников
```
pip install pygame numpy
python main.py
```

## Сборка .exe
PyInstaller нельзя собрать кросс-платформенно (нужна Windows):
```
pip install pyinstaller
pyinstaller --onefile --windowed --add-data "assets;assets" --name NightRealm main.py
```
Готовый exe — во вкладке **Releases** или в артефактах GitHub Actions (`.github/workflows/build.yml`).
