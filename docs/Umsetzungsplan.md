# Umsetzungsplan – BSSE Azure DevOps Platform

**Status:** Source-of-Truth  
**Version:** 1.7

## 1. Core

```text
00-Platform
├── PlatformBootstrap
├── PipelineTemplates
├── DocumentationEngine
├── SecurityValidation
└── SharedModules

10-Automation
├── 10-Automation-AzureInfrastructureCollector
└── 10-Automation-OPNsenseDocumentation

20-IaC
├── Vaultwarden
├── AVD-Accelerator
└── Shared-IaC-Modules

99-LAB
```

## 1.1 `00-Platform` Repositories

### `PlatformBootstrap`

Source of Truth für den Aufbau der Azure-DevOps-Plattform.

Enthält:

- Core-Bootstrap,
- Kunden-Onboarding,
- Firewall-Repo-Onboarding,
- gemeinsame Azure-DevOps-CLI-Authentifizierungslogik,
- Organisationsprofile,
- Namenskonventionen,
- Plattform-/Security-Dokumentation,
- zentralen Techniker-Onboarding-Workflow als Azure Pipeline,
- lokales interaktives Onboarding-Frontend,
- kontrollierte `CustomerConfiguration`-Persistenz,
- Pipeline-Registrierungs- und Readiness-Skripte.

### `PipelineTemplates`

Zentrale YAML-Templates für Azure Pipelines.

### `DocumentationEngine`

Gemeinsame Erzeugung von Markdown, DOCX, PDF und weiteren Dokumentationsformaten.

### `SecurityValidation`

Wiederverwendbare Sicherheits-, Read-only-, Sanitization- und Secret-Prüfungen.

### `SharedModules`

Technische Bibliotheken, die von mehreren Automationen/IaC-Komponenten verwendet werden.

### Upgrade-Verhalten

Bei einer bestehenden v1.4.x-Struktur wird `PlatformBootstrap` nur ergänzt.
`PipelineTemplates` wird nicht umbenannt und vorhandener Repository-Inhalt bleibt unverändert.

## 2. Kundenidentität

```text
CUST-<CustomerNumber>-<CustomerSlug>
```

Die interne Kunden-/Debitorennummer ist die führende, stabile technische ID.

## 3. Kundenprojekt

Mindeststruktur:

```text
CUST-<ID>-<Name>
├── CustomerConfiguration
└── Documentation
```

Optional pro OPNsense:

```text
├── Firewall-<Name>-HQ
├── Firewall-<Name>-Branch01
└── ...
```

## 4. OPNsense RAW Backup

### Festlegung

**Eine OPNsense = ein dediziertes RAW-Git-Repository.**

Dieses Repository:

- liegt im Azure-DevOps-Kundenprojekt,
- ist ausschließlich Upstream für `os-git-backup`,
- enthält die RAW `config.xml` und ihre Git-Historie,
- wird vom Bootstrap leer erzeugt,
- erhält vom Bootstrap niemals README, `.gitignore`, YAML oder Initial-Commit.

### Nicht unter `10-Automation`

Es gibt bewusst kein zentrales Kundenbackup-Repo wie:

```text
10-Automation/OPNsenseBackup
```

Das Repository `10-Automation-OPNsenseDocumentation` enthält ausschließlich generischen Programmcode für Sanitization, Validierung und Normalisierung.

### Datenfluss

```text
CUST-xxx/Firewall-*
    ↓ RAW
10-Automation / 10-Automation-OPNsenseDocumentation
    ↓ Sanitize
    ↓ Validate
    ↓ Normalize
00-Platform / DocumentationEngine
    ↓
CUST-xxx / Documentation
```

## 5. Mehrere Firewalls

```text
CUST-4711-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
├── Firewall-Cannon-Deutschland-GmbH-HQ
├── Firewall-Cannon-Deutschland-GmbH-Branch01
└── Firewall-Cannon-Deutschland-GmbH-Branch02
```

## 6. Verbindliche Trennung: Dokumentationsplattform vs. IaC-Produkte

### Dokumentationsplattform

Folgende Fähigkeiten gehören zum Customer-/Dokumentations-Onboarding:

```text
AzureDocumentation
OPNsenseDocumentation
```

Sie verwenden die Read-only-/Sanitization-Kette der Dokumentationsplattform.

### IaC-Produkte

Folgende Komponenten sind **keine Dokumentationsmodule**:

```text
AVD-Accelerator
Vaultwarden
```

Sie sind IaC-Produkte unter `20-IaC` und werden über separate Deployment-Workflows behandelt.

Damit gilt ausdrücklich:

- `New-BSSECustomerProject.ps1` provisioniert keine AVD- oder Vaultwarden-Deployments.
- `pipelines/customer-onboarding.yml` bietet keine AVD-/Vaultwarden-Auswahl an.
- Customer-Onboarding und IaC-Deployment verwenden getrennte Service Connections und getrennte Sicherheitsmodelle.
- IaC folgt weiterhin `Validate → Lint/Security → Plan/What-If → Approval → Deploy → Verify`.

Firewall-Backup-Repositories sind bewusst vom OPNsenseDocumentation-Modul entkoppelt.

## 7. Security

`Firewall-*` erhält eine höhere Schutzklasse als normales `CustomerConfiguration`.

Ziel für den nächsten Security-Schritt:

- Repository-Zugriff nur für definierte Admins und Pipeline-Identität,
- kein allgemeiner Contributor-Zugriff,
- keine unkontrollierten lokalen Klone,
- kein Raw-Config-Publishing,
- Pipeline muss vor KI/Dokumentation sanitizen und validieren.

IaC verwendet getrennte Deployment-Identitäten und darf nicht über die Dokumentations-/Customer-Onboarding-Identität deployen.

Für den PlatformBootstrap-Technikerweg gilt zusätzlich:

- dedizierte Entra-Dienstidentität,
- `Basic`-Zugriff in Azure DevOps,
- Zugriff auf `00-Platform`,
- Collection-Berechtigung `Create new projects = Allow`,
- keine pauschale Mitgliedschaft in `Project Collection Administrators`,
- Service Connection nur für die vorgesehene Pipeline autorisieren.

## 8. Idempotenz

Erneute Bootstrap-Läufe:

- überschreiben keine bestehenden Repositories,
- löschen keine bestehenden Repositories,
- schreiben nichts in `Firewall-*`,
- erstellen nur fehlende Soll-Repositories,
- erzeugen bei bekannten Legacy-Namen keine Duplikate,
- überschreiben keine abweichenden vorhandenen `CustomerConfiguration`-Bootstrapdateien.

Für `CustomerConfiguration` gilt:

```text
fehlend    → PLAN / ADD
identisch  → EXISTS
abweichend → BLOCKED
```

## 9. Repositorynamen im Projekt `10-Automation`

### Beschlossen

```text
10-Automation-AzureInfrastructureCollector
10-Automation-OPNsenseDocumentation
```

Die fachlichen Komponentenbezeichnungen bleiben:

```text
AzureInfrastructureCollector
OPNsenseDocumentation
```

### Keine globale Präfix-Konvention für andere Projekte

Die Präfixierung ist für die bestehenden Repositories unter `10-Automation` beschlossen. Daraus wird **keine automatische globale Umbenennung** der Repositories unter `00-Platform`, `20-IaC`, `99-LAB` oder den Kundenprojekten abgeleitet.

### Idempotenz / Legacy-Schutz

- `10-Automation-AzureInfrastructureCollector` wird als Sollzustand exakt erkannt.
- `10-Automation-OPNsenseDocumentation` wird als Sollzustand exakt erkannt.
- Legacy-Name `AzureInfrastructureCollector` wird nicht mehr provisioniert.
- Legacy-Namen `OPNsenseDocumentation` / `OpenSenseDocumentation` werden nicht mehr provisioniert.
- Falls ausschließlich ein Legacy-Name vorhanden ist, erzeugt der Bootstrap kein Duplikat und führt keine automatische Umbenennung durch.

## 10. Zentraler Techniker-Workflow / Dual Runtime

### Beschlossen

Der normale Techniker soll das Bootstrap-Repository nicht lokal herunterladen oder pflegen müssen.

Produktiver Zielweg:

```text
Techniker
    ↓
Azure DevOps / Run pipeline
    ↓
Customer-Onboarding
    ↓
Validate
    ↓
Dry Run Customer Boundary
    ↓
Dry Run CustomerConfiguration
    ↓
Manual Approval nur bei Änderungen
    ↓
Apply
    ↓
Post-Apply Verify
```

Für lokale Entwicklung/Regressionstests existiert parallel:

```text
bootstrap/Start-BSSECustomerOnboarding.ps1
```

Beide Wege verwenden:

```text
bootstrap/New-BSSECustomerProject.ps1
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

### Automatische Laufzeit-/Authentifizierungserkennung

`BSSE.AzureDevOps.Common.ps1` unterscheidet selbstständig:

```text
Local
Pipeline
```

Local:
- vorhandenen Azure-CLI-Kontext verwenden,
- passenden gecachten Tenant-/Subscription-Kontext suchen,
- bei Bedarf gezielten interaktiven Login durchführen,
- Browser-Fallback ausschließlich lokal zulassen.

Pipeline:
- keine interaktive Anmeldung,
- kein Browser-Fallback,
- AzureCLI@3 mit Azure-DevOps-Service-Connection/WIF verwenden,
- optional `SYSTEM_ACCESSTOKEN` als Kompatibilitätsfallback,
- andernfalls Fail Closed.

### Customer-Onboarding-Pipeline

Repository-Datei:

```text
/pipelines/customer-onboarding.yml
```

Parameter:

```text
CustomerNumber
CustomerName
CustomerSlug
TenantId
AzureDocumentation
OPNsenseDocumentation
Firewalls
```

AVD und Vaultwarden sind bewusst ausgeschlossen.

Stages:

```text
Validate
DryRun
Approval
Apply
Verify
```

`DryRun` prüft sowohl Kundenboundary als auch `CustomerConfiguration` und setzt `hasChanges` als Stage-Output. Ohne `[PLAN]` werden Approval und Apply übersprungen.

`Verify` prüft nach Apply beide Bereiche erneut und bricht bei `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` ab.

### Persistente CustomerConfiguration

Implementiert über:

```text
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

Das Skript:

- ermittelt das stabile `CUST-<CustomerNumber>-*`-Projekt,
- erzeugt den erwarteten Dokumentations-Scaffold,
- vergleicht die Bootstrap-Zieldateien mit `CustomerConfiguration`,
- fügt nur fehlende Dateien hinzu,
- blockiert abweichende vorhandene Zieldateien,
- nutzt Git-Historie statt blindem Überschreiben,
- bezieht für Git einen Azure-DevOps-OAuth-/Entra-Token ohne ihn in die Remote-URL zu schreiben.

### Pipeline-Registrierung

Implementiert über:

```text
bootstrap/Register-BSSECustomerOnboardingPipeline.ps1
```

Das Skript prüft idempotent:

- `00-Platform`,
- `PlatformBootstrap`,
- `sc-platform-bootstrap-azdo`,
- vorhandene `Customer-Onboarding`-Pipeline.

Fehlt nur die Pipeline, wird sie bei `-Apply` aus `pipelines/customer-onboarding.yml` registriert; der erste Run wird übersprungen.

### Readiness

Implementiert über:

```text
bootstrap/Test-BSSECustomerOnboardingReadiness.ps1
```

Der Readiness-Check verändert keine Kundenobjekte und prüft die Voraussetzungen beider Wege.

### Bereits im Repository implementiert

- Dual-Runtime-Erkennung Local/Pipeline,
- lokales interaktives Frontend,
- fachlich identische Eingaben auf beiden Wegen,
- lokale Dry-Run-/Approval-/Apply-/Verify-Kette,
- zentrale Pipeline Validate → DryRun → Approval → Apply → Verify,
- Approval/Apply nur bei tatsächlich geplanten Änderungen,
- persistente `CustomerConfiguration` mit Bestandsschutz,
- AzureCLI@3-/WIF-Zielmodell,
- Pipeline-Registrierungsskript,
- Readiness-Check,
- harte Abgrenzung von AVD/Vaultwarden.

### Noch Azure-DevOps-seitig einzurichten

- dedizierte Entra-Dienstidentität für PlatformBootstrap,
- Service Connection `sc-platform-bootstrap-azdo` mit WIF,
- minimale Berechtigungen gemäß `docs/Customer-Onboarding-Setup.md`,
- aktuellen `PlatformBootstrap`-Stand nach `00-Platform/PlatformBootstrap` synchronisieren,
- Pipeline mit `Register-BSSECustomerOnboardingPipeline.ps1 -Apply` registrieren.

### Noch nicht runtime-verifiziert

Erst nach dem geplanten gemeinsamen Test dürfen absolut bestätigt werden:

- reale WIF-Authentifizierung,
- reale Rechte der Service-Connection-Identität,
- Git-Push nach `CustomerConfiguration`,
- Stage-/Approval-/Output-Variable-Auswertung,
- realer Apply-/Post-Apply-Idempotenzlauf.

## 11. Separater IaC-Techniker-/Deployment-Weg

### Bereits beschlossen

AVD und Vaultwarden werden als IaC-Produkte unter `20-IaC` geführt.

### Noch offen

Der zentrale Technikerweg für IaC-Deployments ist separat zu implementieren und darf nicht in `customer-onboarding.yml` integriert werden.

Zielkette:

```text
20-IaC Produkt
    ↓
Validate
    ↓
Lint / Security
    ↓
Plan / What-If
    ↓
Approval
    ↓
Deploy
    ↓
Verify
```

Die konkreten produkt-/kundenspezifischen Parameter, Environments, Approvals und Service Connections werden in den jeweiligen IaC-Umsetzungsplänen gepflegt.
