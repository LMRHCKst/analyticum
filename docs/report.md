# АНАЛИТИКУМ: отчёт по прототипу

Дата среза: 14.11.2026. Проект: `D:\AI_Tools\ANALITICUM`.
Компилятор: PascalABC.NET 4.1.0.3948 (console, .NET 10).
Машина: Intel Core i3-9100F, 16 ГБ RAM, Windows, .NET 10.0.102.

Запуск: `run.cmd` (собирает при необходимости), тесты — `run.cmd --test`,
demo — `run.cmd --demo 200`, бенчмарки — `run.cmd --bench`.

## 1. Что закрыто

| Блок | Файл | Строка |
|---|---|---|
| `Result<T,E>` | `src\lib_core.pas` | 27 |
| `Option<T>` | `src\lib_core.pas` | 42 |
| Детерминированный splitmix64 | `src\lib_core.pas` | 55, 195 |
| Перегрузка `+` для `TPoint` | `src\lib_core.pas` | 89 |
| `Clamp`/extension-функции | `src\lib_core.pas` | 73 |
| `TDisposable` + виртуальный `Dispose` | `src\lib_lowlevel.pas` | 16 |
| Арена на unmanaged-памяти | `src\lib_lowlevel.pas` | 26 |
| `TArena.Alloc` с выравниванием | `src\lib_lowlevel.pas` | 252 |
| `TArena.Reset` (live pointers = 0) | `src\lib_lowlevel.pas` | 280 |
| Плотная матрица row-major | `src\lib_lowlevel.pas` | 47 |
| Своя бинарная куча | `src\lib_lowlevel.pas` | 78 |
| A* на своей куче | `src\lib_lowlevel.pas` | 527 |
| Trie автодополнения | `src\lib_lowlevel.pas` | 118 |
| QPC-таймер через `external` | `src\lib_lowlevel.pas` | 131 |
| Бенчмарк арена vs `new`/`List` | `src\lib_lowlevel.pas` | 156 |
| Visitor над AST | `src\lib_script.pas` | 52 |
| Лексер DSL | `src\lib_script.pas` | 247 |
| Парсер DSL | `src\lib_script.pas` | 262 |
| Печать AST обратно | `src\lib_script.pas` | 295, 323 |
| Include-разбиение implementation | `src\lib_script.pas` | 1519 |
| Evaluator DSL | `src\lib_script_impl.inc` | 290 |
| Карринг лямбд | `src\lib_script_impl.inc` | 542 |
| Объекты/слияние конфигов | `src\lib_script_impl.inc` | 173 |
| Свой JSON-сериализатор | `src\lib_script_impl.inc` | 1013 |
| Свой JSON-парсер | `src\lib_script_impl.inc` | 1022 |
| `TConfigSet.LoadDirectory` | `src\lib_script_impl.inc` | 757 |
| Softmax-регрессия | `src\lib_ai.pas` | 35 |
| Ручной `TrainBatch` + клиппинг | `src\lib_ai.pas` | 201 |
| Кольцевой буфер наблюдений | `src\lib_ai.pas` | 59 |
| Разбивка буфера по классам | `src\lib_ai.pas` | 340 |
| AI-движок и обучение каждые 20 | `src\lib_ai.pas` | 77, 389 |
| K-means (3 кластера) | `src\lib_ai.pas` | 101, 479 |
| Признаки хода игрока (40) | `src\lib_ai.pas` | 72 |
| BSP-карта 40×25 | `src\lib_game.pas` | 27, 257 |
| FOV | `src\lib_game.pas` | 320 |
| Игровой цикл | `src\lib_game.pas` | 983 |
| AI врагов/предсказание | `src\lib_game.pas` | 892 |
| Босс по k-means | `src\lib_game.pas` | 594 |
| Бой/лут/опыт | `src\lib_game.pas` | 787 |
| Сохранение seed+журнал | `src\lib_game.pas` | 1062 |
| Реплей сохранения | `src\lib_game.pas` | 1088 |
| Статистика сессии | `src\lib_analytics.pas` | 16 |
| Спарклайн | `src\lib_analytics.pas` | 62 |
| `params`-джойн | `src\lib_analytics.pas` | 63 |
| Срез последних accuracy | `src\lib_analytics.pas` | 239 |
| `Aggregate`/сводка | `src\lib_analytics.pas` | 254 |
| CSV-экспорт | `src\lib_analytics.pas` | 275 |
| JSON-экспорт | `src\lib_analytics.pas` | 307 |
| UI карты и сайдбара | `src\analiticum.pas` | 121 |
| Дашборд, `GroupBy`, кортеж | `src\analiticum.pas` | 225 |
| Командная строка + trie | `src\analiticum.pas` | 295 |
| Demo-режим | `src\analiticum.pas` | 495 |
| Bench-режим | `src\analiticum.pas` | 550 |
| Интерактив | `src\analiticum.pas` | 601 |
| Extension-метод `Fit` | `src\analiticum.pas` | 17 |
| Мини-фреймворк тестов | `src\tests.pas` | 42 |
| Тесты M1–M5 | `src\tests.pas` | 78, 102, 154, 192, 255, 311 |
| Карринг в конфиге | `scripts\monsters.cfg` | 4 |
| Конкретный монстр | `scripts\monsters.cfg` | 25 |
| Босс | `scripts\monsters.cfg` | 64 |

## 2. Что взято из «потолка»

- **Свой аллокатор арен** поверх Win32-кучи через `Marshal.AllocHGlobal`,
  с выравниванием, счётчиком живых указателей и доказательством «после
  Reset — 0» в тестах. `GetMem` в PascalABC.NET 4.1 нет, это честная
  замена, а не обход.
- **Плотная матрица на указателе**, row-major вручную, с `MatVec` и
  `TransposeMatVec`; на ней же живёт softmax.
- **Свой A\*** на самописной бинарной куче, без `PriorityQueue` .NET.
- **Trie** для автодополнения команд в `:`-режиме.
- **Свой DSL** с лексером, парсером, AST, Visitor, печатью AST и
  round-trip-тестом; лямбды, карринг, слияние объектов, `if`, списки с
  `x N`.
- **Своё обучение**: softmax-регрессия, мини-батчи, кросс-энтропия,
  градиент вручную, L2 и клиппинг. Никаких `Fit()`.
- **K-means** на стилевых окнах; по доминирующему кластеру выбирается
  босс.
- **Детерминированный реплей**: сохранение — seed + журнал действий,
  загрузка заново прогоняет игру и сверяет ход/уровень.
- **Свой JSON** (и парсер, и сериализатор), CSV, ASCII-спарклайн.
- **Свой тест-фреймворк** с ассертами и ненулевым кодом возврата.

Частично/иначе, чем в матрице: «рекурсивные generic’и» не выделялись в
отдельную фичу; extension-методы нельзя объявлять в interface юнита,
поэтому они в main/implementation; сравнение с встроенным ML невозможно
(его нет в PascalABC.NET 4.1) — сравниваю с majority-baseline.

## 3. Бенчмарки

`run.cmd --bench`, последний прогон:

| Операция | млн/с | нс/оп | память |
|---|---:|---:|---:|
| arena/unmanaged, 1 млн | 21.88 | 45.7 | 30.5 МБ |
| new/List, 1 млн | 13.14 | 76.1 | 34.9 МБ |

CSV: `out\bench_arena.csv`.

Softmax на 2000×40, 10 эпох, batch 32:

| Модель | accuracy | время |
|---|---:|---:|
| own softmax | 1.000 | 188.4 мс |
| majority baseline | 0.200 | — |

CSV: `out\bench_ml.csv`.

Пиковый Working Set:

| Режим | Пик |
|---|---:|
| `--demo 200` | 32.3 МБ |
| `--bench` | 69.9 МБ |

Бюджет 150 МБ не пробит. Проект без компилятора — 0.56 МБ. Demo-save —
477 байт, то есть лимит 100 КБ с огромным запасом.

## 4. Тесты

`run.cmd --test`: **50 passed, 0 failed**.

Покрытие:

- M1: RNG-детерминизм, `Result.Map/Bind`, `Option.MatchWith`, оператор
  `+`, манхэттен, `Clamp`.
- M2: 1000 аллокаций арены, выравнивание 16, live=0 после reset,
  матрица row-major, A* цена, trie, QPC.
- M3: AST round-trip, загрузка всех конфигов, карринг `base(30)(5)`,
  loot `coin x3`, boss-флаг, JSON round-trip, `\u`-escape.
- M4 AI: softmax > 0.9, loss < 0.5, батчи движка, k-means 3 группы.
- M4 игра: BSP-комнаты, путь до лестницы, FOV, save/replay (turn,
  level, длина журнала).
- M5: спарклайн, счётчики, частые ходы, CSV/JSON, парсинг JSON.

## 5. Demo и реплей

`run.cmd --demo 200`:

- 200 ходов, 4-й уровень, 5/45 HP;
- босс `boss_architect` убит на 3-м уровне;
- точность модели к концу — около 0.94;
- чекпоинт на входе в 4-й уровень: ход 169, HP 45;
- `LoadFrom` прогнал 169 действий и получил те же turn/level/HP.

На 300 ходах demo обычно погибает — это нормальный рогалик, не
заявка на «неуязвимого бота».

## 6. Ограничения и честные оговорки

- `GetMem`/`FreeMem` в PascalABC.NET 4.1 отсутствуют; арена использует
  `Marshal.AllocHGlobal`. Это unmanaged-память, но не классический
  `GetMem`.
- `Match` — зарезервированное слово, поэтому `MatchWith`.
- `destructor Destroy; override` не переопределяется; используется
  `TDisposable.Dispose`. Для GC-языка это честнее, чем делать вид, что
  деструкторы работают как в FPC.
- Встроенного ML-модуля нет; сравнение с `.Fit()` из ТЗ физически
  невозможно. Baseline — 20 %.
- Многопоточность не использовалась: один поток, как разрешено.
- Apphost x86, а .NET 10 x64; запуск через `dotnet out\analiticum.exe`
  (это делает `run.cmd`).
- Босс выбирается по k-means на стилевых окнах, а не по «профилю
  игрока» из большой модели. Для прототипа этого достаточно, но это
  эвристика.
- Сохранение — не полный снапшот, а seed+журнал; реплей проверен, но
  при смене кода/конфигов старые сейвы могут разойтись.

## 7. Как проверить

```bat
cd D:\AI_Tools\ANALITICUM
build.cmd
run.cmd --test
run.cmd --demo 200
run.cmd --bench
run.cmd --replay out\demo_save.json
```

Ожидаемо: `[build] OK`, `50 passed, 0 failed`, demo с реплеем,
две CSV-таблицы.
