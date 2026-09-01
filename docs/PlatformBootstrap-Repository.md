# PlatformBootstrap Repository

## Zweck

`00-Platform/PlatformBootstrap` ist die Source of Truth für Aufbau,
Onboarding und strukturelle Weiterentwicklung der BSSE Azure-DevOps-Plattform.

## Repository-Inhalt

```text
PlatformBootstrap
├── bootstrap/
│   ├── BSSE.AzureDevOps.Common.ps1
│   ├── BSSE.AzureDevOps.RepositoryPolicy.ps1
│   ├── Sync-BSSERepositoryPolicies.ps1
│   ├── New-BSSEAzureDevOpsCore.ps1
│   ├── New-BSSECustomerProject.ps1
│   ├── Add-BSSECustomerFirewall.ps1
│   └── Test-BSSEAzureDevOpsPrerequisites.ps1
│
├── config/
│   ├── organizations.json
│   └── repository-policies.json
│
├── docs/
│   ├── Umsetzungsplan.md
│   ├── Security-Modell.md
│   ├── Kunden-Onboarding.md
│   ├── Namenskonventionen.md
│   └── PlatformBootstrap-Repository.md
│
├── platform/
│   └── pipeline-templates/
│       └── templates/
│           ├── readonly-documentation.yml
│           └── iac-deployment.yml
│
├── tests/
│   └── Test-BSSERepositoryPolicy.ps1
│
├── README.md
├── CHANGELOG.md
└── .gitignore
```

## Hinweis zu `platform/pipeline-templates`

Diese Dateien sind im Bootstrap-Paket Referenz-/Seed-Dateien.
Produktiv sollen die zentralen Pipeline-Templates im separaten Repository
`00-Platform/PipelineTemplates` gepflegt werden.

Dadurch bleibt die Verantwortlichkeit sauber:

```text
PlatformBootstrap
= Plattform erzeugen / strukturieren

PipelineTemplates
= produktive Pipeline-Templates ausführen / versionieren
```

## Repository-Policy-Reconciliation

`config/repository-policies.json` enthält stabile Workload-Schlüssel und den
gewünschten Policyvertrag. Projekt-, Repository-, Pipeline-, Gruppen- und
Policy-IDs sowie Security-Permission-Bits werden immer aus dem aktuellen
Azure-DevOps-Zustand ermittelt.

`bootstrap/Sync-BSSERepositoryPolicies.ps1` ist die öffentliche Schnittstelle.
Ohne `-Apply` ist sie nicht mutierend. Mit `-Apply` erzeugt oder aktualisiert
sie ausschließlich eindeutig aufgelöste Policies und die verwaltete
Break-Glass-ACE; jeder Schreibvorgang wird anschließend zurückgelesen.

Die Komponente ist absichtlich kein Bestandteil eines Workload-Repositories.
Sie wird erst ausgeführt, wenn dessen Validation Pipeline existiert und grün
ist. Unbekannte ACLs, effektiver Bypass normaler Benutzer, eine nicht leere
Break-Glass-Gruppe, mehrdeutige Objekte oder fehlende moderne Permission-
Anzeigenamen führen Fail Closed zu `BLOCKED`.

Ein optionaler `-Rollback` verlangt über `-AppliedStatePath` das unveränderte
Summary des erfolgreichen Apply. Er prüft die aktuelle Bedeutung beider
Actions gegen diesen Nachweis und entfernt nur deren Bits von der verwalteten
Break-Glass-ACE. Policies, Gruppen, fremde ACEs und Legacy-Zuweisungen werden
nicht verändert.
