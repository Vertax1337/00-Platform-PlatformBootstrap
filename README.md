# BSSE Azure DevOps Platform – Bootstrap v1.9

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

### Dokumentationsplattform

```text
AzureDocumentation
OPNsenseDocumentation
```

### IaC-Produkte

```text
20-IaC / AVD-Accelerator
20-IaC / Vaultwarden
```

AVD und Vaultwarden sind **keine** Customer-Onboarding-/Dokumentationsmodule. IaC verwendet einen separaten Deployment-Weg:

```text
Validate → Lint/Security → Plan/What-If → Approval → Deploy → Verify
```

## v1.9 – verwaltetes Project Branding

Azure-DevOps-Projekt-Avatare sind Bestandteil des Bootstrap-Sollzustands.

Versionierte Assets:

```text
assets/
└── project-icons/
    ├── 00-platform.png
    ├── 10-automation.png
    ├── 20-iac.png
    ├── 99-lab.png
    └── cust-generic.png
```

Mapping:

```text
00-Platform   → assets/project-icons/00-platform.png
10-Automation → assets/project-icons/10-automation.png
20-IaC        → assets/project-icons/20-iac.png
99-LAB        → assets/project-icons/99-lab.png
CUST-*        → assets/project-icons/cust-generic.png
```

Zentrale Implementierung:

```text
bootstrap/BSSE.AzureDevOps.Branding.ps1
```

`New-BSSEAzureDevOpsCore.ps1` und `New-BSSECustomerProject.ps1` verwenden dieselbe Funktion `Ensure-BSSEProjectAvatar`. Dadurch werden bestehende und neu angelegte verwaltete Projekte mit derselben Logik behandelt.

Für das Setzen des Avatars wird die offizielle Azure-DevOps-Core-API `Set Project Avatar` (`7.1-preview.1`) verwendet. Die API dokumentiert für Project Avatars keinen GET-Readback. Deshalb verwendet PlatformBootstrap zur idempotenten Zustandsverwaltung die Project Property:

```text
BSSE.PlatformBootstrap.ProjectAvatarSha256
```

Nur wenn dieser verwaltete SHA-256-Marker fehlt oder vom vorgesehenen Asset abweicht, plant/setzt der Bootstrap den Avatar erneut. Der Marker wird erst nach einem erfolgreichen Avatar-API-Aufruf geschrieben und anschließend wieder aus Azure DevOps gelesen und verifiziert.

Bekannte Grenze: Eine ausschließlich manuelle Avatar-Änderung außerhalb des Bootstraps ist bei unverändertem Hash-Marker mit der dokumentierten Project-Avatar-Core-API nicht zuverlässig erkennbar. Details, Berechtigungen und Fail-Closed-Verhalten:

```text
docs/Project-Branding.md
```

## v1.8 – Self-Hosting First Run

Eine neue Plattform besitzt zu Beginn noch keine zentrale Customer-Onboarding-Pipeline und keine dafür verwendbare WIF-Service-Connection. Deshalb ist nur die **Erstinitialisierung** lokal.

Lokaler Einstieg:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Start-BSSECustomerOnboarding.ps1"
```

Vor der Kundenmaske erfolgt automatisch:

```text
Dependency Dry Run
    ↓
Plattform vollständig?
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

Verwendeter Dependency-Baustein:

```text
bootstrap/Initialize-BSSEPlatformDependencies.ps1
```

## Automatisch verwaltete Plattform-Dependencies

```text
Core-Projekte/-Repositories
00-Platform/PlatformBootstrap Seed
sp-bsse-platform-bootstrap-azdo
Basic + 00-Platform/Readers
Create new projects = Allow
sc-platform-bootstrap-azdo (Workload Identity Federation)
fic-sc-platform-bootstrap-azdo
Customer-Onboarding Pipeline
Pipeline-spezifische Service-Connection-Autorisierung
```

### Sicherheitsgrenzen

- Azure-DevOps-Organisation selbst muss bereits existieren.
- Der lokale Erstinstallations-Administrator muss die erforderlichen Entra-/Azure-DevOps-Rechte bereits besitzen.
- Das Skript eskaliert den ausführenden Administrator nicht.
- `Initialize-BSSEPlatformDependencies.ps1 -Apply` ist aus Azure Pipelines blockiert.
- Die Plattformidentität wird nicht `Project Collection Administrator`.
- `Create new projects` wird gezielt vergeben.
- Die Service Connection wird nur für `Customer-Onboarding` autorisiert.
- Ein dirty lokaler PlatformBootstrap-Working-Tree blockiert den Erst-Seed.
- Abweichender Azure-`main` wird nicht überschrieben; kein Force-Push.
- Der Azure-DevOps-WIF-Service-Endpoint-Typ wird aus den Laufzeit-Metadaten ermittelt; unbekannte Pflichtfelder führen zu Fail Closed.

## Normaler Technikerweg nach Erstinitialisierung

Der normale Techniker braucht keinen lokalen Clone mehr:

```text
Azure DevOps
└── 00-Platform / Customer-Onboarding
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

Pipeline:

```text
Validate
  ↓
DryRun Customer Boundary + CustomerConfiguration
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

Beide Wege verwenden:

```text
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

```text
Datei fehlt      → PLAN / ADD
Datei identisch  → EXISTS
Datei abweichend → BLOCKED
```

Es gibt kein blindes Überschreiben bestehender Kundenkonfiguration.

## OPNsense RAW Git Backup

Ein Kunde kann 0..n Firewalls besitzen:

```text
CUST-4711-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
├── Firewall-Cannon-Deutschland-GmbH-HQ
└── Firewall-Cannon-Deutschland-GmbH-Branch01
```

`Firewall-*` ist RAW/CONFIDENTIAL und wird vollständig leer für `os-git-backup` erzeugt.

## Repositorynamen unter `10-Automation`

```text
10-Automation-AzureInfrastructureCollector
10-Automation-OPNsenseDocumentation
```

Aus dieser Entscheidung entsteht keine globale `<Projekt>-<Repository>`-Konvention für andere Projekte.

## Readiness prüfen

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Test-BSSECustomerOnboardingReadiness.ps1"
```

Der Check verändert keine Plattform- oder Kundenobjekte und verwendet die Self-Hosting-Dependencies nur im Dry-Run-/Verify-Modus.

## Verifikationsstatus

### Code-seitig implementiert

- Core-Bootstrap,
- Self-Hosting-Dependency-Bootstrap,
- lokales interaktives Frontend,
- zentrale Azure-DevOps-Pipeline,
- automatische Local-/Pipeline-Erkennung,
- secretless Entra-Identitäts-Sollzustand,
- Azure-DevOps-Entitlement und Least-Privilege-ACL-Sollzustand,
- dynamische WIF-Service-Endpoint-Type-Erkennung,
- federated-credential-Sollzustand,
- Pipeline-Registrierung und gezielte Endpoint-Autorisierung,
- Dry Run / Approval / Apply / Verify,
- persistente `CustomerConfiguration`,
- verwaltetes Project-Branding-Mapping und Avatar-Sollzustand,
- harte Trennung zu AVD/Vaultwarden.

### Noch nicht runtime-verifiziert

Bis zum ersten echten Plattform-/Branding-Lauf sind insbesondere reale Entra-/Azure-DevOps-Objekterstellung, Endpoint-Type-Metadaten, WIF-Service-Connection, ACL-Zuweisung, Project-Avatar-PUT, Project-Property-Marker und der anschließende Pipeline-Lauf **nicht als tatsächlich verifiziert zu betrachten**.

Details:

```text
docs/Customer-Onboarding-Setup.md
docs/Techniker-Workflow.md
docs/Project-Branding.md
docs/Umsetzungsplan.md
```