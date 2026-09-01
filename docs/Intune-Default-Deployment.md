# 30-IDD – Intune Default Deployment und Configuration Lifecycle

> **Status:** Architekturgrenze BESCHLOSSEN; Core-Bootstrap-Integration und `30-IDD`-Branding code-seitig IMPLEMENTIERT; Azure-DevOps-Runtime-Verifikation für `30-IDD` ausstehend; IntuneCD-/IntuneCD-Monitor-Integration noch offen.  
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

Der genaue technische Contract zwischen `30-IDD`, `CUST-*` und `00-Platform/DocumentationEngine` ist noch offen und wird separat festgelegt.

## 4. Actual State und Desired State

Für die spätere DocumentationEngine-Integration gilt bereits als fachliche Leitplanke:

```text
freigegebener 30-IDD-Stand
→ Desired State

IntuneCD-Backup aus einem realen Kunden-Tenant
→ Actual State
```

Ein Git-Commit ist nicht automatisch Desired State. Entscheidend ist die Rolle des Artefakts im freigegebenen Workflow.

Actual und Desired dürfen nicht stillschweigend zusammengeführt werden. Eine spätere Abweichungs-/Drift-Darstellung erfolgt über einen expliziten Reconciliation-Vertrag.

## 5. Kundenspezifische Daten

Kundenspezifische Intune-Snapshots gehören fachlich zur bestehenden `CUST-*`-Boundary und nicht als Sammeldatenbestand in das zentrale `30-IDD`-Projekt.

Das konkrete Repository-Schema ist noch offen. Eine naheliegende, aber noch **nicht beschlossene** Variante ist ein separates Repository pro verwaltetem Intune-Tenant, zum Beispiel:

```text
CUST-4711-Contoso
├── CustomerConfiguration
├── Documentation
└── Intune-contoso.onmicrosoft.com
```

Diese Entscheidung wird erst zusammen mit dem IntuneCD-Monitor- und Customer-Onboarding-Contract finalisiert.

## 6. Verifizierte Upstream-Eigenschaften

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

### IntuneCD

Der am 2026-09-01 geprüfte Upstream-Stand unterstützt eine breite Anzahl von Intune- und Entra-Konfigurationsbereichen. IntuneCD v2.6.0 enthält zusätzlich einen Offline-Compare-Befehl, der zwei Backup-Verzeichnisse ohne Microsoft-Graph-Aufrufe vergleichen und ein strukturiertes `compare_summary.json` sowie optional HTML erzeugen kann.

## 7. Noch zu klärende technische Punkte

### 7.1 IntuneCD-/Monitor-Versionierung

Beim geprüften Stand ist IntuneCD Monitor v2.1.4 auf `IntuneCD==2.4.1` gepinnt, während IntuneCD selbst bereits v2.6.0 veröffentlicht hat.

Vor einer produktiven Übernahme ist deshalb ein eigener getesteter Compatibility Contract erforderlich. `latest` darf nicht ungeprüft als produktiver Sollzustand verwendet werden.

### 7.2 Upstream-Fork / Ownership

Aktuelle Arbeitsannahme, noch nicht beschlossen:

- IntuneCD möglichst als gepinnte Upstream-Abhängigkeit verwenden,
- IntuneCD Monitor nur dort forken/anpassen, wo CloudOps-Integration, Authentifizierung, Deployment oder UI-Erweiterungen dies tatsächlich erfordern.

### 7.3 Git-/Azure-DevOps-Authentifizierung

Der geprüfte Monitor-Upstream speichert Repository-PATs im Azure Key Vault und baut daraus authentifizierte Git-URLs.

Für CloudOps ist noch zu entscheiden, wie die produktive Azure-Repos-Authentifizierung umgesetzt wird. Ziel ist eine secretarme/secretless Identität, soweit Azure DevOps und die ausgewählte Runtime dies belastbar unterstützen. Es wird **nicht** ungeprüft ein PAT-pro-Kunde-Modell zum Plattformstandard erklärt.

### 7.4 Microsoft-Graph-Identitäten

Noch offen ist die genaue Trennung der Identitäten und Graph Application Permissions.

Zu prüfen ist insbesondere:

```text
Backup / Monitoring
→ möglichst read-only

Deployment / Restore / Update
→ kontrollierte Write-Identität
```

Die exakten Permissions werden erst aus den tatsächlich aktivierten IntuneCD-Modulen abgeleitet. Überprivilegierte pauschale Rechte werden nicht vorab als Sollzustand festgeschrieben.

### 7.5 Hosting des Monitors

Der Upstream-Monitor bringt eine Azure-/Container-basierte Deploymentvariante mit. Die konkrete CloudOps-Zielruntime ist noch offen und wird vor Implementierung gegen aktuelle Azure-Dienste, Wartbarkeit, Kosten, Security und Identity-Anforderungen bewertet.

## 8. DocumentationEngine-Integration

Die native IntuneCD-Dokumentation bleibt als mögliche Spezial-/Technikeransicht nützlich, ist aber nicht automatisch die zentrale BSSE-Kundendokumentation.

Zielrichtung:

```text
IntuneCD Backup / Assignment / Compare Artifacts
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

Der Intune-Adapter und sein Input-Contract werden im DocumentationEngine-Projekt spezifiziert. Dabei werden stabile technische IDs und belegte Assignments/Relationships bevorzugt; Namensähnlichkeit darf keine Beziehung erzeugen.

## 9. Branding

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

## 10. Status

### Bereits beschlossen

- `30-IDD` ist eigener Core-Projektbereich neben `00-Platform`, `10-Automation`, `20-IaC` und `99-LAB`.
- Der vollständige Intune Configuration Lifecycle gehört fachlich nach `30-IDD`, nicht nach `10-Automation`.
- Initiales Repository: `IntuneDefaultDeployment`.
- Kundenspezifische Intune-Snapshots gehören fachlich zur `CUST-*`-Boundary.
- Intune Actual State und freigegebener IDD Desired State werden getrennt behandelt.

### Bereits implementiert

- `New-BSSEAzureDevOpsCore.ps1` kennt `30-IDD`.
- `IntuneDefaultDeployment` ist als initialer Repository-Sollzustand im Core-Bootstrap hinterlegt.
- `assets/project-icons/30-idd.png` ist als eigenes Core-Brandingasset versioniert und im zentralen Mapping aktiviert.
- Regressionstests decken den minimalen `30-IDD`-Core-Vertrag sowie Mapping, PNG-Integrität, Dateigröße und die festgeschriebene Git-Blob-Identität des neuen Assets ab.

### Noch offen

- `30-IDD`-Repositoryvertrag und Branding per Azure-DevOps-Dry-Run/Apply/Verify runtime-verifizieren,
- IntuneCD-/Monitor-Repositorystruktur,
- Upstream-Versionierungs-/Fork-Strategie,
- produktive Runtime/Hosting,
- Azure-Repos-Authentifizierung,
- Graph-Identitäten und Least-Privilege-Permissions,
- `CUST-*`-Intune-Repositoryvertrag,
- Customer-Onboarding-Integration,
- Intune→DocumentationEngine-Contract,
- produktiver Actual/Desired-Reconciliation-Contract.

### Runtime-Verifikation ausstehend

Als nächstes ist ein Core-Dry-Run gegen `BSSE-CloudOps` erforderlich. Erst danach darf bestätigt werden, wie der vorhandene `30-IDD`-Istzustand vom neuen Bootstrap-Vertrag erkannt wird, ob die Repository-Umbenennung/-Erstellung wie erwartet geplant wird und ob das neue Branding als kontrollierter `PLAN` erscheint.
