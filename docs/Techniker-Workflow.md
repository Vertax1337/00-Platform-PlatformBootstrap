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

Project Branding ist Bestandteil der Projekt-Provisionierung selbst und benötigt keinen separaten Techniker-Schritt.

## Verbindliche Architekturgrenze

`Customer-Onboarding` ist **kein IaC-Deployment-Workflow**.

Dieser Workflow behandelt ausschließlich:

- Kundenprojekt / Kunden-Repositories,
- generisches Customer-Project-Branding,
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
Core-Project-Branding
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

Die Core-Avatare werden über dieselbe zentrale Branding-Komponente verwaltet wie Customer-Projekte.

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

Project Branding verwendet dieselbe bestehende Authentifizierung. Es wird kein zusätzliches PAT oder Client Secret eingeführt.

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
Dry Run Customer Boundary + Project Branding
    ↓
Dry Run CustomerConfiguration
    ↓
keine Änderungen? → erfolgreich beenden
    ↓
Änderungen vorhanden
    ↓
lokale Freigabe
    ↓
Apply Customer Boundary + Project Branding
    ↓
Apply CustomerConfiguration
    ↓
Post-Apply Dry Run beider Bereiche
    ↓
Idempotenz-Verifikation
```

`[BLOCKED]` verhindert ein Apply. Das gilt auch für Asset-, Project-ID-, Avatar-API- oder Project-Property-Fehler des Brandings.

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

Es existiert bewusst **kein** Project-Icon-Parameter. Jedes `CUST-*` erhält automatisch:

```text
assets/project-icons/cust-generic.png
```

### Stages

```text
Validate
DryRun
Approval
Apply
Verify
```

`DryRun` setzt `hasChanges`. Wenn weder Kundenboundary einschließlich Project Branding noch `CustomerConfiguration` einen `[PLAN]`-Zustand melden, werden Approval und Apply übersprungen.

`Verify` führt nach Apply beide Dry Runs erneut aus und schlägt fehl, wenn `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` verbleibt. Das Branding muss im stabilen Zustand über seinen verwalteten SHA-256-Marker als `EXISTS` erscheinen.

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

## 8. Project Branding

Zentrale Implementierung:

```text
bootstrap/BSSE.AzureDevOps.Branding.ps1
```

Customer-Mapping:

```text
CUST-* → assets/project-icons/cust-generic.png
```

Die Core-Projekte verwenden ihre jeweils fest zugeordneten Assets. Der Bootstrap verwaltet den idempotenten Zustand über:

```text
BSSE.PlatformBootstrap.ProjectAvatarSha256
```

Fehlt oder unterscheidet sich der Marker, wird der Avatar im Dry Run als `PLAN` ausgewiesen. Bei Apply wird zuerst die offizielle Project-Avatar-API aufgerufen; nur nach erfolgreichem API-Resultat wird der SHA-256-Marker geschrieben und anschließend wieder gelesen/verifiziert.

Die dokumentierte Project-Avatar-Core-API bietet keinen Avatar-GET-Readback. Eine rein manuelle Avatar-Änderung außerhalb des Bootstraps ist deshalb bei unverändertem Marker nicht zuverlässig erkennbar. Details: `docs/Project-Branding.md`.

## 9. Readiness-Check

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

## 10. Implementierungsstatus

### Bereits beschlossen

- normaler Technikerweg zentral über Azure DevOps,
- lokale Ausführung für Entwicklung/Regression und Plattform-First-Run,
- automatische Dependency-Erkennung vor lokalem Kunden-Onboarding,
- separate lokale Freigabe für Plattforminitialisierung,
- Pipeline darf sich nicht selbst privilegieren,
- Dokumentation und IaC strikt getrennt,
- Project Branding ist Teil der Projekt-Provisionierung und kein manueller Techniker-Schritt.

### Code-seitig im Branding-Branch implementiert

- zentrale `BSSE.AzureDevOps.Branding.ps1`,
- Core-Project-Branding-Integration,
- automatisches Customer-Project-Branding,
- SHA-256-Markerstrategie,
- Asset-/PNG-Validierung,
- Avatar-API- und Marker-Fail-Closed-Validierung,
- bestehende Local-/Pipeline-Authentifizierung wird wiederverwendet,
- Mapping-/Asset-Regressionstest.

Der Branding-Branch darf erst nach versionierter Aufnahme der fünf freigegebenen PNG-Assets als merge-fertig betrachtet werden.

### Noch nicht runtime-verifiziert

Bis zum ersten echten Plattform-/Branding-Lauf dürfen insbesondere nicht als tatsächlich bestätigt gelten:

- reale Entra-App/SP-Erstellung,
- reales Azure-DevOps-Service-Principal-Entitlement,
- tatsächliche `Create new projects`-ACL-Zuweisung,
- die real von BSSE-CloudOps gelieferten Endpoint-Type-Metadaten,
- reale Erstellung der Azure-DevOps-WIF-Service-Connection,
- reales federated credential,
- pipeline-spezifische Endpoint-Autorisierung,
- WIF-Authentifizierung der Pipeline,
- realer Git-Push in `CustomerConfiguration`,
- realer Project-Avatar-PUT,
- realer Project-Property-Marker-Write/Readback,
- tatsächliche Anzeige der Icons in Azure DevOps,
- realer Apply-/Post-Apply-Idempotenzlauf.

## 11. Separater IaC-Technikerweg

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
