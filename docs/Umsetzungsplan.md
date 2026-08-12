# Umsetzungsplan – BSSE Azure DevOps Platform

**Status:** Source-of-Truth  
**Version:** 1.9

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

Source of Truth für Aufbau und Weiterentwicklung der Azure-DevOps-Plattform.

Enthält:

- Core-Bootstrap,
- Self-Hosting-/Dependency-Initialisierung,
- Kunden-Onboarding,
- Firewall-Repo-Onboarding,
- gemeinsame Azure-DevOps-CLI-Authentifizierungslogik,
- verwaltetes Azure-DevOps-Project-Branding,
- versionierte Branding-Assets,
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

Jedes verwaltete `CUST-*`-Projekt erhält automatisch das generische Customer-Project-Icon aus `assets/project-icons/cust-generic.png`.

## 4. OPNsense RAW Backup

### Festlegung

**Eine OPNsense = ein dediziertes RAW-Git-Repository.**

Dieses Repository:

- liegt im Azure-DevOps-Kundenprojekt,
- ist ausschließlich Upstream für `os-git-backup`,
- enthält die RAW `config.xml` und ihre Git-Historie,
- wird vom Bootstrap leer erzeugt,
- erhält vom Bootstrap niemals README, `.gitignore`, YAML oder Initial-Commit.

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

```text
AzureDocumentation
OPNsenseDocumentation
```

Diese Fähigkeiten gehören zum Customer-/Dokumentations-Onboarding und verwenden die Read-only-/Sanitization-Kette der Dokumentationsplattform.

### IaC-Produkte

```text
AVD-Accelerator
Vaultwarden
```

Sie sind IaC-Produkte unter `20-IaC` und werden über separate Deployment-Workflows behandelt.

Damit gilt ausdrücklich:

- `New-BSSECustomerProject.ps1` provisioniert keine AVD- oder Vaultwarden-Deployments.
- `pipelines/customer-onboarding.yml` bietet keine AVD-/Vaultwarden-Auswahl an.
- Customer-Onboarding und IaC-Deployment verwenden getrennte Service Connections und Sicherheitsmodelle.
- IaC folgt `Validate → Lint/Security → Plan/What-If → Approval → Deploy → Verify`.

## 7. Security

`Firewall-*` erhält eine höhere Schutzklasse als normales `CustomerConfiguration`.

Für die Dokumentationsplattform bleiben vorgesehen:

- Repository-Zugriff nur für definierte Admins und Pipeline-Identität,
- kein allgemeiner Contributor-Zugriff auf RAW-Repositories,
- kein Raw-Config-Publishing,
- Sanitization/Validation vor Dokumentation/KI.

IaC verwendet getrennte Deployment-Identitäten und darf nicht über die Dokumentations-/Customer-Onboarding-Identität deployen.

### PlatformBootstrap-Identität

Zielidentität:

```text
sp-bsse-platform-bootstrap-azdo
```

Ziel-Service-Connection:

```text
sc-platform-bootstrap-azdo
```

Least-Privilege-Zustand:

- secretless Entra-App/Service Principal,
- `Basic` in Azure DevOps,
- `00-Platform / Readers`,
- Collection-Berechtigung `Create new projects = Allow`,
- **keine** Mitgliedschaft in `Project Collection Administrators`,
- WIF-Service-Connection ausschließlich für `Customer-Onboarding` autorisiert.

Ein vorhandenes Deny oder widersprüchliche bestehende Identitäts-/Endpointkonfiguration wird nicht automatisch überschrieben.

### Project Branding

Für Project Branding wird kein separates Credential eingeführt. Die bestehende lokale bzw. Pipeline-Authentifizierung wird wiederverwendet.

Die offizielle `Set Project Avatar`-API dokumentiert den OAuth-Scope `vso.project_manage`. Für den idempotenten SHA-256-Marker werden zusätzlich Project Properties gelesen und geschrieben; die ausführende Identität benötigt dafür die entsprechende Projektberechtigung (`Manage project properties`).

Branding-Fehler werden nicht zu einer reinen Warning degradiert. Asset-, Project-ID-, Berechtigungs-, Avatar-API- oder Marker-Validierungsfehler blockieren den betroffenen Bootstrap-Lauf. Bereits zuvor erfolgreich erzeugte Azure-DevOps-Objekte werden nicht gelöscht oder zurückgerollt.

## 8. Idempotenz / Bestandsschutz

Erneute Bootstrap-Läufe:

- überschreiben keine bestehenden Repositories,
- löschen keine bestehenden Repositories,
- schreiben nichts in `Firewall-*`,
- erstellen nur fehlende Soll-Repositories,
- erzeugen bei bekannten Legacy-Namen keine Duplikate,
- überschreiben keine abweichenden vorhandenen `CustomerConfiguration`-Bootstrapdateien,
- schreiben Project Avatars nicht erneut, wenn der verwaltete Asset-Hash-Marker bereits dem Sollzustand entspricht.

Für `CustomerConfiguration` gilt:

```text
fehlend    → PLAN / ADD
identisch  → EXISTS
abweichend → BLOCKED
```

Für Project Branding gilt:

```text
Asset fehlt/ungültig
→ BLOCKED

Projekt noch nicht vorhanden (Dry Run)
→ PLAN Avatar nach Projekterstellung

Project-Avatar-SHA-Marker fehlt/abweichend
→ PLAN / bei Apply SET + Marker-Verify

Project-Avatar-SHA-Marker identisch
→ EXISTS / kein Avatar-Write

Avatar-API / Marker-Write / Marker-Readback fehlerhaft
→ BLOCKED
```

Die aktuell dokumentierte Azure-DevOps-Core-API bietet keinen Project-Avatar-GET-Readback. Deshalb wird als verwalteter Marker folgende Project Property verwendet:

```text
BSSE.PlatformBootstrap.ProjectAvatarSha256
```

Bekannte Grenze: Eine manuelle Avatar-Änderung außerhalb von PlatformBootstrap kann bei unverändertem Marker nicht zuverlässig erkannt werden. Es wird bewusst kein undokumentierter Readback-Endpoint verwendet.

Für die Self-Hosting-Ausführungsquelle gilt:

```text
Azure PlatformBootstrap leer
→ PLAN / Seed aus lokalem committed HEAD

Azure main == lokaler committed HEAD
→ EXISTS

lokaler Working Tree dirty
→ BLOCKED

Azure main != lokaler committed HEAD
→ BLOCKED

nicht-leeres Azure Repo ohne main
→ BLOCKED
```

Es gibt keinen automatischen Force-Push.

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

Aus dieser Entscheidung wird keine globale `<Projekt>-<Repository>`-Konvention für andere Projekte abgeleitet.

## 10. Self-Hosting Bootstrap / Erstinitialisierung

### Beschlossen

Eine neue Plattform besitzt zu Beginn noch keine zentrale Customer-Onboarding-Pipeline und keine dafür nutzbare WIF-Service-Connection. Der allererste Lauf erfolgt daher lokal.

Das lokale Frontend prüft automatisch vor der Kundenabfrage:

```text
bootstrap/Initialize-BSSEPlatformDependencies.ps1
```

Ablauf:

```text
Start-BSSECustomerOnboarding.ps1
    ↓
Dependency Dry Run
    ↓
Dependencies vollständig?
 ├─ Ja → Customer-Onboarding
 └─ Nein
      ↓
PLATFORM INITIALIZATION REQUIRED
      ↓
separate lokale Freigabe
      ↓
Dependency Apply
      ↓
Dependency Verify
      ↓
Customer-Onboarding
```

### Was automatisch als Dependency behandelt wird

```text
Core-Projekte/-Repositories inkl. Project Branding
00-Platform/PlatformBootstrap Seed
sp-bsse-platform-bootstrap-azdo
Azure-DevOps-Service-Principal-Entitlement
Basic + 00-Platform/Readers
Create new projects = Allow
sc-platform-bootstrap-azdo (WIF)
fic-sc-platform-bootstrap-azdo
Customer-Onboarding Pipeline
pipeline-spezifische Service-Connection-Autorisierung
```

### Was nicht automatisch erzeugt wird

Die Azure-DevOps-Organisation selbst ist eine äußere Voraussetzung und muss bereits existieren.

Der lokale Erstinstallations-Administrator muss außerdem bereits über die notwendigen Entra-/Azure-DevOps-Rechte verfügen. Der Bootstrap erhöht die Rechte des ausführenden Administrators nicht selbst.

### Privilege-Boundary

`Initialize-BSSEPlatformDependencies.ps1 -Apply` ist aus Azure Pipelines blockiert.

Damit gilt:

```text
lokaler Erstinstallations-Admin
→ darf nach Dry Run + expliziter Freigabe Plattform-Dependencies herstellen

Customer-Onboarding Pipeline
→ darf vorhandene Dependencies verwenden
→ darf sich selbst keine Identität oder organisationsweiten Rechte geben
```

### Runtime-Schema für Azure-DevOps-WIF

Der neue Azure-DevOps-Service-Connection-Typ wird nicht mit einem geratenen undokumentierten JSON-Schema hartcodiert.

Der Bootstrap fragt die Service-Endpoint-Type-Metadaten der Zielorganisation ab und akzeptiert ausschließlich einen eindeutigen `Azure DevOps`-Endpoint mit `WorkloadIdentityFederation`.

Unbekannte erforderliche Inputs führen zu Fail Closed.

## 11. Customer-Onboarding / Dual Runtime

### Zentraler Technikerweg

```text
Techniker
    ↓
Azure DevOps / Run pipeline
    ↓
Customer-Onboarding
    ↓
Validate
    ↓
Dry Run Customer Boundary + Project Branding
    ↓
Dry Run CustomerConfiguration
    ↓
Manual Approval nur bei Änderungen
    ↓
Apply
    ↓
Post-Apply Verify
```

### Lokaler Entwicklungs-/Regressionstestweg

```text
bootstrap/Start-BSSECustomerOnboarding.ps1
```

Nach erfolgreicher Dependency-Prüfung verwendet er dieselben fachlichen Parameter und Backend-Bausteine wie die Pipeline.

Beide Wege verwenden:

```text
bootstrap/New-BSSECustomerProject.ps1
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

Project Branding ist Bestandteil von `New-BSSECustomerProject.ps1` und benötigt keinen separaten Techniker-Schritt.

### Authentifizierung

`BSSE.AzureDevOps.Common.ps1` unterscheidet:

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

### Pipeline-Parameter

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

### Pipeline-Stages

```text
Validate
DryRun
Approval
Apply
Verify
```

`DryRun` prüft Kundenboundary einschließlich Project Branding sowie `CustomerConfiguration` und setzt `hasChanges`. Ohne `[PLAN]` werden Approval und Apply übersprungen.

`Verify` bricht bei verbleibendem `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` ab. Ein korrekt gesetzter Branding-Marker muss deshalb im Verify als `EXISTS` erscheinen.

## 12. Persistente CustomerConfiguration

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
- verwendet OAuth-/Entra-Token ohne Token in der Remote-URL.

## 13. Pipeline-Registrierung und Readiness

Pipeline-Registrierung:

```text
bootstrap/Register-BSSECustomerOnboardingPipeline.ps1
```

Readiness:

```text
bootstrap/Test-BSSECustomerOnboardingReadiness.ps1
```

Der Readiness-Check verwendet den Self-Hosting-Dependency-Bootstrap ausschließlich im Dry-Run-/Verify-Modus.

```text
kein PLAN / kein BLOCKED → READY
PLAN                    → Dependency fehlt
BLOCKED / Fehler         → NOT READY
```

## 14. Project Branding

### Assets

```text
assets/project-icons/00-platform.png
assets/project-icons/10-automation.png
assets/project-icons/20-iac.png
assets/project-icons/99-lab.png
assets/project-icons/cust-generic.png
```

Verbindliches Mapping:

```text
00-Platform   → 00-platform.png
10-Automation → 10-automation.png
20-IaC        → 20-iac.png
99-LAB        → 99-lab.png
CUST-*        → cust-generic.png
```

Zentrale wiederverwendbare Komponente:

```text
bootstrap/BSSE.AzureDevOps.Branding.ps1
```

Validierung:

```text
Asset-Mapping
→ Asset vorhanden
→ PNG-Signatur
→ SHA-256
→ Projekt / Project-ID
→ bestehender Hash-Marker
→ bei Bedarf Avatar PUT
→ HTTP 200
→ Hash-Marker PATCH
→ Hash-Marker GET / exakte Verifikation
```

Regressionstest:

```text
tests/Test-BSSEProjectBranding.ps1
```

Der Test fixiert Mapping, Dateigrößen und SHA-256 der fünf freigegebenen Branding-Assets.

Details und API-/Idempotenzgrenzen:

```text
docs/Project-Branding.md
```

## 15. Implementierungsstatus

### Bereits beschlossen

- Dokumentationsplattform und IaC strikt getrennt.
- Normaler Technikerweg erfolgt zentral über Azure DevOps.
- Erstinitialisierung einer neuen Plattform erfolgt lokal.
- Plattform-Dependencies werden als idempotenter Sollzustand behandelt.
- privilegierte Dependency-Änderungen benötigen separaten lokalen Dry Run + Freigabe.
- Pipeline darf sich nicht selbst privilegieren.
- Project Branding ist Teil des verwalteten Azure-DevOps-Projekt-Sollzustands.
- Alle `CUST-*` verwenden zunächst dasselbe generische Customer-Icon.

### Bereits im Repository implementiert

- Core-Bootstrap,
- Dual-Runtime-Erkennung,
- `Initialize-BSSEPlatformDependencies.ps1`,
- automatischer Dependency-Preflight im lokalen Frontend,
- secretless Entra-Identitätsplanung/-erstellung,
- Azure-DevOps-Entitlement Basic + Readers,
- gezielte `Create new projects`-ACL,
- dynamische WIF-Service-Endpoint-Type-Erkennung,
- federated-credential-Management,
- Pipeline-Registrierung und pipeline-spezifische Endpoint-Autorisierung,
- lokaler und zentraler Customer-Onboarding-Workflow,
- persistente `CustomerConfiguration`,
- zentrale Branding-Funktion und Projekt-Mapping,
- Core-/Customer-Provisionierungsintegration des Brandings,
- Branding-Asset-/Mapping-Regressionstest,
- Readiness-Check.

### Noch nicht runtime-verifiziert

Bis zum echten Erstinstallations-/Runtime-Test sind insbesondere nicht absolut bestätigt:

- reale Entra-App/SP-Erstellung im BSSE-Tenant,
- reales Service-Principal-Entitlement in BSSE-CloudOps,
- tatsächliche `Create new projects`-ACL-Zuweisung,
- tatsächlich gelieferte Endpoint-Type-Metadaten für die Azure-DevOps-WIF-Service-Connection,
- reale Erstellung von `sc-platform-bootstrap-azdo`,
- reales federated credential,
- pipeline-spezifische Service-Connection-Autorisierung,
- WIF-Pipeline-Authentifizierung,
- Git-Push nach `CustomerConfiguration`,
- realer Project-Avatar-PUT für Core-/Customer-Projekte,
- reale Project-Property-Marker-Schreib-/Leseverifikation,
- tatsächliche Anzeige der Icons in der Azure-DevOps-UI,
- realer Apply-/Post-Apply-Idempotenzlauf.

## 16. Separater IaC-Techniker-/Deployment-Weg

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