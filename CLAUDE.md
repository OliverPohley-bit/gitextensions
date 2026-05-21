# CLAUDE.md — Git Extensions Codebase Guide

## Project Overview

Git Extensions is a standalone Windows UI tool for managing Git repositories, with optional integration into Windows Explorer and Visual Studio (2015–2022). It targets Windows 7 SP1+ with .NET 9.0.

- **Runtime**: .NET 9.0 (`net9.0-windows`)
- **UI framework**: Windows Forms (WinForms, not WPF)
- **Language**: C# 13 (preview features enabled via `LangVersion=preview`)
- **IDE**: Visual Studio 2022 (v17.12+), or any editor with MSBuild support
- **CI**: AppVeyor (Windows only)
- **Plugin system**: MEF (Managed Extensibility Framework)

---

## Repository Layout

```
/
├── src/
│   ├── app/            # Core application projects
│   ├── plugins/        # Plugin projects (MEF-loaded at runtime)
│   └── native/         # VC++ projects (SSH askpass, Shell extension)
├── tests/
│   ├── app/
│   │   ├── UnitTests/          # Unit test projects per src/app project
│   │   └── IntegrationTests/   # UI and BugReporter integration tests
│   ├── plugins/UnitTests/      # Plugin unit tests
│   └── CommonTestUtils/        # Shared test helpers
├── setup/              # WiX installer project
├── eng/                # Build scripts, MSBuild props, analyzers config
├── externals/          # Git submodules (Git.hub, ConEmu, TextEditor, SpellChecker)
├── artifacts/          # Build outputs (generated, not committed)
├── global.json         # Pins .NET SDK to 9.0 (rollForward: feature)
├── Directory.Build.props     # Global MSBuild configuration
├── Directory.Packages.props  # Central NuGet package version management
└── GitExtensions.sln   # Visual Studio solution (44 projects)
```

### Core App Projects (`src/app/`)

| Project | Purpose |
|---|---|
| `GitExtensions` | WinForms entry point (`Program.cs`) |
| `GitUI` | All UI dialogs, forms, and controls |
| `GitCommands` | Git command execution and repository model |
| `GitExtUtils` | Shared utilities (no UI dependencies) |
| `ResourceManager` | Localization and translation resource loading |
| `BugReporter` | Crash/error reporting dialog |
| `GitExtensions.Extensibility` | Public plugin API and interfaces |
| `GitExtensions.Analyzers.CSharp` | Custom Roslyn analyzers for code style |

### Plugin Projects (`src/plugins/`)

Each plugin is a separate assembly placed in `artifacts/bin/GitExtensions/net9.0-windows/Plugins/` and discovered via MEF at startup.

---

## Build System

### Prerequisites

- .NET 9.0 SDK (`global.json` pins the version)
- Visual Studio 2022 v17.12+ (for native VC++ projects)
- VC++ with ATL (x86/x64) for the installer

### Building

```powershell
# Initialize submodules (required on first clone)
git submodule update --init --recursive

# Build all .NET projects (Debug)
dotnet build

# Build in Release
dotnet build -c Release

# Build native VC++ projects separately
dotnet build ./src/native/build.proj -c Release

# CI build (sets version, enables determinism)
dotnet build -c Release /p:ContinuousIntegrationBuild=true
```

Build outputs go to `artifacts/<Configuration>/bin/<ProjectName>/`.

### Key MSBuild Files

- **`Directory.Build.props`**: Applied to every project. Sets `net9.0-windows`, enables nullable reference types, `TreatWarningsAsErrors=true`, `ImplicitUsings=enable`, and links `CommonAssemblyInfo.cs`.
- **`Directory.Build.targets`**: Post-build steps (e.g. copying plugin DLLs to the Plugins output folder).
- **`eng/RepoLayout.props`**: Defines all artifact path variables (`ArtifactsDir`, `ArtifactsBinDir`, etc.).
- **`eng/Tests.props`**: Classifies test projects by suffix (`.Tests` = unit, `.IntegrationTests` = integration).
- **`Directory.Packages.props`**: Central Package Management — all NuGet versions are defined here; individual `.csproj` files must not specify version numbers.

---

## Running Tests

```powershell
# Run all unit tests
dotnet test

# Run a specific test project
dotnet test tests/app/UnitTests/GitCommands.Tests/

# Run with code coverage
dotnet test /p:Coverage=true
```

Test projects are identified by project name suffix:
- `*.Tests` → unit tests
- `*.IntegrationTests` → integration tests

Key testing libraries:
- **NUnit 4.3.2** — test framework
- **FluentAssertions 8.2.0** — assertions
- **NSubstitute 5.3.0** — mocking
- **Verify.NUnit 28.16.0** — snapshot testing
- **CommonTestUtils** (in `tests/`) — shared Git repo setup helpers

---

## Code Style and Conventions

### Enforced by `.editorconfig` and StyleCop

- **Indentation**: 4 spaces (CRLF line endings)
- **Explicit types**: Avoid `var`; prefer explicit type names
- **Nullable**: Nullable reference types are **enabled** everywhere (`Nullable=enable`)
- **Warnings as errors**: All warnings treated as errors in CI
- **Private fields**: Must use `_camelCase` underscore prefix (e.g. `_repositoryManager`)
- **Tuple member names**: camelCase
- **Hungarian prefixes allowed**: `ui`, `x`, `y`, `my`, `ls`, `am`, `id`, `ie`, `vs`, `up`

### Naming Conventions

- **Namespaces**: `GitExtensions.*` for core; `GitExtensions.Plugins.*` for plugins
- **Interfaces**: Prefix with `I` (e.g. `IGitModule`, `IGitUICommands`)
- **Classes, methods, properties, constants**: PascalCase
- **Private fields**: `_camelCase`
- **Parameters and locals**: camelCase

### Architecture Patterns

- **Separation of concerns**: Business logic in `GitCommands`, UI in `GitUI`. Avoid mixing.
- **Command/Module pattern**: `GitModule` (in `GitCommands`) is the central model for a repository.
- **Plugin API**: Plugins implement interfaces from `GitExtensions.Extensibility` and are MEF-exported via `[Export(typeof(IGitPlugin))]`.
- **Main thread**: WinForms UI must run on the main thread. The `vs-threading` analyzer enforces this — methods listed in `eng/vs-threading.TypesRequiringMainThread.txt` must be called only on the main thread.
- **Async**: Use `Microsoft.VisualStudio.Threading` (`JoinableTaskFactory`) for threading, not raw `Task.Run` in UI code.

---

## Dependencies

### Key NuGet Packages

| Package | Purpose |
|---|---|
| `LibGit2Sharp` (0.31.0) | Core git operations |
| `Microsoft.VisualStudio.Composition` (17.2.41) | MEF plugin system |
| `Microsoft.VisualStudio.Threading` (17.13.61) | UI-safe async/threading |
| `System.Reactive` (5.0.0) | Reactive extensions (Rx.NET) |
| `Newtonsoft.Json` (13.0.3) | JSON serialization |
| `RestSharp` (106.12.0) | HTTP client (used by GitHub/GitLab plugins) |
| `YamlDotNet` (16.3.0) | YAML parsing |

### Git Submodules (`/externals/`)

- **Git.hub** — GitHub API wrapper
- **conemu-inside** — ConEmu terminal embedding
- **ICSharpCode.TextEditor** — Text editor component
- **NetSpell.SpellChecker** — Spell checking in commit messages

These must be initialized before building: `git submodule update --init --recursive`.

---

## Plugin Development

To create a new plugin:

1. Add a new project under `src/plugins/` following the `GitExtensions.Plugins.<Name>` naming convention.
2. Reference `GitExtensions.Extensibility` (not `GitUI` or `GitCommands` directly).
3. Implement `IGitPlugin` (or a more specific interface) and decorate with `[Export(typeof(IGitPlugin))]`.
4. Add the project to `GitExtensions.sln` and the plugins `Directory.Build.targets` so the output DLL is copied to the Plugins folder.

---

## Translations / Localization

- Resource files use `.resx` format.
- Translations are managed via **Transifex** (`eng/transifex.yml`).
- The `ResourceManager` project handles runtime loading of localized resources.
- Do not manually edit `.resx` files for non-English languages; use Transifex.

---

## CI/CD

**AppVeyor** (`appveyor.yml`):
- Image: Visual Studio 2022
- Version scheme: `5.3.0.{build}`
- Skips: branches `configdata`, `gh-pages`, `experimental/*`, `translations_*`
- Steps: install .NET SDK, update submodules, set version, build native, build .NET, run tests, package artifacts
- Parallel MSBuild enabled

**GitHub Actions** (`.github/workflows/`):
- PR/issue labeler automation
- Cache retention policies

---

## Version Management

Version numbers are set by `eng/set_version_to.py`. The `CommonAssemblyInfo.cs` file (at repo root) is linked into every project and provides shared assembly metadata. Do not set version attributes in individual project files.

---

## Important Files to Know

| File | Description |
|---|---|
| `CommonAssemblyInfo.cs` | Shared assembly version/metadata, linked into all projects |
| `eng/GitExtensions.ruleset` | Code analysis ruleset (StyleCop + VS Threading) |
| `eng/stylecop.json` | StyleCop configuration (allowed Hungarian prefixes, tuple naming) |
| `eng/vs-threading.TypesRequiringMainThread.txt` | Types that must be accessed only on the main UI thread |
| `eng/vs-threading.MainThreadAssertingMethods.txt` | Methods that assert main thread context |
| `src/app/GitExtensions.Extensibility/` | Plugin public API — the stable interface boundary |
| `src/app/GitCommands/Git/GitModule.cs` | Central repository model and git command dispatcher |

---

## Common Pitfalls

- **Never add NuGet package versions in `.csproj` files.** All versions are centrally managed in `Directory.Packages.props`.
- **Do not use `var`** — the editorconfig enforces explicit types.
- **Nullable annotations are mandatory.** All new code must be null-safe; the compiler will error on unannotated nullable flows.
- **UI access on background threads** is enforced by the VS Threading analyzer. If you see `VSTHRD` analyzer errors, ensure UI calls are marshalled back to the main thread.
- **Submodules must be initialized** before the first build or the native/external projects will fail.
- **Plugins must not directly reference `GitUI`** — they must only depend on `GitExtensions.Extensibility` to remain decoupled.
