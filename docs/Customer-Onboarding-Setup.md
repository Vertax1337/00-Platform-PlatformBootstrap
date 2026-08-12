# Customer-Onboarding – Self-Hosting-Erstinitialisierung

## Zweck

Der normale Techniker soll Kunden später ausschließlich zentral über Azure DevOps onboarden:

```text
00-Platform / Customer-Onboarding
```

Eine **komplett neue Plattform** besitzt diese Pipeline, ihre Service Connection und die dafür benötigte Dienstidentität naturgemäß noch nicht. Deshalb ist nur die Erstinitialisierung lokal.

Der lokale Einstieg bleibt:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Start-BSSECustomerOnboarding.ps1"
```

Dieses Frontend prüft **vor jeder Kundenabfrage** die Self-Hosting-Dependencies über:

```text
bootstrap/Initialize-BSSEPlatformDependencies.ps1
```

## Voraussetzungen, die der Bootstrap nicht selbst erzeugt

Die Automatisierung beginnt innerhalb einer bereits existierenden Azure-DevOps-Organisation.

Erforderlich sind daher vor dem allerersten Lauf:

- die Azure-DevOps-Organisation, z. B. `https://dev.azure.com/BSSE-CloudOps/`, existiert bereits,
- der lokale Erstinstallations-Administrator kann sich gegen die Organisation authentifizieren,
- der lokale Erstinstallations-Administrator besitzt die nötigen Microsoft-Entra-Rechte zum Erstellen einer App Registration / eines Service Principals,
- der lokale Erstinstallations-Administrator darf in Azure DevOps Projekte und die benötigten Plattformberechtigungen verwalten,
- Azure CLI, Azure-DevOps-CLI-Extension, PowerShell und Git sind lokal verfügbar beziehungsweise werden im Rahmen der bestehenden Bootstraplogik geprüft.

Der Bootstrap **eskaliert den ausführenden Administrator nicht selbst**. Fehlen diese Ausgangsrechte, bricht er mit einer eindeutigen Fehlermeldung ab.

## Erstinstallations-Ablauf

```text
Start-BSSECustomerOnboarding.ps1
        ↓
Dependency Dry Run
        ↓
Plattform vollständig?
   ├─ Ja → direkt Customer-Onboarding
   └─ Nein
        ↓
PLATFORM INITIALIZATION REQUIRED
        ↓
separate lokale Freigabe
        ↓
Initialize-BSSEPlatformDependencies.ps1 -Apply
        ↓
Dependency Verify / Dry Run
        ↓
erst danach Customer-Onboarding
```

Die Plattforminitialisierung ist damit bewusst von der späteren Kundenfreigabe getrennt.

## Automatisch verwaltete Dependencies

### 1. Core-Projekte und Repositories

Der Dependency-Bootstrap verwendet den bestehenden idempotenten Core-Bootstrap:

```text
bootstrap/New-BSSEAzureDevOpsCore.ps1
```

Damit werden fehlende Core-Projekte/-Repositories geplant beziehungsweise bei Freigabe erstellt.

### 2. `00-Platform/PlatformBootstrap` als Ausführungsquelle

Ist das Azure-Repo vollständig leer, darf es beim Erstaufbau aus dem lokalen **committed** Source-of-Truth initialisiert werden:

```text
lokaler PlatformBootstrap HEAD
        ↓
00-Platform / PlatformBootstrap / main
```

Sicherheitsregeln:

- lokale uncommitted Änderungen → `BLOCKED`,
- Azure-Repo leer → `PLAN` / bei Apply initialisieren,
- Azure-Repo `main` identisch zum lokalen committed HEAD → `EXISTS`,
- Azure-Repo nicht leer, aber ohne `main` → `BLOCKED`,
- Azure-`main` weicht vom lokalen committed HEAD ab → `BLOCKED`,
- niemals automatischer Force-Push.

### 3. Dedizierte Microsoft-Entra-Dienstidentität

Zielname:

```text
sp-bsse-platform-bootstrap-azdo
```

Wenn sie fehlt, erstellt der Bootstrap eine App Registration und den zugehörigen Service Principal **ohne Passwort/Client Secret**.

Der Bootstrap weist der Identität dabei keine Azure-RBAC-Rolle auf Subscription-/Resource-Ebene zu.

Existieren mehrere Objekte mit exakt demselben Namen oder widersprüchliche bestehende Objekte, wird nicht geraten oder ersetzt.

### 4. Azure-DevOps-Mitgliedschaft

Die Dienstidentität wird mit folgendem Zielzustand in Azure DevOps aufgenommen:

```text
Access Level: Basic
Project:      00-Platform
Group:        Readers
```

Damit erhält sie nicht pauschal administrative Rechte im Plattformprojekt.

### 5. Minimale Collection-Berechtigung

Die Identität wird ausdrücklich **nicht** Mitglied von:

```text
Project Collection Administrators
```

Stattdessen erhält sie gezielt:

```text
Create new projects = Allow
```

Der Bootstrap ermittelt Security Namespace und Permission Bit zur Laufzeit. Auch der zu verwendende Collection-ACL-Token wird nicht geraten, sondern aus den effektiven Rechten des angemeldeten Erstinstallations-Administrators abgeleitet.

Ein vorhandenes `Deny` wird nicht automatisch überschrieben.

### 6. Azure-DevOps-WIF-Service-Connection

Zielname:

```text
sc-platform-bootstrap-azdo
```

Zielauthentifizierung:

```text
Microsoft Entra Workload Identity Federation
```

Der Bootstrap verwendet für diesen neuen Azure-DevOps-Service-Connection-Typ **kein hartcodiertes undokumentiertes Schema**. Er fragt die in der Organisation verfügbaren Service-Endpoint-Type-Metadaten ab und akzeptiert nur einen eindeutigen `Azure DevOps`-Typ mit `WorkloadIdentityFederation`.

Unbekannte erforderliche Endpoint-Inputs führen zu Fail Closed.

### 7. Federated Credential

Nachdem Azure DevOps für die Service Connection `issuer` und `subject` bereitstellt, wird auf der Entra-App das Credential angelegt:

```text
fic-sc-platform-bootstrap-azdo
```

Bestehendes Credential:

- identisch → `EXISTS`,
- abweichender Issuer/Subject/Audience → `BLOCKED`,
- kein automatisches Ersetzen.

### 8. Customer-Onboarding-Pipeline

Die Pipeline wird aus:

```text
00-Platform / PlatformBootstrap
pipelines/customer-onboarding.yml
```

idempotent als:

```text
Customer-Onboarding
```

registriert. Der erste Run wird bei der Registrierung bewusst nicht ausgelöst.

Danach wird ausschließlich diese Pipeline für die Verwendung von:

```text
sc-platform-bootstrap-azdo
```

autorisiert. Es gibt keine pauschale Freigabe für alle Pipelines.

## Pipeline darf sich nicht selbst privilegieren

Folgendes ist ausdrücklich blockiert:

```powershell
Initialize-BSSEPlatformDependencies.ps1 -Apply
```

wenn der Aufruf aus Azure Pipelines erfolgt.

Die zentrale Pipeline **verwendet** die vorhandenen Dependencies, darf aber ihre eigene Identität, WIF-Verbindung oder organisationsweiten Berechtigungen nicht selbst erzeugen oder erweitern.

## Readiness prüfen

Nach der Erstinitialisierung kann ohne Kundenänderung geprüft werden:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Test-BSSECustomerOnboardingReadiness.ps1"
```

Der Readiness-Check verwendet den Dependency-Bootstrap ausschließlich ohne `-Apply`.

```text
kein PLAN / kein BLOCKED
→ Plattform-Dependencies bereit

PLAN
→ Dependency fehlt noch

BLOCKED / Exception
→ Drift, fehlende Rechte oder nicht sicher auflösbarer Zustand
```

## Architekturgrenze Dokumentation / IaC

Der Self-Hosting-Bootstrap ändert nichts an der bestehenden Trennung.

Customer-Onboarding behandelt ausschließlich:

```text
AzureDocumentation
OPNsenseDocumentation
CustomerConfiguration
Firewall-* RAW-Repositories
```

Nicht Bestandteil:

```text
AVD-Accelerator
Vaultwarden
```

Diese bleiben IaC-Produkte unter `20-IaC` mit eigenen Deployment-Identitäten und Deployment-Pipelines.

## Runtime-Verifikationsstatus

Die Self-Hosting-Logik ist im Repository implementiert. **Noch nicht durch einen echten Erstinstallationslauf verifiziert** sind insbesondere:

- die tatsächlich von `BSSE-CloudOps` gelieferten Endpoint-Type-Metadaten für die neue Azure-DevOps-WIF-Service-Connection,
- das reale Erstellen von `sp-bsse-platform-bootstrap-azdo`,
- das reale Service-Principal-Entitlement in Azure DevOps,
- die tatsächliche `Create new projects`-ACL-Zuweisung,
- die reale Erstellung von `sc-platform-bootstrap-azdo`,
- das reale federated credential,
- die Pipeline-spezifische Service-Connection-Autorisierung,
- der anschließende WIF-Pipeline-Run.

Diese Punkte dürfen erst nach dem vorgesehenen gemeinsamen Erstinstallations-/Runtime-Test als tatsächlich bestätigt gelten.
