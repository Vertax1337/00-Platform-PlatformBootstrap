# BSSE Azure DevOps Platform – Bootstrap v1.9 Candidate

> **Status:** `main` ist Arbeitsbranch und Source of Truth. Die Plattform- und Customer-Onboarding-Bausteine sind code-seitig implementiert und werden aktuell im realen BSSE-CloudOps-Erstinitialisierungslauf verifiziert. Eine Phase gilt erst als abgeschlossen, wenn Fachdokumentation und `docs/Umsetzungsplan.md` denselben bestätigten Status enthalten.

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
├── 30-IDD
│   └── IntuneDefaultDeployment
│
├── 99-LAB
│   ├── LabConfiguration
│   └── LabDocumentation
│
└── CUST-<interne Kunden-/Debitorennummer>-<Kundenname>
    ├── CustomerConfiguration
    ├── Documentation
    └── Firewall-<Kundenname>-<Firewall/Standort>   # 0..n
```

Die interne Kunden-/Debitorennummer ist die stabile technische Kunden-ID.

## Verbindliche Architekturgrenzen

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

### Intune Default Deployment / Configuration Lifecycle

```text
30-IDD / IntuneDefaultDeployment
```

`30-IDD` ist der eigene fachliche Core-Projektbereich für Intune Default Deployment und den Intune-Konfigurationslebenszyklus. IntuneCD und IntuneCD Monitor werden deshalb nicht als reine `10-Automation`-Collector eingeordnet. Die konkrete IntuneCD-/Monitor-Repository-, Runtime-, Identity- und Customer-Integration ist noch offen und wird in `docs/Intune-Default-Deployment.md` geführt.

### PlatformBootstrap vs. DocumentationEngine

`PlatformBootstrap` provisioniert die `CUST-*`-Boundary und die für Customer-/Infrastruktur-Onboarding benötigten technischen Voraussetzungen.

Die finale Knowledge-Base-/Publishing-Architektur wird dagegen im Unterprojekt:

```text
00-Platform / DocumentationEngine
```

festgelegt und ist keine Bootstrap-Verantwortlichkeit.

---

# Erstinitialisierung – Vorgehen für Techniker

Eine komplett neue Plattform besitzt zu Beginn noch keine nutzbare `Customer-Onboarding`-Pipeline und keine dafür verwendbare WIF-Service-Connection. **Nur diese Erstinitialisierung erfolgt lokal und bewusst privilegiert.**

Nach erfolgreicher Erstinitialisierung läuft das normale Customer-Onboarding zentral über Azure DevOps; ein lokaler Clone ist dafür nicht mehr erforderlich.

## 1. Voraussetzungen

Vor dem ersten Lauf müssen bereits vorhanden sein:

- Azure-DevOps-Organisation, z. B. `https://dev.azure.com/BSSE-CloudOps/`,
- lokaler Clone von `PlatformBootstrap` auf `main`,
- sauberer, vollständig commiteter Working Tree,
- Azure CLI,
- Azure-DevOps-CLI-Erweiterung,
- PowerShell 7 (`pwsh`),
- Git,
- ein lokaler Erstinstallations-Administrator mit den unten beschriebenen Entra-/Azure-DevOps-Rechten.

Der Bootstrap **eskaliert den ausführenden Administrator nicht selbst**.

## 2. Benötigte Berechtigungen für die Erstinitialisierung

### Microsoft Entra ID

Der ausführende Erstinstallations-Administrator muss eine App Registration und den zugehörigen Service Principal erstellen dürfen.

Im realen BSSE-Erstinitialisierungslauf wurde dafür erfolgreich folgende per PIM aktivierte Rolle verwendet:

```text
Application Administrator
```

Die Rolle kann nur für die Dauer der Erstinitialisierung aktiviert und anschließend wieder deaktiviert bzw. auslaufen gelassen werden.

Entscheidend ist technisch, dass der Benutzer die benötigte App Registration / den Service Principal erzeugen darf. Der Bootstrap legt keine permanente privilegierte Benutzerrolle an und weist der erzeugten Plattformidentität keine Azure-RBAC-Rolle auf Subscription-/Resource-Ebene zu.

Zielidentität:

```text
sp-bsse-platform-bootstrap-azdo
```

### Azure DevOps

Der ausführende Erstinstallations-Administrator muss in der Zielorganisation ausreichend berechtigt sein, um die vom Bootstrap verwalteten Plattform-Dependencies herzustellen beziehungsweise zu vergeben. Dazu gehören insbesondere:

- Projekte und Repositories lesen/verwalten, soweit für den Core-Bootstrap erforderlich,
- den neuen Entra Service Principal als Azure-DevOps-Identität aufnehmen,
- `Basic + 00-Platform/Readers` für die Plattformidentität herstellen,
- Collection-Berechtigungen lesen und `Create new projects = Allow` gezielt vergeben,
- Service Connections im Projekt `00-Platform` erstellen/verwalten,
- die `Customer-Onboarding`-Pipeline registrieren/verwalten,
- die Service Connection gezielt für diese Pipeline autorisieren.

Der Bootstrap verlangt **keine dauerhafte Mitgliedschaft der Plattformidentität** in:

```text
Project Collection Administrators
```

Zielzustand der Plattformidentität:

```text
Azure DevOps Access Level: Basic
Projekt:                  00-Platform
Projektrolle:             Readers
Collection Permission:    Create new projects = Allow
```

Der reale BSSE-Erstinitialisierungslauf hat `Create new projects = Allow` erfolgreich vergeben, unmittelbar danach wieder verifiziert und in einem späteren Apply idempotent als `EXISTS` wiedererkannt. Unbekannte oder mehrdeutige ACL-Zustände führen weiterhin bewusst zu `BLOCKED` statt zu geratenen Berechtigungsänderungen.

## 3. Vor dem Lauf: lokalen Source of Truth prüfen

Der Bootstrap akzeptiert für die Erstinitialisierung ausschließlich einen sauberen, commiteten Source of Truth.

```powershell
git status
git log -1 --oneline
```

Es dürfen keine uncommitteten Änderungen vorhanden sein.

Für die Ausführungsquelle gilt:

```text
Azure PlatformBootstrap leer
→ PLAN / Seed aus lokalem committed HEAD

Azure main == lokaler committed HEAD
→ EXISTS

lokaler Working Tree dirty
→ BLOCKED

Azure main != lokaler committed HEAD
→ BLOCKED

nicht-leeres Azure Repo ohne main
→ BLOCKED
```

Es gibt **keinen automatischen Force-Push**.

## 4. Entra-/Azure-Session vorbereiten

Wenn eine Entra-Rolle erst per PIM aktiviert wurde, sollte die Azure-CLI-Session anschließend erneuert werden:

```powershell
az logout
az login --tenant f9acedfe-a77a-4831-b79c-f010afa6b889
```

Anschließend den aktiven Kontext prüfen:

```powershell
az account show --query "{user:user.name, tenantId:tenantId, subscription:name}" -o table
```

Für `BSSE-CloudOps` muss der erwartete Plattform-Tenant aktiv sein:

```text
f9acedfe-a77a-4831-b79c-f010afa6b889
```

## 5. Immer zuerst: Dependency Dry Run

Vor jeder mutierenden Erstinitialisierung zuerst **ohne `-Apply`** ausführen:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Initialize-BSSEPlatformDependencies.ps1"
```

Der Dry Run darf keine Plattformobjekte verändern.

Ausgaben:

```text
[EXISTS]  → Sollzustand bereits vorhanden
[PLAN]    → Änderung wäre erforderlich
[BLOCKED] → sicherer automatischer Fortgang nicht möglich
```

Bei `[BLOCKED]` oder Exception **nicht blind mit `-Apply` fortfahren**. Ursache zuerst prüfen.

## 6. Geplante Erstinitialisierung prüfen

Der Dependency-Bootstrap verwaltet folgende Kette:

```text
Core-Projekte/-Repositories inkl. jeweils freigegebenem Project Branding
        ↓
00-Platform/PlatformBootstrap Ausführungsquelle
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
pipeline-spezifische Service-Connection-Autorisierung
```

Die geplanten Änderungen müssen vor dem Apply geprüft werden.

## 7. Erst nach Prüfung: Apply

Nach geprüftem Dry Run und bewusster Freigabe:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Initialize-BSSEPlatformDependencies.ps1" `
  -Apply
```

`-Apply` ist absichtlich nur für die lokale, privilegierte Erstinitialisierung vorgesehen und aus Azure Pipelines blockiert.

Wichtig:

- keine App Registration manuell parallel anlegen,
- keine alternative Service Connection manuell erzeugen,
- keine vorhandenen widersprüchlichen Objekte überschreiben,
- bei `BLOCKED`/Exception den Lauf stoppen und Ursache analysieren,
- bereits erfolgreich angelegte Objekte werden beim nächsten Lauf idempotent wiedererkannt.

## 8. Nach Apply: Verify / Dry Run

Nach einem erfolgreichen Apply erneut **ohne `-Apply`** ausführen:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Initialize-BSSEPlatformDependencies.ps1"
```

Der gewünschte Endzustand ist:

```text
kein verbleibendes PLAN
kein BLOCKED
keine Exception
verwaltete Dependencies → EXISTS / verifiziert
```

Danach kann zusätzlich der Readiness-Check verwendet werden:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Test-BSSECustomerOnboardingReadiness.ps1"
```

```text
kein PLAN / kein BLOCKED → READY
PLAN                    → Dependency fehlt
BLOCKED / Fehler         → NOT READY
```

## 9. Was nach der Erstinitialisierung anders ist

Nach erfolgreichem Self-Hosting-Bootstrap benötigt der normale Techniker keinen lokalen Clone mehr.

Der produktive Technikerweg lautet dann:

```text
Azure DevOps
→ 00-Platform
→ Customer-Onboarding
→ Run pipeline
```

Die Plattformidentität und WIF-Service-Connection übernehmen die nachgelagerten Azure-DevOps-Aktionen entsprechend des definierten Least-Privilege-Modells.

---

## Verwaltetes Project Branding

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
30-IDD        → OPEN, freigegebenes 30-idd.png noch nicht versioniert
99-LAB        → assets/project-icons/99-lab.png
CUST-*        → assets/project-icons/cust-generic.png
```

Zentrale Implementierung:

```text
bootstrap/BSSE.AzureDevOps.Branding.ps1
```

Der idempotente Sollzustand gebrandeter Projekte wird über folgende Project Property verwaltet:

```text
BSSE.PlatformBootstrap.ProjectAvatarSha256
```

Im realen BSSE-CloudOps-Lauf sind Avatar-PUT, Marker-PATCH/GET und der anschließende idempotente `EXISTS`-Zustand für die vier bisher gebrandeten Core-Projekte bestätigt. `30-IDD` wird bereits als Core-Projekt provisioniert, sein Avatar bleibt bis zur Integration des freigegebenen Originalassets bewusst unverändert.

Bekannte Grenze: Eine ausschließlich manuelle Avatar-Änderung außerhalb des Bootstraps ist bei unverändertem Hash-Marker mit der dokumentierten Project-Avatar-Core-API nicht zuverlässig erkennbar.

Details:

```text
docs/Project-Branding.md
```

## Normaler Customer-Onboarding-Technikerweg

Parameter der zentralen Pipeline:

```text
CustomerNumber
CustomerName
CustomerSlug
TenantId
AzureDocumentation
OPNsenseDocumentation
Firewalls
```

AVD und Vaultwarden sind bewusst ausgeschlossen. Die spätere Intune-/IDD-Kundenintegration wird erst nach dem noch offenen `30-IDD ↔ CUST-*`-Contract in dieses Onboarding aufgenommen.

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

Beide Customer-Onboarding-Wege verwenden:

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

## Zentral verwaltete Repository-Policies

`PlatformBootstrap` ist die zentrale Source of Truth für wiederverwendbare
Azure-Repos-Branch-Policies. Workload-Repositories beschreiben ihren Vertrag in
`config/repository-policies.json`; die Reconciliation bleibt bewusst ein
separater Schritt, weil die referenzierte Validation Pipeline bereits vorhanden
sein muss.

```powershell
pwsh -NoProfile -File bootstrap/Sync-BSSERepositoryPolicies.ps1 `
  -OrganizationUrl https://dev.azure.com/BSSE-CloudOps/ `
  -RepositoryKey 20-IaC/Vaultwarden

pwsh -NoProfile -File bootstrap/Sync-BSSERepositoryPolicies.ps1 `
  -OrganizationUrl https://dev.azure.com/BSSE-CloudOps/ `
  -RepositoryKey 20-IaC/Vaultwarden `
  -Apply

# Nur nach ausdrücklicher Freigabe und mit dem unveränderten Apply-Summary:
pwsh -NoProfile -File bootstrap/Sync-BSSERepositoryPolicies.ps1 `
  -OrganizationUrl https://dev.azure.com/BSSE-CloudOps/ `
  -RepositoryKey 20-IaC/Vaultwarden `
  -Rollback `
  -AppliedStatePath <apply-summary.json>
```

Ohne `-Apply` liefert der Lauf ausschließlich `PLAN`, `EXISTS` oder
`BLOCKED`. Mit `-Apply` werden nur eindeutig aufgelöste Sollobjekte geändert
und unmittelbar zurückgelesen. Der Apply ist aus Azure Pipelines gesperrt und
für den bewusst privilegierten lokalen Administrator vorgesehen.

Das Break-Glass-Modell löst ausschließlich die beiden modernen Azure-DevOps-
Anzeigenamen `Bypass policies when pushing` und `Bypass policies when
completing pull requests` zur Laufzeit auf. Numerische Bits werden nicht
festgeschrieben; der historische interne Name `PolicyExempt` ist weder Lookup-
Schlüssel noch Fallback. Die regulär leere Break-Glass-Gruppe erhält exakt
diese beiden Branch-Allows und insbesondere kein `Contribute`, `Force push`,
`Edit policies` oder `Manage permissions`.

Der Vaultwarden-Vertrag verwaltet exakt zwei blockierende Policies: die
automatische `Vaultwarden-CI` Build Validation und die Auflösung aktiver
Kommentar-Threads. Eine Minimum-Reviewer-Policy gehört ausdrücklich nicht zum
Desired State; der PR-Autor darf nach grüner CI und aufgelösten Kommentaren
selbst abschließen. Eine aus dem verworfenen Zwischenvertrag exakt erkannte
Bootstrap-Reviewer-Policy wird als verwaltete Drift kontrolliert entfernt.
Abweichende oder fremde Reviewer-Policies werden nicht gelöscht, sondern
führen zu `BLOCKED`.

Der kontrollierte Rollback vergleicht Namespace, beide Anzeigenamen, interne
Action-Namen und Laufzeit-Bits mit dem unveränderten Apply-Summary. Nur bei
vollständiger Übereinstimmung setzt er exakt diese beiden Bits auf der
verwalteten Gruppen-ACE zurück; alle anderen ACL-Einträge werden vor und nach
dem Vorgang verglichen.

Details:

```text
docs/PlatformBootstrap-Repository.md
docs/Security-Modell.md
```

## Aktueller Runtime-Verifikationsstatus

### Bereits real bestätigt

- Azure-/Azure-DevOps-Authentifizierung im Plattform-Tenant,
- die bisher verwalteten Core-Projekte und deren bisherige Core-Repositories,
- `PlatformBootstrap`-Source-of-Truth-Guard,
- Project Branding inkl. SHA-256-Marker für die vier bisher gebrandeten Core-Projekte,
- idempotenter Folge-Apply des Project Brandings,
- passwordless Entra App/Service Principal `sp-bsse-platform-bootstrap-azdo` erstellt,
- Azure-DevOps-Entitlement `Basic + 00-Platform/Readers` erstellt und anschließend als `EXISTS` verifiziert,
- Collection-ACL-Struktur erfolgreich ausgewertet,
- `Create new projects = Allow` real vergeben, unmittelbar danach verifiziert und später idempotent als `EXISTS` erkannt,
- passender Azure-DevOps-Service-Endpoint-Typ mit `WorkloadIdentityFederation` real eindeutig erkannt,
- realer Service-Connection-Create-Aufruf erreicht,
- Azure DevOps hat bestätigt, dass `creationMode` im aktuellen Endpoint-Typ kein erlaubtes Input ist,
- Vaultwarden-Policyvertrag live angewendet, zurückgelesen und idempotent mit
  exakt Build Validation und Comment Resolution ohne verpflichtendes Human
  Review verifiziert,
- Vaultwarden-Probe-, Evidence- und Closure-PR einschließlich zweier
  Probe-Merge-Kandidaten und abschließender `master`-Validierung erfolgreich
  nachgewiesen.

### Noch offen / laufende Runtime-Verifikation

- Core-Dry-Run gegen den vorhandenen `30-IDD`-Istzustand und Verifikation des geplanten/erkannten `IntuneDefaultDeployment`-Repositoryvertrags,
- freigegebenes `30-idd.png` integrieren und 30-IDD-Branding aktivieren/verifizieren,
- erfolgreicher Create von `sc-platform-bootstrap-azdo` nach der descriptor-basierten Entfernung des pauschalen `creationMode`,
- `sc-platform-bootstrap-azdo` anschließend lesen/verifizieren,
- `fic-sc-platform-bootstrap-azdo` erstellen/verifizieren,
- pipeline-spezifische Service-Connection-Autorisierung erstellen/verifizieren,
- abschließenden Dependency-Dry-Run ohne `PLAN`/`BLOCKED`,
- WIF-basierter Customer-Onboarding-Pipeline-Run,
- Branding-Regressionstest lokal ausführen.

Bis diese Punkte abgeschlossen sind, bleibt v1.9 **Candidate**.

## Detaildokumentation

```text
docs/Customer-Onboarding-Setup.md
docs/Techniker-Workflow.md
docs/Project-Branding.md
docs/Intune-Default-Deployment.md
docs/PlatformBootstrap-Repository.md
docs/Security-Modell.md
docs/Umsetzungsplan.md
```
