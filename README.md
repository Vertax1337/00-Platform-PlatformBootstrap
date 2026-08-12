# BSSE Azure DevOps Platform – Bootstrap v1.6

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
├── 99-LAB
│
└── CUST-<interne Kunden-/Debitorennummer>-<Kundenname>
    ├── CustomerConfiguration
    ├── Documentation
    └── Firewall-<Kundenname>-<Firewall/Standort>   # 0..n
```

Die interne Kunden-/Debitorennummer ist die stabile technische Kunden-ID.

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

Die `Firewall-*` Repositories sind absichtlich **keine normalen Entwicklungs-Repositories**, sondern `RAW / CONFIDENTIAL` Upstreams für OPNsense `os-git-backup`.

Der Bootstrap erstellt diese Repositories vollständig leer:

- kein README
- kein `.gitignore`
- kein `azure-pipelines.yml`
- kein Initial-Commit
- kein Scaffold
- keine Sanitized Config

Dadurch kann OPNsense `os-git-backup` das Remote-Repository selbst übernehmen.

## Neues Kundenprojekt mit Firewalls

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

## Firewall später hinzufügen

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Add-BSSECustomerFirewall.ps1" `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "4711" `
  -Firewalls "Branch02"
```

## Verantwortlichkeiten

```text
CUST-xxx / Firewall-*                         = RAW Backup + Git History
10-Automation / 10-Automation-OPNsenseDocumentation = Sanitizer + Validator + Parser/Normalizer
10-Automation / 10-Automation-AzureInfrastructureCollector = Azure Read-only Collector
00-Platform / DocumentationEngine             = finale Dokumenterzeugung
CUST-xxx / Documentation                      = freigegebene Kundendokumentation
```

## Sicherheitsgrenze

```text
Firewall-* RAW repo
      ↓
Sanitize
      ↓
Validate
      ↓
Secret Check
      ↓
------------- SECURITY BOUNDARY -------------
      ↓
sanitized / normalized data
      ↓
DocumentationEngine / KI
```

RAW-Konfigurationen dürfen niemals in `10-Automation`, `Documentation`, normale Pipeline-Artefakte oder öffentliche/allgemeine Entwicklungs-Repositories kopiert werden.

## Robuste Listenparameter

Der Bootstrap akzeptiert Komma-/Semikolon-Listen, auch bei `pwsh.exe -File`:

```powershell
-Modules AzureDocumentation,OPNsenseDocumentation
-Firewalls "HQ,Branch01,Branch02"
```

## PlatformBootstrap Repository

```text
00-Platform
├── PlatformBootstrap
├── PipelineTemplates
├── DocumentationEngine
├── SecurityValidation
└── SharedModules
```

`PlatformBootstrap` ist die Source of Truth für Aufbau und Weiterentwicklung der Azure-DevOps-Plattform. Bei bestehenden Umgebungen werden vorhandene Repositories und Inhalte nicht überschrieben.

## Repositorynamen unter `10-Automation`

Für die aktuell bestehenden Automations-Repositories gilt:

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

Die fachlichen Komponentenbezeichnungen bleiben `AzureInfrastructureCollector` bzw. `OPNsenseDocumentation` und sind von den Repositorynamen getrennt.

Für Repositories anderer Projekte ist damit **keine globale Umbenennung auf `<Projekt>-<Repository>` beschlossen**.

### Bestandsschutz / Idempotenz

Sind die Soll-Repositories vorhanden, zeigt der Dry Run:

```text
[EXISTS] Repo 10-Automation-AzureInfrastructureCollector (no change)
[EXISTS] Repo 10-Automation-OPNsenseDocumentation (no change)
```

Existiert ausschließlich ein Legacy-Repository `AzureInfrastructureCollector`, `OPNsenseDocumentation` oder `OpenSenseDocumentation`, wird **kein zweites Repository automatisch erzeugt**. Der Bootstrap blockiert die automatische Änderung und verlangt eine bewusste manuelle Prüfung/Umbenennung.

## v1.6 – lokaler Entwicklungsweg und zentraler Technikerweg

Das gleiche PowerShell-Bootstrap wird jetzt in zwei Laufzeitmodi unterstützt:

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

Als Kompatibilitätsfallback kann ein explizit gemapptes `SYSTEM_ACCESSTOKEN` nicht-interaktiv an die Azure-DevOps-CLI gebunden werden. In einer Pipeline werden niemals `az login` oder Browser-Fallbacks gestartet.

### Techniker-Pipeline

```text
/pipelines/customer-onboarding.yml
```

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

Der Post-Apply-Verify schlägt fehl, wenn weiterhin `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` erkannt wird.

### Noch nicht produktiv verifiziert

Code und YAML sind im Repository implementiert. Azure-DevOps-seitig müssen noch eingerichtet und tatsächlich getestet werden:

- `sc-platform-bootstrap-azdo`
- Microsoft Entra Workload Identity Federation
- minimale erforderliche Azure-DevOps-Berechtigungen
- Pipeline-Registrierung aus `/pipelines/customer-onboarding.yml`
- erster echter Dry Run / Apply / Verify

Details: `docs/Techniker-Workflow.md` und `docs/Umsetzungsplan.md`.
