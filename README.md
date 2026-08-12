# BSSE Azure DevOps Platform – Bootstrap v1.6.1

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

Existiert genau ein solches Projekt, wird dieses wiederverwendet – selbst wenn sich der Firmenname später ändert. Dadurch erzeugt eine Umfirmierung kein zweites Kundenprojekt.

## OPNsense RAW Git Backup

Ein Kunde kann **0 bis n OPNsense-Firewalls** besitzen.

```text
CUST-4711-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
├── Firewall-Cannon-Deutschland-GmbH-HQ
└── Firewall-Cannon-Deutschland-GmbH-Branch01
```

Die `Firewall-*` Repositories sind `RAW / CONFIDENTIAL` Upstreams für OPNsense `os-git-backup`.

Der Bootstrap erstellt diese Repositories vollständig leer:

- kein README
- kein `.gitignore`
- kein `azure-pipelines.yml`
- kein Initial-Commit
- kein Scaffold
- keine Sanitized Config

## Lokaler Entwicklungsweg

Dry Run:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\New-BSSECustomerProject.ps1" `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "4711" `
  -CustomerName "Cannon Deutschland GmbH" `
  -TenantId "b1e23349-29c5-410c-befa-ee649ea88549" `
  -Modules AzureDocumentation,OPNsenseDocumentation `
  -Firewalls "HQ","Branch01"
```

Apply mit demselben Aufruf plus `-Apply`.

Die erlaubten `-Modules` sind ausschließlich:

```text
AzureDocumentation
OPNsenseDocumentation
```

Ein Aufruf mit `AVD`, `AVD-Accelerator` oder `Vaultwarden` wird bewusst abgewiesen, weil dies IaC-Produkte sind.

## Verantwortlichkeiten

```text
CUST-xxx / Firewall-*                                  = RAW Backup + Git History
10-Automation / 10-Automation-OPNsenseDocumentation  = Sanitizer + Validator + Parser/Normalizer
10-Automation / 10-Automation-AzureInfrastructureCollector
                                                       = Azure Read-only Collector
00-Platform / DocumentationEngine                     = finale Dokumenterzeugung
CUST-xxx / Documentation                              = freigegebene Kundendokumentation
20-IaC / AVD-Accelerator                              = AVD IaC Produkt
20-IaC / Vaultwarden                                  = Vaultwarden IaC Produkt
```

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

## v1.6 – lokaler Entwicklungsweg und zentraler Technikerweg

Das gleiche PowerShell-Bootstrap wird in zwei Laufzeitmodi unterstützt:

```text
LOCAL
→ Entwicklung / Debugging
→ vorhandener az-Login / Cache / gezielter interaktiver Login

PIPELINE
→ normaler Technikerweg
→ Azure DevOps Service Connection / WIF
→ keine interaktive Anmeldung
```

Die Erkennung erfolgt automatisch in `bootstrap/BSSE.AzureDevOps.Common.ps1`.

Bevorzugte Pipeline-Authentifizierung:

```text
AzureCLI@3
connectionType: azureDevOps
Service Connection: sc-platform-bootstrap-azdo
Microsoft Entra Workload Identity Federation
```

### Techniker-Pipeline

```text
/pipelines/customer-onboarding.yml
```

Diese Pipeline behandelt ausschließlich Kundenbasis und Dokumentationsfähigkeiten:

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

Ablauf:

```text
Validate
  ↓
Dry Run
  ↓
Manual Approval
  ↓
Apply
  ↓
Verify (erneuter Dry Run / Idempotenz)
```

## Noch nicht produktiv verifiziert

Code und YAML sind im Repository implementiert. Azure-DevOps-seitig müssen noch eingerichtet und tatsächlich getestet werden:

- `sc-platform-bootstrap-azdo`
- Microsoft Entra Workload Identity Federation
- minimale erforderliche Azure-DevOps-Berechtigungen
- Pipeline-Registrierung aus `/pipelines/customer-onboarding.yml`
- erster echter Dry Run / Apply / Verify
- kontrollierte Persistierung des generierten CustomerConfiguration-Scaffolds

Der separate zentrale Techniker-/Deployment-Weg für die IaC-Produkte AVD und Vaultwarden ist noch offen und wird in den jeweiligen IaC-Umsetzungsplänen umgesetzt.

Details: `docs/Techniker-Workflow.md` und `docs/Umsetzungsplan.md`.