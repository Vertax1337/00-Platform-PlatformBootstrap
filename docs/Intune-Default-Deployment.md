# 30-IDD – Intune Default Deployment und Configuration Lifecycle

> **Status:** Architekturgrenze, Cross-Project-Boundary und CUST-Intune-Repositoryvertrag BESCHLOSSEN; Core-Bootstrap-Integration und `30-IDD`-Branding code-seitig IMPLEMENTIERT; Azure-DevOps-Runtime-Verifikation für `30-IDD` ausstehend; IntuneCD-/IntuneCD-Monitor-Runtime noch offen.  
> **Stand:** 2026-09-01

## 1. Zweck und Verantwortungsgrenze

`30-IDD` ist der zentrale Azure-DevOps-Projektbereich für den Intune-Konfigurationslebenszyklus von BSSE.

Die Einordnung unter `30-IDD` ist bewusst von `10-Automation` getrennt:

```text
10-Automation
→ read-only Infrastruktur-Collector, Sanitization und Dokumentationsautomation

30-IDD
→ Intune Default Deployment
→ Intune-Konfigurationsmanagement
→ Backup / Compare / kontrollierte Änderung
→ Techniker-Frontend für Intune
```

IntuneCD wird damit nicht lediglich als weiterer Collector betrachtet. Das Werkzeug kann Konfigurationen aus Intune sichern, lokale bzw. versionierte Konfigurationen vergleichen und Konfigurationen wieder in einen Tenant übertragen. Zusammen mit IntuneCD Monitor entsteht deshalb ein eigener fachlicher Configuration-Lifecycle-Bereich.

Der projektübergreifende Ownership-/Boundary-Vertrag ist in [`Intune-Cross-Project-Contract.md`](Intune-Cross-Project-Contract.md) kanonisch festgelegt. Der konkrete CUST-seitige Repositoryvertrag steht in [`Intune-Customer-Repository-Contract.md`](Intune-Customer-Repository-Contract.md). Dieses Dokument hält nur die `30-IDD`-fachliche Sicht und dupliziert die vollständigen Plattformverträge nicht.

## 2. Initialer Bootstrap-Vertrag

Der erste verbindliche Repository-Vertrag lautet:

```text
30-IDD
└── IntuneDefaultDeployment
```

`IntuneDefaultDeployment` ist der zentrale Ausgangspunkt für den freigegebenen BSSE-Intune-Sollstand.

Weitere Repositories werden **nicht** vorab erfunden. Insbesondere ist noch offen, ob die spätere IntuneCD-/Monitor-Integration in einem oder mehreren zusätzlichen Repositories geführt wird.

Der Core-Bootstrap muss bei einem bereits vorhandenen Azure-DevOps-Projekt `30-IDD` den normalen idempotenten Repository-Vertrag anwenden. Existiert dort nur das von Azure DevOps initial erzeugte gleichnamige Repository `30-IDD`, wird im Dry Run die kontrollierte Umbenennung zu `IntuneDefaultDeployment` geplant und erst mit `-Apply` ausgeführt.

## 3. Zielbild für IntuneCD und IntuneCD Monitor

Die fachliche Zielrichtung ist:

```text
                         30-IDD
                           │
          ┌────────────────┴────────────────┐
          │                                 │
          ▼                                 ▼
 IntuneDefaultDeployment             IntuneCD / Monitor
     freigegebener                  Backup / Compare /
       Sollstand                    Techniker-Frontend
          │                                 │
          │ desired                         │ actual capture
          ▼                                 ▼
   DocumentationEngine            CUST-* Customer Boundary
          ▲                                 │
          └──────────── actual ─────────────┘
```

Der fachliche Cross-Project-Contract und die CUST-seitige Repositorygrenze sind beschlossen. Technisch offen bleiben insbesondere Snapshot-Schema, Monitor-Runtime/-Identity, Customer-Onboarding-Implementierung und Adapterimplementierung.

## 4. Actual State und Desired State

Für die spätere DocumentationEngine-Integration gilt verbindlich:

```text
freigegebener 30-IDD-Stand
→ Desired State / desiredDeployment

IntuneCD-Backup aus einem realen Kunden-Tenant
→ Actual State / actual
```

Ein Git-Commit ist nicht automatisch Desired State. Entscheidend ist die Rolle des Artefakts im freigegebenen Workflow.

Der operative `baseline`-Status von IntuneCD Monitor ist kein Ersatz für die kanonische Desired-State-Quelle.

Actual und Desired dürfen nicht stillschweigend zusammengeführt werden. Eine spätere Abweichungs-/Drift-Darstellung erfolgt über einen expliziten Reconciliation-Vertrag.

## 5. Kundenspezifische Daten

Kundenspezifische Intune-Snapshots gehören fachlich zur bestehenden `CUST-*`-Boundary und nicht als Sammeldatenbestand in das zentrale `30-IDD`-Projekt.

**Beschlossen:** Ein produktiv verwalteter Intune-Tenant erhält innerhalb der zugehörigen `CUST-*`-Boundary genau ein eigenes versioniertes Repository für den Intune-Iststand.

Verbindliches Namensschema:

```text
Intune-<TenantSlug>
```

Beispiel:

```text
CUST-4711-Contoso
├── CustomerConfiguration
├── Documentation
├── Intune-contoso-prod
└── Intune-contoso-lab
```

Die stabile technische Tenant-Zuordnung erfolgt über die Microsoft Entra Tenant ID und nicht über den Repositorynamen. Der `TenantSlug` ist ein bei Erstregistrierung persistierter menschenlesbarer Alias und wird bei späteren Tenant-/Domain-/Kunden-Umbenennungen nicht automatisch geändert.

Die kanonische Zuordnung liegt in `CustomerConfiguration/customer.yml` unter `intune.tenants[]`. Mehrere Intune-Tenants pro Kunde sind ausdrücklich unterstützt.

Customer-Intune-Repositories werden bis zu einer feineren, technisch verifizierten Datenklassifikation als `RAW-CONFIDENTIAL` behandelt.

Details: [`Intune-Customer-Repository-Contract.md`](Intune-Customer-Repository-Contract.md).

## 6. BSSE Intune Snapshot Contract

Zwischen IntuneCD/Monitor, Customer-Repository und DocumentationEngine wird ein versionierter Snapshot-/Provenance-Contract eingeführt.

Der Contract kapselt die native IntuneCD-Ausgabe und muss mindestens Customer-/Tenant-Identität, Snapshot-/Perspektivinformation, Tool-/Commit-Provenance, Artefaktreferenzen/-integrität, Coverage sowie Validation-/Security-Status transportieren können.

Die konkrete JSON-/YAML-Repräsentation, Dateibenennung und Schema-Technologie bleiben technisch offen.

Details: [`Intune-Cross-Project-Contract.md`](Intune-Cross-Project-Contract.md).

## 7. Verifizierte Upstream-Eigenschaften

Die Bewertung vom 2026-09-01 basiert auf den Upstream-Repositories:

```text
https://github.com/almenscorner/IntuneCD
https://github.com/almenscorner/intunecd-monitor
```

### IntuneCD Monitor

Der Monitor ist ein Multi-Tenant-Frontend für IntuneCD und unterstützt bereits die fachlich relevanten Bausteine:

- Tenant-Verwaltung,
- Repository-Zuordnung pro Tenant,
- Backup- und Update-Aufrufe,
- geplante/scheduled Jobs,
- Status- und Änderungsübersichten,
- Assignment-Auswertung,
- optionale native IntuneCD-Dokumentation.

Der Upstream-Code klont das einem Tenant zugeordnete Git-Repository, führt `IntuneCD-startbackup` bzw. `IntuneCD-startupdate` aus, liest Summary-/Assignment-Artefakte und pusht Änderungen wieder in das Repository.

Für CloudOps gilt zusätzlich: Die Monitor-Datenbank darf diese Zuordnung operativ cachen, ist aber nicht kanonische Source of Truth für `CustomerNumber ↔ tenantId ↔ Repository`. Diese Zuordnung bleibt versioniert in der CustomerConfiguration.

### IntuneCD

Der am 2026-09-01 geprüfte Upstream-Stand unterstützt eine breite Anzahl von Intune- und Entra-Konfigurationsbereichen. IntuneCD v2.6.0 enthält zusätzlich einen Offline-Compare-Befehl, der zwei Backup-Verzeichnisse ohne Microsoft-Graph-Aufrufe vergleichen und ein strukturiertes `compare_summary.json` sowie optional HTML erzeugen kann.

## 8. Noch zu klärende technische Punkte

### 8.1 IntuneCD-/Monitor-Versionierung

Beim geprüften Stand ist IntuneCD Monitor v2.1.4 auf `IntuneCD==2.4.1` gepinnt, während IntuneCD selbst bereits v2.6.0 veröffentlicht hat.

Vor einer produktiven Übernahme ist deshalb ein eigener getesteter Compatibility Contract erforderlich. `latest` darf nicht ungeprüft als produktiver Sollzustand verwendet werden.

### 8.2 Upstream-Fork / Ownership

Aktuelle Arbeitsannahme, noch nicht beschlossen:

- IntuneCD möglichst als gepinnte Upstream-Abhängigkeit verwenden,
- IntuneCD Monitor nur dort forken/anpassen, wo CloudOps-Integration, Authentifizierung, Deployment oder UI-Erweiterungen dies tatsächlich erfordern.

### 8.3 Git-/Azure-DevOps-Authentifizierung

Der geprüfte Monitor-Upstream speichert Repository-PATs im Azure Key Vault und baut daraus authentifizierte Git-URLs.

Für CloudOps ist noch zu entscheiden, wie die produktive Azure-Repos-Authentifizierung umgesetzt wird. Ziel ist eine secretarme/secretless Identität, soweit Azure DevOps und die ausgewählte Runtime dies belastbar unterstützen. Es wird **nicht** ungeprüft ein PAT-pro-Kunde-Modell zum Plattformstandard erklärt.

### 8.4 Microsoft-Graph-Identitäten

Noch offen ist die genaue Trennung der Identitäten und Graph Application Permissions.

Zu prüfen ist insbesondere:

```text
Backup / Monitoring
→ möglichst read-only

Deployment / Restore / Update
→ kontrollierte Write-Identität
```

Die exakten Permissions werden erst aus den tatsächlich aktivierten IntuneCD-Modulen abgeleitet. Überprivilegierte pauschale Rechte werden nicht vorab als Sollzustand festgeschrieben.

### 8.5 Hosting des Monitors

Der Upstream-Monitor bringt eine Azure-/Container-basierte Deploymentvariante mit. Die konkrete CloudOps-Zielruntime ist noch offen und wird vor Implementierung gegen aktuelle Azure-Dienste, Wartbarkeit, Kosten, Security und Identity-Anforderungen bewertet.

### 8.6 Customer-Onboarding

Der Repositoryvertrag ist fachlich festgelegt, technisch aber noch nicht umgesetzt.

Der zukünftige PlatformBootstrap-Pfad muss `0..n` Intune-Tenants je Kunde idempotent verarbeiten, `Intune-<TenantSlug>` provisionieren und die kanonische `intune.tenants[]`-Registry in CustomerConfiguration pflegen.

Das bestehende `customer.tenantId` beziehungsweise der heutige `TenantId`-Parameter wird nicht stillschweigend zum Multi-Tenant-Intune-Vertrag umdefiniert. Die konkrete CLI-/Pipelineoberfläche bleibt ein eigener Implementierungsworkchunk.

## 9. DocumentationEngine-Integration

Die native IntuneCD-Dokumentation bleibt als mögliche Spezial-/Technikeransicht nützlich, ist aber nicht die zentrale BSSE-Kundendokumentation.

Zielrichtung:

```text
IntuneCD Backup / Assignment / Compare Artifacts
                    ↓
       BSSE Snapshot / Provenance Contract
                    ↓
            Intune Source Adapter
                    ↓
        DocumentationEngine Canonical Models
                    ↓
           Semantic View Builder
                    ↓
          Document View Model
                    ↓
        Markdown / DOCX / PDF / Diagramme
```

Der Intune-Adapter und sein Consumer-Contract werden im DocumentationEngine-Projekt unter `docs/INTUNECD_INTERFACE.md` geführt. Stabile technische IDs und belegte Assignments/Relationships sind verbindlich; Namensähnlichkeit darf keine Beziehung erzeugen.

Die native IntuneCD-Dokumentation wird nicht als Canonical Source of Truth geparst. IntuneCD Compare darf als provider-spezifische Evidence-/Vergleichshilfe genutzt werden, ersetzt jedoch nicht den providerunabhängigen Reconciliation-Contract.

## 10. Branding

Das vom Projektverantwortlichen eingebrachte Asset ist jetzt versioniert:

```text
assets/project-icons/30-idd.png
```

Der GitHub-Stand weist dafür aktuell die unveränderliche Git-Blob-ID

```text
8cbe66d5b92b864ddc136adb7e643e4e8055b824
```

und eine Dateigröße von `1074185` Byte aus. PlatformBootstrap ordnet `30-IDD` diesem Asset nun wie die übrigen Core-Projekte über die zentrale Branding-Komponente zu. Die lokale Assetprüfung validiert PNG-Signatur und berechnet den für Azure DevOps verwendeten SHA-256-Marker dynamisch.

Damit gilt code-seitig:

```text
30-IDD Project/Repository Provisioning
→ IMPLEMENTIERT

30-IDD Project Branding
→ IMPLEMENTIERT

30-IDD Runtime Apply/Verify in Azure DevOps
→ OFFEN
```

## 11. Status

### Bereits beschlossen

- `30-IDD` ist eigener Core-Projektbereich neben `00-Platform`, `10-Automation`, `20-IaC` und `99-LAB`.
- Der vollständige Intune Configuration Lifecycle gehört fachlich nach `30-IDD`, nicht nach `10-Automation`.
- Initiales Repository: `IntuneDefaultDeployment`.
- Kundenspezifische Intune-Snapshots gehören fachlich zur `CUST-*`-Boundary.
- Ein produktiv verwalteter Intune-Tenant erhält genau ein eigenes Customer-Repository `Intune-<TenantSlug>`.
- CustomerNumber und Entra Tenant ID sind die stabilen Zuordnungsidentitäten; TenantSlug ist ein persistierter Repositoryalias.
- Die kanonische Tenant→Repository-Zuordnung liegt in `CustomerConfiguration/customer.yml` unter `intune.tenants[]`.
- Customer-Intune-Repositories sind zunächst `RAW-CONFIDENTIAL`.
- Intune Actual State und freigegebener IDD Desired State werden getrennt behandelt.
- Der BSSE Intune Snapshot-/Provenance-Contract ist als Cross-Project-Grenze beschlossen.
- Native IntuneCD-Dokumentation und Compare ersetzen weder DVM noch providerunabhängige Reconciliation.

### Bereits implementiert

- `New-BSSEAzureDevOpsCore.ps1` kennt `30-IDD`.
- `IntuneDefaultDeployment` ist als initialer Repository-Sollzustand im Core-Bootstrap hinterlegt.
- `assets/project-icons/30-idd.png` ist als eigenes Core-Brandingasset versioniert und im zentralen Mapping aktiviert.
- Regressionstests decken den minimalen `30-IDD`-Core-Vertrag sowie Mapping, PNG-Integrität, Dateigröße und die festgeschriebene Git-Blob-Identität des neuen Assets ab.
- Cross-Project-Contract ist unter `docs/Intune-Cross-Project-Contract.md` versioniert.
- CUST-Intune-Repositoryvertrag ist unter `docs/Intune-Customer-Repository-Contract.md` versioniert.

### Noch offen

- `30-IDD`-Repositoryvertrag und Branding per Azure-DevOps-Dry-Run/Apply/Verify runtime-verifizieren,
- IntuneCD-/Monitor-Repositorystruktur,
- Upstream-Versionierungs-/Fork-Strategie,
- produktive Runtime/Hosting,
- Azure-Repos-Authentifizierung,
- Graph-Identitäten und Least-Privilege-Permissions,
- technische Customer-Onboarding-Integration für `0..n` Intune-Tenants,
- technische `customer.yml`-Reconciliation,
- Seed-/Default-Branch-Vertrag der Customer-Intune-Repositories,
- technisches Snapshot-Schema,
- DocumentationEngine Intune-Adapterimplementierung,
- produktiver Actual/Desired-Reconciliation-Contract.

### Runtime-Verifikation ausstehend

Als nächstes ist ein Core-Dry-Run gegen `BSSE-CloudOps` erforderlich. Erst danach darf bestätigt werden, wie der vorhandene `30-IDD`-Istzustand vom neuen Bootstrap-Vertrag erkannt wird, ob die Repository-Umbenennung/-Erstellung wie erwartet geplant wird und ob das neue Branding als kontrollierter `PLAN` erscheint.
