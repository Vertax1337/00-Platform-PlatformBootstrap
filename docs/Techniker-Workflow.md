# Techniker-Workflow – PlatformBootstrap

## Ziel

Der produktive Kunden-Onboarding-Prozess funktioniert ohne lokalen Download des Bootstrap-Repositories.

Der Techniker startet zentral in Azure DevOps:

```text
00-Platform
└── Pipeline: Customer-Onboarding
    └── YAML: /pipelines/customer-onboarding.yml
```

Für Entwicklung und Regressionstests existiert parallel ein lokales interaktives Frontend:

```text
bootstrap/Start-BSSECustomerOnboarding.ps1
```

Beide Wege verwenden dieselben fachlichen Backend-Bausteine:

```text
bootstrap/New-BSSECustomerProject.ps1
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

## Verbindliche Architekturgrenze

`Customer-Onboarding` ist **kein IaC-Deployment-Workflow**.

Dieser Workflow behandelt ausschließlich:

- Kundenprojekt / Kunden-Repositories,
- `AzureDocumentation`,
- `OPNsenseDocumentation`,
- optionale OPNsense RAW-Backup-Repositories `Firewall-*`,
- persistente Initialisierung von `CustomerConfiguration`.

Nicht Bestandteil dieses Workflows:

```text
AVD
Vaultwarden
```

AVD und Vaultwarden sind IaC-Produkte unter `20-IaC` und erhalten eigene Deployment-Workflows mit eigenen Deployment-Service-Connections, Plan/What-If, Approval, Deploy und Verify.

## Gemeinsame Ablaufsemantik

Lokal und Pipeline verwenden dieselbe fachliche Reihenfolge:

```text
Eingaben
    ↓
Validate
    ↓
Dry Run Customer Boundary
    ↓
Dry Run CustomerConfiguration
    ↓
keine Änderungen? → erfolgreich beenden
    ↓
Änderungen vorhanden
    ↓
Freigabe
    ↓
Apply Customer Boundary
    ↓
Apply CustomerConfiguration
    ↓
Post-Apply Dry Run beider Bereiche
    ↓
Idempotenz-Verifikation
```

`[BLOCKED]` verhindert ein Apply. Abweichende vorhandene Bootstrap-Zieldateien in `CustomerConfiguration` werden nicht automatisch überschrieben.

## Local

Start:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Start-BSSECustomerOnboarding.ps1"
```

Das Frontend fragt ab:

- CustomerNumber
- CustomerName
- CustomerSlug (optional)
- TenantId (optional)
- AzureDocumentation
- OPNsenseDocumentation
- Firewalls (optional, kommasepariert)

Nach dem Dry Run erfolgt eine lokale Ja/Nein-Freigabe. Ist kein `[PLAN]` vorhanden, wird kein Apply angeboten.

Die gemeinsame Authentifizierungslogik erkennt die lokale Ausführung automatisch und verwendet:

1. vorhandenen Azure-CLI-Kontext,
2. passenden gecachten Tenant-/Subscription-Kontext,
3. falls erforderlich gezielten interaktiven Login,
4. lokalen Browser-Fallback nur für die Erstinitialisierung.

Das Backend kann für Debugging weiterhin direkt per CLI-Parameter aufgerufen werden.

## Pipeline

Azure Pipelines wird automatisch erkannt. Interaktive Anmeldung und Browser-Fallback sind dort deaktiviert.

Bevorzugte Authentifizierung:

```text
AzureCLI@3
connectionType: azureDevOps
Service Connection: sc-platform-bootstrap-azdo
Microsoft Entra Workload Identity Federation
```

Fallback ist nur ein explizit gemapptes `SYSTEM_ACCESSTOKEN`; andernfalls Fail Closed.

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

`DryRun` setzt eine Output-Variable `hasChanges`. Wenn weder Kundenboundary noch `CustomerConfiguration` einen `[PLAN]`-Zustand melden, werden Approval und Apply übersprungen.

`Verify` führt nach Apply beide Dry Runs erneut aus und schlägt fehl, wenn `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` verbleibt.

## Persistente CustomerConfiguration

`Sync-BSSECustomerConfiguration.ps1` macht die generierte Kundenkonfiguration zum kontrollierten Git-Zielzustand.

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

Der Push erfolgt erst nach erfolgreichem Vergleich. Das Azure-DevOps-OAuth-/Entra-Token wird nur prozesslokal für Git verwendet und nicht in die Remote-URL geschrieben.

Dadurch ist `CustomerConfiguration` bei einem Microsoft-hosted Agent nicht mehr nur ein flüchtiges Arbeitsverzeichnis.

## Pipeline-Registrierung

Die Pipeline wird idempotent mit folgendem Plattformskript registriert:

```text
bootstrap/Register-BSSECustomerOnboardingPipeline.ps1
```

Dry Run:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Register-BSSECustomerOnboardingPipeline.ps1"
```

Apply:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Register-BSSECustomerOnboardingPipeline.ps1" `
  -Apply
```

Der erste Pipeline-Lauf wird bei der Registrierung bewusst übersprungen.

## Sicherheitsmodell der Plattformidentität

Zielname:

```text
sc-platform-bootstrap-azdo
```

Die dahinterliegende Entra-Dienstidentität wird nicht pauschal `Project Collection Administrator`.

Zielberechtigungen:

- Basic-Zugriff in Azure DevOps,
- Projektzugriff auf `00-Platform`,
- Collection-Berechtigung `Create new projects = Allow`,
- anschließend projektlokale Rechte im jeweils neu erzeugten `CUST-*` über die Projekt-Erstellerrolle.

Die Service Connection wird nur für die vorgesehene Customer-Onboarding-Pipeline autorisiert.

Details zur einmaligen Einrichtung: `docs/Customer-Onboarding-Setup.md`.

## Readiness-Check

Vor dem ersten echten Test kann ohne Kundenprovisionierung geprüft werden:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Test-BSSECustomerOnboardingReadiness.ps1"
```

Der Check prüft u. a. Git, Azure-DevOps-Zugriff, `00-Platform/PlatformBootstrap`, Service Connection, registrierte Pipeline und die lokalen Workflow-Dateien.

Er verändert keine Azure-DevOps-Kundenobjekte und ersetzt **keine** Runtime-Verifikation.

## Implementierungsstatus

### Im Repository implementiert und code-seitig verifiziert

- automatische Local-/Pipeline-Erkennung
- lokales interaktives Frontend
- identische fachliche Parameter auf beiden Wegen
- Customer Boundary Dry Run / Apply
- persistente `CustomerConfiguration` mit Bestandsschutz
- lokaler Dry Run → Freigabe → Apply → Verify
- Pipeline Validate → DryRun → Approval → Apply → Verify
- Approval/Apply nur bei tatsächlich geplanten Änderungen
- AzureCLI@3-/WIF-Zielmodell
- Pipeline-Registrierungsskript
- Readiness-Check
- harte Trennung von AVD/Vaultwarden

### Noch Azure-DevOps-seitig einzurichten

- dedizierte Entra-Dienstidentität für PlatformBootstrap,
- `sc-platform-bootstrap-azdo` mit Workload Identity Federation,
- minimale Berechtigungen gemäß `docs/Customer-Onboarding-Setup.md`,
- aktueller `PlatformBootstrap`-Stand in `00-Platform/PlatformBootstrap`,
- Pipeline mit dem Registrierungsskript registrieren.

### Noch nicht runtime-verifiziert

Bis zum geplanten gemeinsamen Test dürfen folgende Punkte nicht als bestätigt gelten:

- reale WIF-Authentifizierung der Service Connection,
- tatsächliche Berechtigungen der Pipeline-Identität,
- realer Git-Push nach `CustomerConfiguration`,
- reale Stage-/Approval-/Output-Variable-Auswertung,
- realer Apply-/Post-Apply-Idempotenzlauf.

## Separater IaC-Technikerweg

Für AVD und Vaultwarden bleibt ein eigener Techniker-/Deployment-Workflow vorgesehen und **noch offen**:

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
