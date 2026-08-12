# Techniker-Workflow – PlatformBootstrap

## Ziel

Der produktive Kunden-Onboarding-Prozess funktioniert ohne lokalen Download oder lokale Pflege des Bootstrap-Repositories.

Der normale Techniker startet zentral in Azure DevOps:

```text
00-Platform
└── Pipeline: Customer-Onboarding
    └── YAML: /pipelines/customer-onboarding.yml
```

Nur eine **noch nicht selbsttragende Erstinstallation** der Plattform wird lokal initialisiert.

Für Entwicklung, Regressionstests und diesen einmaligen First-Run existiert:

```text
bootstrap/Start-BSSECustomerOnboarding.ps1
```

## Verbindliche Architekturgrenze

`Customer-Onboarding` ist **kein IaC-Deployment-Workflow**.

Dieser Workflow behandelt ausschließlich:

- Kundenprojekt / Kunden-Repositories,
- `AzureDocumentation`,
- `OPNsenseDocumentation`,
- optionale OPNsense RAW-Backup-Repositories `Firewall-*`,
- persistente Initialisierung von `CustomerConfiguration`.

Nicht Bestandteil:

```text
AVD
Vaultwarden
```

AVD und Vaultwarden sind IaC-Produkte unter `20-IaC` und erhalten eigene Deployment-Workflows mit eigenen Deployment-Service-Connections, Plan/What-If, Approval, Deploy und Verify.

## 1. First Run einer neuen Plattform

Start lokal:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Start-BSSECustomerOnboarding.ps1"
```

Noch bevor Kundendaten abgefragt werden:

```text
=== PLATFORM DEPENDENCIES / SELF-HOSTING READINESS ===
```

Das Frontend ruft den Dependency-Bootstrap ohne `-Apply` auf:

```text
bootstrap/Initialize-BSSEPlatformDependencies.ps1
```

### Plattform bereits vollständig

```text
Dependency Dry Run
→ kein PLAN
→ kein BLOCKED
→ direkt zur Kundenmaske
```

### Plattform noch nicht vollständig

```text
Dependency Dry Run
    ↓
PLAN-Zustände gefunden
    ↓
PLATFORM INITIALIZATION REQUIRED
    ↓
Plattform-Dependencies jetzt einmalig lokal einrichten? [j/N]
```

Erst bei `Ja` wird der Dependency-Apply ausgeführt.

Anschließend folgt automatisch ein erneuter Dependency-Dry-Run. Bleibt `[PLAN]` oder `[BLOCKED]`, wird **kein Kunden-Onboarding** gestartet.

## 2. Was beim First Run automatisch eingerichtet wird

Der lokale Self-Hosting-Bootstrap behandelt als Sollzustand:

```text
Core-Projekte/-Repositories
        ↓
00-Platform/PlatformBootstrap
        ↓
sp-bsse-platform-bootstrap-azdo
        ↓
Basic + 00-Platform/Readers
        ↓
Create new projects = Allow
        ↓
sc-platform-bootstrap-azdo (WIF)
        ↓
fic-sc-platform-bootstrap-azdo
        ↓
Customer-Onboarding Pipeline
        ↓
Pipeline-spezifische Service-Connection-Autorisierung
```

### Voraussetzungen außerhalb des Skripts

Die Azure-DevOps-Organisation selbst muss bereits existieren.

Der ausführende lokale Erstinstallations-Administrator benötigt bereits:

- Zugriff auf die Azure-DevOps-Organisation,
- die erforderlichen Azure-DevOps-Administrationsrechte für den Plattformaufbau,
- die erforderlichen Microsoft-Entra-Rechte zum Erstellen der secretless App/SP-Identität.

Das Skript erhöht **nicht** die Rechte des ausführenden Administrators.

## 3. Self-Hosting-Sicherheitsgrenzen

### Kein Self-Privilege aus Pipelines

Folgendes ist aus Azure Pipelines blockiert:

```powershell
Initialize-BSSEPlatformDependencies.ps1 -Apply
```

Die Pipeline darf die vorhandene Plattformidentität benutzen, sich aber keine Identität oder organisationsweiten Rechte selbst geben.

### Kein Force-Push des PlatformBootstrap

Bei der initialen Synchronisation nach:

```text
00-Platform / PlatformBootstrap
```

gilt:

```text
leeres Azure Repo + sauberer committed lokaler Stand
→ Seed erlaubt

identischer main
→ EXISTS

lokaler Working Tree dirty
→ BLOCKED

abweichender Azure main
→ BLOCKED
```

### Least Privilege der Plattformidentität

Ziel:

```text
Entra SP: sp-bsse-platform-bootstrap-azdo
Azure DevOps: Basic
00-Platform: Readers
Collection: Create new projects = Allow
```

Keine pauschale Mitgliedschaft in:

```text
Project Collection Administrators
```

Service Connection:

```text
sc-platform-bootstrap-azdo
```

wird ausschließlich für:

```text
Customer-Onboarding
```

autorisiert.

## 4. Normaler lokaler Customer-Onboarding-Weg

Nach erfolgreicher Dependency-Prüfung fragt das lokale Frontend:

- CustomerNumber
- CustomerName
- CustomerSlug (optional)
- TenantId (optional)
- AzureDocumentation
- OPNsenseDocumentation
- Firewalls (optional, kommasepariert)

Ablauf:

```text
Eingaben
    ↓
Dry Run Customer Boundary
    ↓
Dry Run CustomerConfiguration
    ↓
keine Änderungen? → erfolgreich beenden
    ↓
Änderungen vorhanden
    ↓
lokale Freigabe
    ↓
Apply Customer Boundary
    ↓
Apply CustomerConfiguration
    ↓
Post-Apply Dry Run beider Bereiche
    ↓
Idempotenz-Verifikation
```

`[BLOCKED]` verhindert ein Apply.

## 5. Zentraler Technikerweg

Nach einmaliger Self-Hosting-Initialisierung benötigt der normale Techniker keinen lokalen Clone mehr.

Azure DevOps:

```text
00-Platform
└── Customer-Onboarding
```

Pipeline-Parameter:

- CustomerNumber
- CustomerName
- CustomerSlug (optional)
- TenantId (optional)
- AzureDocumentation
- OPNsenseDocumentation
- Firewalls (optional, kommasepariert)

AVD- oder Vaultwarden-Parameter existieren bewusst nicht.

### Stages

```text
Validate
DryRun
Approval
Apply
Verify
```

`DryRun` setzt `hasChanges`. Wenn weder Kundenboundary noch `CustomerConfiguration` einen `[PLAN]`-Zustand melden, werden Approval und Apply übersprungen.

`Verify` führt nach Apply beide Dry Runs erneut aus und schlägt fehl, wenn `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` verbleibt.

## 6. Gemeinsame Authentifizierungslogik

`BSSE.AzureDevOps.Common.ps1` erkennt Local vs Pipeline.

### Local

1. vorhandenen Azure-CLI-Kontext verwenden,
2. passenden gecachten Tenant-/Subscription-Kontext suchen,
3. bei Bedarf gezielten interaktiven Login durchführen,
4. Browser-Fallback ausschließlich lokal zulassen.

### Pipeline

Bevorzugt:

```text
AzureCLI@3
connectionType: azureDevOps
Service Connection: sc-platform-bootstrap-azdo
Microsoft Entra Workload Identity Federation
```

Keine interaktive Anmeldung, kein Browser-Fallback. Optional bleibt ein explizit gemapptes `SYSTEM_ACCESSTOKEN` als Kompatibilitätsfallback; andernfalls Fail Closed.

## 7. Persistente CustomerConfiguration

Beide Wege verwenden:

```text
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

Verhalten:

```text
Datei fehlt
→ PLAN / bei Apply hinzufügen

Datei identisch
→ EXISTS / no change

Datei existiert abweichend
→ BLOCKED
→ kein automatisches Überschreiben
```

Der Git-Push erfolgt erst nach erfolgreichem Vergleich. Das Azure-DevOps-OAuth-/Entra-Token wird prozesslokal verwendet und nicht in die Remote-URL geschrieben.

## 8. Readiness-Check

Nach der Erstinitialisierung beziehungsweise vor dem ersten realen Kunden-Test:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Test-BSSECustomerOnboardingReadiness.ps1"
```

Der Check verändert keine Plattform- oder Kundenobjekte. Er führt den Dependency-Bootstrap ausschließlich im Dry-Run-/Verify-Modus aus.

```text
kein PLAN / kein BLOCKED → READY
PLAN                    → NOT READY / Dependency fehlt
BLOCKED / Fehler         → NOT READY
```

## 9. Implementierungsstatus

### Bereits beschlossen

- normaler Technikerweg zentral über Azure DevOps,
- lokale Ausführung für Entwicklung/Regression und Plattform-First-Run,
- automatische Dependency-Erkennung vor lokalem Kunden-Onboarding,
- separate lokale Freigabe für Plattforminitialisierung,
- Pipeline darf sich nicht selbst privilegieren,
- Dokumentation und IaC strikt getrennt.

### Im Repository implementiert

- automatische Local-/Pipeline-Erkennung,
- `Initialize-BSSEPlatformDependencies.ps1`,
- Dependency-Preflight im lokalen Frontend,
- Core-Bootstrap-Integration,
- sicherer Seed von `PlatformBootstrap`,
- secretless Entra-App/SP-Sollzustand,
- Azure-DevOps-Entitlement Basic + Readers,
- gezielte `Create new projects`-ACL,
- dynamische WIF-Service-Endpoint-Type-Erkennung,
- federated-credential-Sollzustand,
- Pipeline-Registrierung und pipeline-spezifische Service-Connection-Autorisierung,
- lokales Customer-Onboarding,
- zentraler Pipelineweg,
- persistente `CustomerConfiguration`,
- Readiness-Check.

### Noch nicht runtime-verifiziert

Bis zum ersten echten Plattform-First-Run dürfen insbesondere nicht als tatsächlich bestätigt gelten:

- reale Entra-App/SP-Erstellung,
- reales Azure-DevOps-Service-Principal-Entitlement,
- tatsächliche `Create new projects`-ACL-Zuweisung,
- die real von BSSE-CloudOps gelieferten Endpoint-Type-Metadaten,
- reale Erstellung der Azure-DevOps-WIF-Service-Connection,
- reales federated credential,
- pipeline-spezifische Endpoint-Autorisierung,
- WIF-Authentifizierung der Pipeline,
- realer Git-Push in `CustomerConfiguration`,
- realer Apply-/Post-Apply-Idempotenzlauf.

## 10. Separater IaC-Technikerweg

AVD und Vaultwarden bleiben außerhalb dieses Workflows:

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
