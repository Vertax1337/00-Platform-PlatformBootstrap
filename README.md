# BSSE Azure DevOps Platform – Bootstrap v1.5

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
├── 10-Automation
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

## Neu in v1.4: OPNsense RAW Git Backup

Ein Kunde kann jetzt **0 bis n OPNsense-Firewalls** besitzen.

Beispiel:

```text
CUST-4711-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
├── Firewall-Cannon-Deutschland-GmbH-HQ
└── Firewall-Cannon-Deutschland-GmbH-Branch01
```

Die `Firewall-*` Repositories sind absichtlich **keine normalen Entwicklungs-Repositories**.

Sie sind:

```text
RAW / CONFIDENTIAL
OPNsense os-git-backup upstream
```

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

Apply:

```powershell
# denselben Aufruf mit:
-Apply
```

## Firewall später zu bestehendem Kunden hinzufügen

Dry Run:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Add-BSSECustomerFirewall.ps1" `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "4711" `
  -Firewalls "Branch02"
```

Apply:

```powershell
# denselben Aufruf mit:
-Apply
```

## Verantwortlichkeiten

```text
CUST-xxx/Firewall-*
    = RAW Backup + Git History

10-Automation/OPNsenseDocumentation
    = Sanitizer + Validator + Parser/Normalizer

00-Platform/DocumentationEngine
    = finale Dokumenterzeugung

CUST-xxx/Documentation
    = freigegebene Kundendokumentation
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

RAW-Konfigurationen dürfen niemals in:

- `10-Automation`
- `Documentation`
- normale Pipeline-Artefakte
- öffentliche oder allgemeine Entwicklungs-Repositories

kopiert werden.


## Neu in v1.4.1 – robuste Listenparameter

Beim Aufruf über `pwsh.exe -File` werden Komma-Listen je nach Aufrufkontext als ein einzelner String übergeben.
Der Bootstrap normalisiert deshalb jetzt automatisch:

```powershell
-Modules AzureDocumentation,OPNsenseDocumentation
```

genauso wie:

```powershell
-Modules "AzureDocumentation,OPNsenseDocumentation"
```

Auch Semikolon-getrennte Werte werden akzeptiert.

Für Firewalls gilt dasselbe:

```powershell
-Firewalls "HQ,Branch01,Branch02"
```

oder einzelne Array-Werte bei direktem Aufruf innerhalb einer PowerShell-Sitzung.


## Neu in v1.5 – eigenes `PlatformBootstrap` Repository

Das Bootstrap selbst ist jetzt ein eigener Plattformbaustein:

```text
00-Platform
├── PlatformBootstrap
├── PipelineTemplates
├── DocumentationEngine
├── SecurityValidation
└── SharedModules
```

Verantwortlichkeiten:

```text
PlatformBootstrap
= Aufbau und Weiterentwicklung der Azure-DevOps-Plattform

PipelineTemplates
= zentrale YAML-Pipeline-Standards

DocumentationEngine
= gemeinsame Dokumenterzeugung

SecurityValidation
= zentrale Security-/Sanitization-Prüfungen

SharedModules
= gemeinsam verwendete technische Module
```

### Verhalten bei einer bereits bestehenden Umgebung

Wenn `00-Platform` schon mit `PipelineTemplates`, `DocumentationEngine`,
`SecurityValidation` und `SharedModules` existiert, wird **nichts umbenannt**.

Ein erneuter Dry Run zeigt lediglich:

```text
[EXISTS] Project 00-Platform
  [PLAN] Create repo PlatformBootstrap
  [EXISTS] Repo PipelineTemplates
  [EXISTS] Repo DocumentationEngine
  [EXISTS] Repo SecurityValidation
  [EXISTS] Repo SharedModules
```

Mit `-Apply` wird ausschließlich das fehlende Repo `PlatformBootstrap` ergänzt.
Bestehender Inhalt wird nicht verändert.

### Inhalt des `PlatformBootstrap` Repositories

Der Inhalt dieses Pakets gehört anschließend in dieses Repository:

```text
PlatformBootstrap/
├── bootstrap/
│   ├── BSSE.AzureDevOps.Common.ps1
│   ├── New-BSSEAzureDevOpsCore.ps1
│   ├── New-BSSECustomerProject.ps1
│   ├── Add-BSSECustomerFirewall.ps1
│   └── Test-BSSEAzureDevOpsPrerequisites.ps1
├── config/
│   └── organizations.json
├── docs/
│   ├── Umsetzungsplan.md
│   ├── Security-Modell.md
│   ├── Kunden-Onboarding.md
│   └── Namenskonventionen.md
├── README.md
├── CHANGELOG.md
└── .gitignore
```
