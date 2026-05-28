# CIODIY Driver Center — Frozen Architecture (v2.0)

This document defines the **final structure**. Do not reorganize layers or add parallel entry points.
Future work only **fills capabilities** inside existing boundaries.

## Version Roadmap (engineering, not feature sprawl)

| Version | Scope |
|---------|--------|
| **v1.7.0** | Architecture freeze: GUI → AppController → DriverEngine → lib |
| **v1.8.0** | Dashboard + DriverCenter UI shell |
| **v1.9.0** | RepositoryCenter + RollbackCenter |
| **v2.0.0** | DeployCenter + CompatibilityDB scoring integration |

## Layer Diagram

```
┌────────────────────────────────────┐
│             GUI Layer              │
│  MainWindow.xaml                   │
│  Dashboard | DriverCenter          │
│  QuickFix  | DeployCenter          │
│  BackupCenter (settings opts)      │
│  RepoCenter | RollbackCenter       │
│  Logs | Settings                   │
└────────────┬───────────────────────┘
             │
┌────────────▼───────────────────────┐
│          AppController             │
│  Session state / scan scheduling   │
│  lib/AppController.ps1             │
└────────────┬───────────────────────┘
             │
┌────────────▼───────────────────────┐
│        DriverEngine API            │
│  engine/DriverEngine.ps1           │
│  Scan | Match | Fix | Rollback     │
│  Health | Deploy | Repository      │
└────────────┬───────────────────────┘
             │
┌────────────▼───────────────────────┐
│             lib Layer              │
│  Scanner | Matcher | Installer     │
│  Repo | Backup | Health | Analytics│
└────────────────────────────────────┘
```

## GUI Module Map

| File | Role |
|------|------|
| `DriverBooster.ps1` | Entry, CLI, load XAML, ShowDialog |
| `lib/GuiState.ps1` | Context, control registry |
| `lib/GuiNavigation.ps1` | Page switching (8 pages) |
| `lib/GuiPages.ps1` | Per-page render helpers |
| `lib/GuiRender.ps1` | Shared panel updates |
| `lib/GuiEvents.ps1` | Events → Engine API only |
| `lib/GuiWorkers.ps1` | BackgroundWorker, busy state |
| `lib/AppController.ps1` | Session state shared by CLI/GUI |

**Rule:** GUI never calls lib internals directly except through `DriverEngine` facade or AppController scan helpers.

## DriverEngine Public API (frozen surface)

- `Invoke-DriverAppScanEngine`
- `Invoke-DriverFixEngine` / `Invoke-DriverFixEngineWrapped`
- `Invoke-DriverRollbackEngine`
- `Invoke-DriverHealthEngine`
- `Invoke-DeployModeEngine`
- `Get-DriverRepositoryHealthEngine` / `Invoke-DriverRepositoryRepairEngine`
- `Invoke-DriverSyncEngine` / `Invoke-DriverInstallEngine`
- `Get-DriverLatestTransactionEngine` / `Get-DriverTransactionsEngine`
- `Get-DriverTransactionSummaryEngine`

## Scoring Algorithm (frozen weights)

Defined in `lib/DriverScorer.ps1` — **do not change weights without updating this doc and tests**.

| Factor | Max points |
|--------|------------|
| HWID exact match | 50 |
| Device class match | 20 |
| OS version compatible | 10 |
| WHQL | 5 |
| Machine verify success rate | 10 |
| Install success rate | 5 |
| **Total** | **100** |

Recommendation tiers (`lib/RecommendTier.ps1`):

| Score | Tier |
|-------|------|
| 95+ | Strongly recommended |
| 80+ | Recommended |
| 60+ | Optional |
| <60 | Not recommended |

## Compatibility Database

Path: `%LOCALAPPDATA%\CIODIY_DriverBooster\Cache\compatibility_db.jsonl`

Each install appends a record. `Get-PackageCompatibilityHint` feeds machine-verify score.
This asset grows with real installs — more valuable than bulk unverified packages.

## Data Paths

| Purpose | Location |
|---------|----------|
| Install (read-only OK) | `C:\Program Files\CIODIY_DriverBooster` |
| Logs, cache, transactions | `%LOCALAPPDATA%\CIODIY_DriverBooster` |

## Explicitly Out of Scope

- Game boost / game components
- Junk / registry cleanup
- Skin store / accounts
- Background auto-update daemon
- Forced auto-fix without user consent

## CLI Deploy Mode (frozen)

```powershell
.\DriverBooster.ps1 -DeployMode -AutoFix -RebootIfNeeded
```
