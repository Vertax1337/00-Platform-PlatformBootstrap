# PlatformBootstrap Repository

## Zweck

`00-Platform/PlatformBootstrap` ist die Source of Truth für Aufbau,
Onboarding und strukturelle Weiterentwicklung der BSSE Azure-DevOps-Plattform.

## Repository-Inhalt

```text
PlatformBootstrap
├── bootstrap/
│   ├── BSSE.AzureDevOps.Common.ps1
│   ├── New-BSSEAzureDevOpsCore.ps1
│   ├── New-BSSECustomerProject.ps1
│   ├── Add-BSSECustomerFirewall.ps1
│   └── Test-BSSEAzureDevOpsPrerequisites.ps1
│
├── config/
│   └── organizations.json
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
