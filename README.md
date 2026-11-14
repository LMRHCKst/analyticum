# ANALITICUM

Консольный рогалик на PascalABC.NET 4.1: BSP-подземелья 40×25, FOV, бой,
DSL конфигов, своя логистическая регрессия и k-means. Один процесс, без
сети, без ML-библиотек.

## Запуск

```bat
build.cmd
run.cmd
```

`run.cmd` собирает сам, если `out\analiticum.exe` ещё нет.

```bat
run.cmd --demo 200
run.cmd --bench
run.cmd --test
run.cmd --replay out\demo_save.json
```

Компилятор PascalABC.NET 4.1 в репозиторий не кладу: это 40 МБ DLL.
Скачай `PascalABCNET-Console-net10.zip` с pascalabc.net и распакуй в
`tools\pabcnet\PascalABCNET-Console-net10`. Нужен .NET 10 Runtime.

## Коротко о внутренностях

- `src\lib_core.pas` — `Result<T,E>`, `Option<T>`, splitmix64, операторы.
- `src\lib_lowlevel.pas` — арена на unmanaged-памяти, плотная матрица,
  свой heap + A*, trie, QPC, бенчмарк.
- `src\lib_script.pas` + `lib_script_impl.inc` — DSL: лексер → парсер →
  AST → Visitor, печать AST, лямбды, карринг, JSON.
- `src\lib_ai.pas` — softmax-регрессия, мини-батчи, k-means.
- `src\lib_game.pas` — карта, FOV, враги, босс, save/replay.
- `src\lib_analytics.pas` — статистика, спарклайн, CSV/JSON.
- `src\analiticum.pas` — UI, demo, bench, replay, команды.
- `scripts\*.cfg` — монстры и предметы без перекомпиляции.

## Мои мысли

PascalABC.NET 4.1 — это .NET-франкенштейн. Снаружи старый синтаксис,
внутри CLR, лямбды, `Seq` и garbage collector. Для такого проекта — норм.
Для прода — я бы трижды подумала.

Больше всего бесило не отсутствие `GetMem`, а тихое `X := x` в
конструкторе: компилятор делает `X := X`, и все враги стоят в `(0,0)`.
Потом сидишь и смотришь, как восемь монстров наложились на один тайл.
Теперь пишу `Self.X := x` даже там, где имена вроде разные.

Ещё привет `Match`, которое зарезервировали — поэтому `MatchWith`;
конструкторам, которые обязаны называться только `Create`;
extension-методам, которые нельзя объявлять в interface юнита;
двумерному массиву как полю класса, который даёт `BadImageFormatException`;
и generic-статике, которая не парсится в выражении.

Что понравилось: лямбды и LINQ-пайплайны, срезы, кортежи, интерполяция,
быстрый компилятор, `class function operator+`, `extensionmethod`.
И свой softmax с k-means — когда модель выдаёт 1.000, а не вызывает
чужой `fit()`, это кайф.

Вердикт: большой прод на Паскале я бы не писала. Но этот проект было
интересно тащить именно на нём. Паскаль не мёртв, он просто странный.

## Цифры

- `--test`: 50 passed, 0 failed.
- 1 млн аллокаций: арена 21.88 млн/с против `new/List` 13.14 млн/с.
- softmax 2000×40: accuracy 1.000, 188 мс.
- Пик памяти: demo 32.3 МБ, bench 69.9 МБ.
- Demo 200 ходов: 4-й уровень, босс убит, реплей сходится.

Подробный отчёт: `docs\report.md`.
Личный, с матами: `docs\personal-report.md`.
