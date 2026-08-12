# Customer-Onboarding – einmaliges Azure-DevOps-Setup

## Zweck

Diese Anleitung beschreibt die einmalige Plattformkonfiguration für den zentralen Technikerweg:

```text
00-Platform / Customer-Onboarding
```

Der normale Techniker benötigt danach keinen lokalen Clone des `PlatformBootstrap`-Repositories.

Die Pipeline verwendet:

```text
AzureCLI@3
connectionType: azureDevOps
Service Connection: sc-platform-bootstrap-azdo
Microsoft Entra Workload Identity Federation
```

## Architekturgrenze

`Customer-Onboarding` behandelt ausschließlich:

- Kundenprojekt / Kunden-Repositories,
- `AzureDocumentation`,
- `OPNsenseDocumentation`,
- optionale `Firewall-*` RAW-Repositories,
- persistente Initialisierung von `CustomerConfiguration`.

AVD und Vaultwarden sind IaC-Produkte unter `20-IaC` und ausdrücklich nicht Bestandteil dieses Workflows.

## 1. Microsoft-Entra-Identität

Für `sc-platform-bootstrap-azdo` wird eine dedizierte Microsoft-Entra-Dienstidentität verwendet.

Empfohlener Name:

```text
sp-bsse-platform-bootstrap-azdo
```

Keine persönliche Benutzeridentität und kein langlebiger PAT/Client-Secret als produktiver Standard.

## 2. Identität in Azure DevOps aufnehmen

In der Azure-DevOps-Organisation:

```text
Organization Settings
└── Users
```

Die Entra-Dienstidentität hinzufügen.

Zugriffsebene:

```text
Basic
```

Sie muss außerdem Zugriff auf `00-Platform` erhalten; `Readers` reicht für die reine Projektzuordnung. Die eigentliche Pipelineauthentifizierung erfolgt über die Service Connection.

## 3. Minimale organisationsweite Bootstrap-Berechtigung

Die Identität wird **nicht** Mitglied von `Project Collection Administrators`.

Stattdessen wird auf Collection-/Organization-Ebene ausschließlich folgende Berechtigung auf `Allow` gesetzt:

```text
Create new projects
```

Das ist die benötigte organisationsweite Sonderberechtigung für den Kundenprojekt-Bootstrap.

Der Ersteller eines neuen Azure-DevOps-Projekts wird automatisch Mitglied der `Project Administrators`-Gruppe dieses neu erstellten Projekts. Dadurch kann die Bootstrap-Identität anschließend innerhalb genau dieses neuen `CUST-*`-Projekts die erforderlichen Repository-Operationen durchführen.

## 4. Azure-DevOps-Service-Connection erstellen

In:

```text
00-Platform
└── Project Settings
    └── Service connections
```

Neue Service Connection erstellen:

```text
Type: Azure DevOps
Identity: sp-bsse-platform-bootstrap-azdo
Name: sc-platform-bootstrap-azdo
Authentication: Microsoft Entra Workload Identity Federation
```

Die Service Connection nicht organisationsweit für beliebige Pipelines freigeben. Nur die vorgesehene `Customer-Onboarding`-Pipeline autorisieren.

## 5. PlatformBootstrap nach Azure Repos synchronisieren

Die Pipeline wird aus folgendem Azure-Repo registriert:

```text
00-Platform / PlatformBootstrap
```

Dort muss mindestens der aktuelle Stand enthalten sein, insbesondere:

```text
bootstrap/New-BSSECustomerProject.ps1
bootstrap/Sync-BSSECustomerConfiguration.ps1
bootstrap/BSSE.AzureDevOps.Common.ps1
pipelines/customer-onboarding.yml
```

Die GitHub-Engineering-Quelle und der Azure-DevOps-Ausführungsstand dürfen vor dem Test nicht auseinanderlaufen.

## 6. Pipeline idempotent registrieren

Dry Run:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Register-BSSECustomerOnboardingPipeline.ps1"
```

Erwartung bei vorhandener Service Connection und noch fehlender Pipeline:

```text
[OK] Repository 00-Platform/PlatformBootstrap vorhanden.
[OK] Service Connection sc-platform-bootstrap-azdo vorhanden.
[PLAN] Register pipeline Customer-Onboarding ...
```

Apply:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Register-BSSECustomerOnboardingPipeline.ps1" `
  -Apply
```

Der erste Pipeline-Lauf wird bewusst nicht automatisch gestartet.

Wiederholter Lauf:

```text
[EXISTS] Pipeline Customer-Onboarding (no change)
```

## 7. CustomerConfiguration-Persistenz

Beide Ausführungswege verwenden:

```text
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

Verhalten:

- fehlende Bootstrap-Zieldateien → `[PLAN]` / bei Apply hinzufügen,
- identische vorhandene Dateien → `[EXISTS]`,
- abweichende vorhandene Bootstrap-Zieldateien → `[BLOCKED]`,
- kein automatisches Überschreiben vorhandener abweichender Kundenkonfiguration,
- Git-Push ausschließlich nach erfolgreichem Vergleich,
- OAuth-/Entra-Token wird nicht in Remote-URLs geschrieben.

Damit ist `CustomerConfiguration` kein flüchtiges Agent-Artefakt mehr, sondern Bestandteil des kontrollierten Git-Zielzustands.

## 8. Fertiger Technikerablauf

```text
Run pipeline
    ↓
Parameter eingeben
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
Manual Approval
    ↓
Apply Customer Boundary
    ↓
Apply CustomerConfiguration
    ↓
Post-Apply Dry Run beider Bereiche
    ↓
Idempotenz verifizieren
```

## 9. Noch nicht als verifiziert markieren

Die Implementierung im Repository darf erst nach einem realen Test als runtime-verifiziert gelten.

Vor diesem Test sind folgende Aussagen ausschließlich code-/konfigurationsseitig vorbereitet:

- WIF-Authentifizierung funktioniert mit der realen Service Connection,
- die Identität besitzt exakt die nötigen Berechtigungen,
- Projekt-/Repository-Provisionierung funktioniert aus AzureCLI@3,
- Git-Push in `CustomerConfiguration` funktioniert mit dem Entra-Token,
- Approval-/Output-Variable-Bedingung verhält sich im realen Pipeline-Run wie vorgesehen,
- Post-Apply-Verify ist tatsächlich idempotent.
