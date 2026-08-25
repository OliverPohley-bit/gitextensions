# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Git Extensions is a standalone Windows Forms UI tool for managing git repositories, with integrations for Windows Explorer and Visual Studio. It targets .NET 9.0, C# 13 (`LangVersion` is `preview` to get the `field` keyword), and is **Windows-only** — it uses `UseWindowsForms`, native VC++ components (shell extension, SSH askpass), and P/Invoke throughout. It cannot be built or run on Linux/macOS.

## Build & test

Requires the .NET 9.0 SDK (`global.json`) and, on Windows, Visual Studio 2022 (17.12+) with the VC++/ATL workload for the native installer/shell components. Full build instructions: https://github.com/gitextensions/gitextensions/wiki/Build-instructions.

```
git submodule update --init --recursive     # externals/ are git submodules
dotnet build .\src\native\build.proj -c Release   # native components (Windows only)
dotnet build -c Release                     # main solution (GitExtensions.sln)
dotnet test -c Release                      # all tests
dotnet test tests/app/UnitTests/GitCommands.Tests -c Release   # a single test project
dotnet test --filter "FullyQualifiedName~MyMethod_should_return_expected"   # a single test
```

CI (`appveyor.yml`) runs `dotnet build` for native then managed code, then `dotnet test`, then a localisation check (`_UpdateEnglishTranslations` target must produce no new pending strings) and `dotnet publish`.

## Architecture

The solution (`GitExtensions.sln`) has ~70 projects under three roots:

- **`src/app/`** — the core application, split into layered assemblies:
  - `GitExtensions.Extensibility` — public interfaces/contracts (`IGitPlugin`, `IGitUICommands`, settings abstractions, build-server integration contracts). No git or UI logic; this is what plugins reference.
  - `GitExtUtils` — low-level, dependency-free helpers (process/stream utilities, argument builders).
  - `GitCommands` — the git domain layer: shells out to the `git` executable, parses output, models revisions/branches/remotes/submodules/config.
  - `ResourceManager` — base classes for translated WinForms controls/forms (`TranslatedControl`, `GitExtensionsFormBase`) and localization plumbing.
  - `GitUI` — the WinForms UI: dialogs (`CommandsDialogs`), the revision grid (`LeftPanel`), themes, editor, autocompletion, etc. Depends on `GitCommands` and `ResourceManager`.
  - `GitExtensions` — the executable entry point (`Program.cs`), composes everything via `ServiceContainerRegistry`.
  - `BugReporter` — crash reporting.
  - `GitExtensions.Analyzers.CSharp` — repo-specific Roslyn analyzers.
- **`src/plugins/`** — optional plugins (GitFlow, GitHub3, Bitbucket, Gource, JiraCommitHintPlugin, build-server integrations, etc.) built against `GitUIPluginInterfaces`/`GitExtensions.Extensibility` and discovered via MEF (`ManagedExtensibility.cs`, `PluginsPathScanner.cs`). New plugin capabilities are exposed as `[Export(typeof(...))]` implementations of interfaces like `IGitPlugin`/`IRepositoryHostPlugin`.
- **`src/native/`** — C++ components: the Windows Explorer shell extension and an SSH askpass helper, built separately via `src/native/build.proj`.

**Service wiring**: each layer exposes a static `ServiceContainerRegistry.RegisterServices(ServiceContainer)` (e.g. `src/app/GitCommands/ServiceContainerRegistry.cs`) that registers its services into a shared `System.ComponentModel.Design.ServiceContainer`; these are called during app startup to build up the composed service graph. Look at these files first to find where a given interface is implemented/registered.

**Tests** (`tests/`) mirror `src/`:
- `tests/app/UnitTests/*.Tests` — one project per `src/app` assembly (NUnit, NSubstitute for mocking, FluentAssertions for assertions).
- `tests/app/IntegrationTests/*.IntegrationTests` — UI and bug-reporter integration tests.
- `tests/CommonTestUtils` — shared test helpers (`ReferenceRepository`, `GitModuleTestHelper`, in-memory settings, MEF test composition).
- `tests/plugins` — plugin tests.

Project "flavor" (unit/integration/performance) is inferred purely from name suffix in `eng/Tests.props` (`.Tests`/`.UnitTests`, `.IntegrationTests`, `.PerformanceTests`) — keep new test project names consistent with this convention.

## Code style (see `.github/copilot-instructions.md` and `.editorconfig` for the full rules)

- Files use CRLF line endings; formatting follows `.editorconfig` (enforced, warnings are errors — `TreatWarningsAsErrors` is set repo-wide).
- File-scoped namespaces; single-line `using`s; newline before opening braces (Allman style).
- Nullable reference types are enabled everywhere — declare non-nullable and check at entry points; use `is null`/`is not null`, not `== null`; don't add redundant null checks where the type system already guarantees non-null.
- Never use `var` for primitive types; use `var` only when the type is obvious from context. Prefer target-typed `new()` over repeating the type.
- Use pattern matching/switch expressions where possible; use `nameof` instead of string literals for member names.
- Tests: NUnit, NSubstitute for mocks, FluentAssertions for assertions; no Arrange/Act/Assert comments; test method names are `MethodUnderTest_should_expected_behavior` (method name stays as-is, suffix is snake_case).

## Contributing conventions (see `CONTRIBUTING.md`)

- PRs should reference an existing (or newly filed) GitHub issue — file/discuss an issue before implementing a non-trivial change.
- Keep PRs focused in scope, with clear commits and accompanying unit tests.
- Contributions are made under the Developer Certificate of Origin (`contributors.txt`).
