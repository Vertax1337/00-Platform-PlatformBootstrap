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

Beim ersten realen Lauf am 13.08.2026 wurde unmittelbar nach der Entra-Erstellung einmalig folgendes Azure-DevOps-Ergebnis beobachtet:

```text
VS403283: Could not add user '<service-principal-object-id>' at this time.
```

Ein unveränderter Wiederholungslauf nach kurzer Wartezeit konnte dasselbe Service-Principal-Entitlement erfolgreich anlegen und anschließend als `Basic + 00-Platform/Readers` verifizieren. Für genau diesen real bestätigten Entra→Azure-DevOps-Materialisierungsfall verwendet der Bootstrap deshalb einen **begrenzten Retry**. Andere Entitlement-Fehler werden nicht verschluckt oder pauschal wiederholt.

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

Die Azure-DevOps-CLI liefert `az devops security permission list --output json` als ACL-Struktur mit `acesDictionary`. Die effektiven Werte liegen im zugehörigen Access Control Entry unter:

```text
acesDictionary
└── <identity-descriptor>
    └── extendedInfo
        ├── effectiveAllow
        └── effectiveDeny
```

Der Bootstrap normalisiert dieses dokumentierte Format auf einen internen Berechtigungszustand und unterstützt zusätzlich bereits flach ausgegebene CLI-Werte. Mehrdeutige ACE-Zuordnungen oder unbekannte Ausgabeformate führen zu **Fail Closed**. Ein vorhandenes effektives `Deny` wird nicht automatisch überschrieben.

Der reale Dry Run am 13.08.2026 hat die korrigierte ACL-Normalisierung erfolgreich durchlaufen und den fehlenden Zustand als `PLAN` erkannt. Der anschließende reale Apply hat die Collection-Berechtigung danach tatsächlich gesetzt und direkt aus Azure DevOps wieder verifiziert:

```text
[GRANT] Collection permission: Create new projects = Allow
[OK] Create new projects für sp-bsse-platform-bootstrap-azdo verifiziert.
```

Ein weiterer Apply erkennt denselben Zustand inzwischen idempotent als:

```text
[EXISTS] Collection permission: Create new projects = Allow
```

Damit sind die **lesende ACL-Ermittlung, die mutierende Vergabe, die Post-Write-Verifikation und die Idempotenz von `Create new projects = Allow` runtime-verifiziert**.

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

Unbekannte **explizit als erforderlich markierte** Endpoint-Inputs führen zu Fail Closed.

Der reale Dry Run am 13.08.2026 konnte die von `BSSE-CloudOps` gelieferten Endpoint-Type-Metadaten ohne `BLOCKED`/Exception auswerten und eindeutig folgenden Plan erzeugen:

```text
[PLAN] Create Azure DevOps WIF Service Connection sc-platform-bootstrap-azdo
[PLAN] Create federated credential after Service Connection yields issuer/subject
```

Der erste reale Apply auf diesem Pfad erreichte `New-BSSEServiceEndpointConfiguration`, brach dort jedoch vor der Service-Connection-Erstellung an einer StrictMode-Annahme ab:

```text
The property 'isRequired' cannot be found on this object.
```

Die offizielle Azure-DevOps-REST-Struktur erlaubt `InputDescriptor.validation`, ohne dass `isRequired` zwingend enthalten sein muss. Der Bootstrap prüft daher nun zuerst, ob `validation` und die Property `isRequired` tatsächlich vorhanden sind. Nur ein explizites `isRequired: true` wird als Pflichtfeld behandelt. Dadurch bleiben unbekannte Pflichtinputs weiterhin Fail Closed, während optionale Metadaten unter StrictMode nicht mehr fehlschlagen.

Der darauf folgende reale Apply erreichte anschließend erstmals den tatsächlichen CLI-Create-Aufruf:

```text
[CREATE] Service Connection sc-platform-bootstrap-azdo
```

Azure DevOps lehnte die Konfiguration dabei mit folgender konkreter Validierung ab:

```text
Following fields in the service connection are not expected: creationMode.
Only fields that are defined in the service connection's contribution type as inputs can be specified.
```

Damit ist runtime-verifiziert, dass der reale `Azure DevOps`-/WIF-Endpoint-Typ in `BSSE-CloudOps` **kein** allgemeines `creationMode`-Input definiert. Die bisherige Konfiguration setzte `data.creationMode = Manual` trotzdem pauschal und verletzte damit gerade das metadata-driven Zielmodell.

Korrigiert gilt jetzt:

```text
ServiceEndpoint.data
→ startet leer
→ erhält ausschließlich Inputs aus EndpointType.inputDescriptors

Authorization.parameters
→ wird anhand des ausgewählten WIF-Schemas befüllt

creationMode
→ wird nur gesetzt, wenn Azure DevOps selbst einen Descriptor mit id=creationMode liefert

unbekannter explizit erforderlicher Descriptor
→ BLOCKED / Fail Closed
```

Damit wird kein typspezifisches `data`-Feld mehr unabhängig von den real gelieferten Endpoint-Metadaten erfunden. Die reale Erstellung von `sc-platform-bootstrap-azdo` und die daraus gelieferten konkreten `issuer`-/`subject`-Werte bleiben bis zum nächsten Apply offen.

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

### Bereits real bestätigt

Die bisherigen Erstinitialisierungs-/Apply-/Dry-Run-Läufe in `BSSE-CloudOps` haben folgende Punkte bestätigt:

- Azure CLI und Azure-DevOps-CLI-Erweiterung funktionieren im lokalen Bootstrap-Kontext,
- Organisationsprofil, Ziel-Tenant und Azure-DevOps-Zugriff werden korrekt erkannt,
- Core-Projekte und erwartete Core-Repositories werden idempotent erkannt,
- `00-Platform`, `10-Automation`, `20-IaC` und `99-LAB` besitzen die verwalteten Project Avatars und die SHA-256-Marker wurden erfolgreich geschrieben/gelesen,
- ein Folge-Apply erkennt diese vier Branding-Zustände als `EXISTS`,
- `00-Platform/PlatformBootstrap main` wird gegen den lokalen committed HEAD verifiziert,
- `sp-bsse-platform-bootstrap-azdo` wurde real als passwordless Entra App/Service Principal erzeugt,
- der erste unmittelbare Azure-DevOps-Entitlement-Versuch lieferte `VS403283`,
- ein späterer unveränderter Wiederholungslauf konnte das Entitlement real erzeugen,
- `Basic + 00-Platform/Readers` wurde anschließend aus Azure DevOps gelesen und als `EXISTS` bestätigt,
- die korrigierte Collection-ACL-Normalisierung wurde gegen die reale `BSSE-CloudOps`-Ausgabe erfolgreich ausgeführt,
- `Create new projects = Allow` wurde real vergeben, unmittelbar danach erfolgreich verifiziert und in einem späteren Apply als `EXISTS` wiedererkannt,
- die realen Azure-DevOps-Service-Endpoint-Type-Metadaten konnten für `Azure DevOps` + `WorkloadIdentityFederation` eindeutig ausgewertet werden,
- der vollständige vorherige Dependency-Dry-Run endete erfolgreich mit `[OK] Platform dependency dry run / verification completed.`,
- der nachfolgende Apply erreichte die tatsächliche WIF-Service-Endpoint-Konfiguration,
- der nächste Apply erreichte den realen Service-Connection-Create-Aufruf und bestätigte, dass `creationMode` im aktuellen Endpoint-Typ kein erlaubtes Input ist.

### Code-seitig korrigiert / implementiert

```text
az devops security permission list
        ↓
ACL.token
ACL.acesDictionary
        ↓
zugehörigen ACE eindeutig auflösen
        ↓
extendedInfo.effectiveAllow / effectiveDeny
        ↓
normalisierter interner Permission-State
```

Für Endpoint-Type-Metadaten gilt nun zusätzlich:

```text
InputDescriptor.validation fehlt
→ optional / kein Required-Zugriff

validation vorhanden, isRequired fehlt
→ nicht als Pflichtfeld behandeln

validation.isRequired == true
→ unbekannter Input bleibt BLOCKED / Fail Closed

EndpointType.inputDescriptors
→ nur diese Werte dürfen in ServiceEndpoint.data aufgenommen werden

creationMode
→ kein pauschales Default-Feld mehr
→ nur noch bei tatsächlich geliefertem Descriptor
```

Zusätzlich ist für den real beobachteten transienten `VS403283`-Materialisierungsfall ein begrenzter Retry implementiert. Die Retry-Implementierung selbst kann erst bei einem zukünftigen frischen Erstlauf innerhalb desselben Prozesses vollständig runtime-verifiziert werden.

### Noch nicht runtime-verifiziert

- erfolgreicher Service-Connection-Create nach Entfernung des pauschalen `creationMode`,
- reale Erstellung von `sc-platform-bootstrap-azdo`,
- die nach Erstellung real gelieferten WIF-`issuer`-/`subject`-Werte,
- reales federated credential `fic-sc-platform-bootstrap-azdo`,
- Pipeline-spezifische Service-Connection-Autorisierung,
- anschließender WIF-Pipeline-Run,
- vollständiger abschließender Dependency-Dry-Run ohne `PLAN`/`BLOCKED` nach dem Apply,
- Retry-Implementierung für `VS403283` innerhalb eines einzelnen frischen Erstlaufs.

Diese Punkte dürfen erst nach den vorgesehenen weiteren Runtime-Tests als tatsächlich bestätigt gelten.
