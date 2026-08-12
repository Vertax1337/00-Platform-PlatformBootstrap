# BSSE Azure DevOps Platform – Bootstrap v1.7

## Zielmodell

```text
BSSE-CloudOps
│
├── 00-Platform
│   ├── PlatformBootstrap
│   ├── PipelineTemplates
│   ├── DocumentationEngine
│   ├── SecurityValidation
│   └── SharedModules
│
├── 10-Automation
│   ├── 10-Automation-AzureInfrastructureCollector
│   └── 10-Automation-OPNsenseDocumentation
│
├── 20-IaC
│   ├── Vaultwarden
│   ├── AVD-Accelerator
│   └── Shared-IaC-Modules
│
├── 99-LAB
│
└── CUST-<interne Kunden-/Debitorennummer>-<Kundenname>
    ├── CustomerConfiguration
    ├── Documentation
    └── Firewall-<Kundenname>-<Firewall/Standort>   # 0..n
```

Die interne Kunden-/Debitorennummer ist die stabile technische Kunden-ID.

## Verbindliche Architekturgrenze

Die Plattform trennt **Dokumentation** und **IaC-Deployment** strikt.

### Dokumentationsplattform

```text
AzureDocumentation
OPNsenseDocumentation
```

Diese Fähigkeiten werden über das Kunden-/Dokumentations-Onboarding aktiviert und nutzen Read-only-/Sanitization-Prozesse.

### IaC-Produkte

```text
AVD-Accelerator
Vaultwarden
```

Diese Produkte liegen unter `20-IaC` und werden **nicht** durch `New-BSSECustomerProject.ps1` oder `/pipelines/customer-onboarding.yml` deployed.

IaC erhält einen separaten Deployment-Weg:

```text
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

## Wiederholte Läufe / Umfirmierung

Die Debitorennummer ist die primäre Kundenidentität. Der Bootstrap sucht zuerst nach:

```text
CUST-<CustomerNumber>-*
```

Existiert genau ein solches Projekt, wird dieses wiederverwendet – selbst wenn sich der Firmenname später ändert.

## OPNsense RAW Git Backup

Ein Kunde kann **0 bis n OPNsense-Firewalls** besitzen.

```text
CUST-4711-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
├── Firewall-Cannon-Deutschland-GmbH-HQ
└── Firewall-Cannon-Deutschland-GmbH-Branch01
```

Die `Firewall-*` Repositories sind `RAW / CONFIDENTIAL` Upstreams für OPNsense `os-git-backup` und werden vollständig leer erzeugt.

## Repositorynamen unter `10-Automation`

```text
10-Automation-AzureInfrastructureCollector
10-Automation-OPNsenseDocumentation
```

Lokale Zielstruktur:

```text
Repositorys/
└── DEVOPS_Plattform/
    └── 10-Automation/
        ├── 10-Automation-AzureInfrastructureCollector/
        └── 10-Automation-OPNsenseDocumentation/
```

Für Repositories anderer Projekte ist damit **keine globale Umbenennung auf `<Projekt>-<Repository>` beschlossen**.

## v1.7 – vollständiger lokaler und zentraler Customer-Onboarding-Weg

Beide Frontends verwenden dieselben fachlichen Backend-Bausteine:

```text
bootstrap/New-BSSECustomerProject.ps1
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

### Lokal

Interaktiver Einstieg:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Start-BSSECustomerOnboarding.ps1"
```

Ablauf:

```text
Eingaben
  ↓
Dry Run Customer Boundary
  ↓
Dry Run CustomerConfiguration
  ↓
Bestätigung nur bei Änderungen
  ↓
Apply
  ↓
Post-Apply Verify
```

### Zentraler Technikerweg

```text
00-Platform / Customer-Onboarding
YAML: /pipelines/customer-onboarding.yml
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

AVD und Vaultwarden sind bewusst **keine Parameter** dieser Pipeline.

Stages:

```text
Validate
  ↓
DryRun
  ↓
Approval nur bei Änderungen
  ↓
Apply
  ↓
Verify
```

Bevorzugte Pipeline-Authentifizierung:

```text
AzureCLI@3
connectionType: azureDevOps
Service Connection: sc-platform-bootstrap-azdo
Microsoft Entra Workload Identity Federation
```

## Persistente CustomerConfiguration

`Sync-BSSECustomerConfiguration.ps1` vergleicht den erwarteten Dokumentations-Scaffold mit dem Kundenrepository.

```text
Datei fehlt     → PLAN / bei Apply hinzufügen
Datei identisch → EXISTS / no change
Datei abweichend→ BLOCKED
```

Abweichende vorhandene Kundenkonfiguration wird nicht automatisch überschrieben.

Der Git-Zugriff verwendet ein Azure-DevOps-OAuth-/Entra-Token, ohne es in die Remote-URL zu schreiben.

## Pipeline einmalig registrieren

Voraussetzungen und Least-Privilege-Setup:

```text
docs/Customer-Onboarding-Setup.md
```

Registrierungs-Dry-Run:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Register-BSSECustomerOnboardingPipeline.ps1"
```

Registrierung:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Register-BSSECustomerOnboardingPipeline.ps1" `
  -Apply
```

Der erste Pipeline-Run wird bei der Registrierung bewusst nicht ausgelöst.

## Readiness prüfen

Vor dem ersten realen Onboarding-Test:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Test-BSSECustomerOnboardingReadiness.ps1"
```

Dieser Check prüft Voraussetzungen und verändert keine Kundenobjekte.

## Aktueller Verifikationsstatus

### Code-seitig implementiert

- lokales interaktives Frontend,
- Azure-DevOps-Run-Pipeline,
- automatische Local-/Pipeline-Erkennung,
- Dry Run / Approval / Apply / Verify,
- persistente `CustomerConfiguration` mit Bestandsschutz,
- WIF-/AzureCLI@3-Zielmodell,
- idempotente Pipeline-Registrierung,
- Readiness-Check,
- harte Trennung zu AVD/Vaultwarden.

### Vor dem ersten Test noch Azure-DevOps-seitig einzurichten

- dedizierte Entra-Dienstidentität,
- `sc-platform-bootstrap-azdo` mit Workload Identity Federation,
- minimale Rechte gemäß `docs/Customer-Onboarding-Setup.md`,
- aktueller Repository-Stand in `00-Platform/PlatformBootstrap`,
- Registrierung der `Customer-Onboarding`-Pipeline.

### Noch nicht runtime-verifiziert

Bis zum realen Test sind insbesondere WIF-Authentifizierung, reale Berechtigungen, Git-Push nach `CustomerConfiguration`, Stage-/Approval-Auswertung und Post-Apply-Idempotenz **nicht als tatsächlich verifiziert zu betrachten**.

Details:

```text
docs/Techniker-Workflow.md
docs/Customer-Onboarding-Setup.md
docs/Umsetzungsplan.md
```
