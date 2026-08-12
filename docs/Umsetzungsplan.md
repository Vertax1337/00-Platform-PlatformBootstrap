# Umsetzungsplan – BSSE Azure DevOps Platform

**Status:** Source-of-Truth  
**Version:** 1.6

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
99-LAB
```

## 1.1 `00-Platform` Repositories

### `PlatformBootstrap`

Source of Truth für den Aufbau der Azure-DevOps-Plattform.

Enthält:

- Core-Bootstrap
- Kunden-Onboarding
- Firewall-Repo-Onboarding
- gemeinsame Azure-DevOps-CLI-Authentifizierungslogik
- Organisationsprofile
- Namenskonventionen
- Plattform-/Security-Dokumentation
- zentralen Techniker-Onboarding-Workflow als Azure Pipeline

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

## 6. Modulmodell

- AzureDocumentation
- OPNsenseDocumentation
- AVD
- Vaultwarden

Firewall-Backup-Repositories sind bewusst vom OPNsenseDocumentation-Modul entkoppelt.

Das bedeutet:

- Firewall-Backup kann bereits existieren, obwohl Dokumentationsautomation noch nicht aktiv ist.
- OPNsenseDocumentation kann aktiviert sein, bevor die erste Firewall angebunden wurde.

## 7. Security

`Firewall-*` erhält eine höhere Schutzklasse als normales CustomerConfiguration.

Ziel für den nächsten Security-Schritt:

- Repository-Zugriff nur für definierte Admins und Pipeline-Identität
- kein allgemeiner Contributor-Zugriff
- keine unkontrollierten lokalen Klone
- kein Raw-Config-Publishing
- Pipeline muss vor KI/Dokumentation sanitizen und validieren

## 8. Idempotenz

Erneute Bootstrap-Läufe:

- überschreiben keine bestehenden Repositories,
- löschen keine bestehenden Repositories,
- schreiben nichts in `Firewall-*`,
- erstellen nur fehlende Soll-Repositories,
- erzeugen bei bekannten Legacy-Namen keine Duplikate.

## 9. Repositorynamen im Projekt `10-Automation`

### Beschlossen

Für die beiden aktuell bestehenden Automations-Repositories gelten als Sollnamen:

```text
10-Automation-AzureInfrastructureCollector
10-Automation-OPNsenseDocumentation
```

Hintergrund ist die eindeutige lokale Zuordnung zum Azure-DevOps-Projekt und eine saubere Clone-/Verzeichnisstruktur.

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
- Falls ausschließlich ein Legacy-Name vorhanden ist, erzeugt der Bootstrap kein Duplikat und führt keine automatische Umbenennung durch; der Lauf wird vor `-Apply` zur manuellen Prüfung blockiert.
- Bestehende Git-Inhalte und Historie werden nicht verändert.

## 10. Zentraler Techniker-Workflow / Dual Runtime

### Beschlossen

Der normale Techniker soll das Bootstrap-Repository künftig **nicht lokal herunterladen oder pflegen müssen**.

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
Dry Run
    ↓
Manual Approval
    ↓
Apply
    ↓
Post-Apply Verify
```

Das zugrunde liegende PowerShell-Skript bleibt identisch zur lokalen Entwicklungs-/Debug-Ausführung:

```text
bootstrap/New-BSSECustomerProject.ps1
```

### Automatische Laufzeit-/Authentifizierungserkennung

`BSSE.AzureDevOps.Common.ps1` entscheidet selbstständig zwischen:

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
- zuerst bereits durch `AzureCLI@3` hergestellte Azure-DevOps-Service-Connection-/WIF-Session verwenden,
- optional `SYSTEM_ACCESSTOKEN` als nicht-interaktiven Kompatibilitätsfallback automatisch an die Azure-DevOps-CLI binden,
- andernfalls Fail Closed.

### Pipeline

Repository-Datei:

```text
/pipelines/customer-onboarding.yml
```

Implementierte Stages:

```text
Validate
DryRun
Approval
Apply
Verify
```

`Verify` führt nach Apply erneut einen Dry Run aus und bricht ab, wenn noch `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` erkannt wird.

### Bevorzugte Pipeline-Identität

Zielname der Azure-DevOps-Service-Connection:

```text
sc-platform-bootstrap-azdo
```

Bevorzugte Authentifizierung:

```text
Microsoft Entra Workload Identity Federation
+ AzureCLI@3
+ connectionType: azureDevOps
```

Keine langlebigen PATs oder Client Secrets als produktiver Standard.

### Bereits im Repository implementiert

- Dual-Runtime-Erkennung Local/Pipeline
- lokale Selbstheilungslogik bleibt erhalten
- nicht-interaktiver Pipeline-Modus
- AzureCLI@3-/Service-Connection-Unterstützung
- `System.AccessToken`-Fallback
- `pipelines/customer-onboarding.yml`
- Validate → Dry Run → Approval → Apply → Verify
- `docs/Techniker-Workflow.md`

### Noch offen / nicht runtime-verifiziert

- Service Connection `sc-platform-bootstrap-azdo` in Azure DevOps anlegen
- WIF konfigurieren
- minimale Azure-DevOps-Rechte der Service-Connection-Identität festlegen und zuweisen
- Pipeline aus `/pipelines/customer-onboarding.yml` in `00-Platform` registrieren
- Pipeline-Dry-Run tatsächlich ausführen
- Apply gegen Test-Provisionierung tatsächlich ausführen
- Post-Apply-Idempotenzprüfung tatsächlich verifizieren

Bis diese Azure-DevOps-seitigen Schritte durchgeführt wurden, ist der Technikerweg **code-seitig implementiert, aber noch nicht produktiv verifiziert**.
