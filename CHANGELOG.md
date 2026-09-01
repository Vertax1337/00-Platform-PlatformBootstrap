# Changelog

## v1.9 Candidate (`main`)

- zentrale, wiederverwendbare Repository-Policy-Reconciliation für geschützte Azure-Repos-Branches ergänzt
- erster versionierter Policyvertrag für `20-IaC/Vaultwarden/refs/heads/master` mit exakt Kommentarauflösung und blockierender automatischer `Vaultwarden-CI`-Build-Validation; kein verpflichtendes Human Review
- die durch den verworfenen Drei-Policy-Zwischenstand erzeugte Minimum-Reviewer-Policy wird nur bei exakter Signatur als verwaltete Drift entfernt; fremde Reviewer-Policies werden nicht gelöscht
- neue öffentliche Schnittstelle `bootstrap/Sync-BSSERepositoryPolicies.ps1` mit nicht mutierendem Dry Run, kontrolliertem Apply und anschließendem Read-back
- moderne Bypass-Actions werden ausschließlich über die exakten Anzeigenamen `Bypass policies when pushing` und `Bypass policies when completing pull requests` dynamisch aufgelöst; keine festgeschriebenen Bits und kein `PolicyExempt`-Fallback
- regulär leere Break-Glass-Gruppe erhält exakt die beiden modernen Bypass-Allows und ausdrücklich kein Contribute, Force push, Edit policies oder Manage permissions
- effektive direkte und transitive Bypass-Rechte normaler Benutzer sowie fremde Bestands-/Legacy-ACLs werden Fail Closed geprüft
- neue Mock-/Vertragstests `tests/Test-BSSERepositoryPolicy.ps1` für dynamische Bits, Legacy-/Mehrdeutigkeitsfehler, exakte ACEs, Drift, Incident-Preflight, Dry Run, Rollback-Grenzen und Idempotenz
- Live-Apply, idempotenter Read-back sowie Probe-, Evidence- und Closure-PR für Vaultwarden WC-01.4 real erfolgreich nachgewiesen
- zentrale Project-Branding-Komponente `bootstrap/BSSE.AzureDevOps.Branding.ps1` code-seitig implementiert
- verbindliches Avatar-Mapping für `00-Platform`, `10-Automation`, `20-IaC`, `99-LAB` und alle `CUST-*`
- die fünf freigegebenen Original-Branding-Assets sind unter `assets/project-icons/` in `main` versioniert; Dateinamen, Größen und Git-Blob-Inhalte wurden gegen die zuvor geprüften ZIP-Originale abgeglichen
- Core-Bootstrap bindet Project Branding für bestehende und neu erstellte Core-Projekte ein
- Customer-Provisionierung bindet `cust-generic.png` automatisch für bestehende und neu erstellte `CUST-*`-Projekte ein
- Avatar-Write über die offiziell dokumentierte Azure-DevOps-Core-API `Set Project Avatar` (`7.1-preview.1`)
- bestehende Local-/Pipeline-Authentifizierung wird wiederverwendet; kein zusätzliches PAT/Client Secret
- Asset-Validierung prüft Mapping, Existenz, PNG-Signatur und SHA-256
- idempotenter Sollzustand über Project Property `BSSE.PlatformBootstrap.ProjectAvatarSha256`
- Avatar wird nur bei fehlendem/abweichendem verwaltetem Hash-Marker neu gesetzt
- Avatar-PUT akzeptiert dokumentiertes HTTP 200 sowie den im realen BSSE-CloudOps-Lauf beobachteten HTTP-204-Erfolg
- Hash-Marker wird erst nach erfolgreichem Avatar-PUT geschrieben und anschließend per Project-Properties-GET verifiziert
- Project-Properties-PATCH serialisiert ein ein-elementiges `JsonPatchDocument` garantiert als JSON-Array über `ConvertTo-Json -InputObject`; die Arrayform wird vor dem Request zusätzlich geprüft
- fehlende Assets, fehlende Project-ID, Berechtigungs-/REST-Fehler oder nicht verifizierbarer Marker führen Fail Closed zu `BLOCKED`/Fehler statt Warning-only
- bekannte API-Grenze dokumentiert: manuelle Avatar-Drift außerhalb des Bootstraps ist bei unverändertem Marker mit der dokumentierten Core-API nicht zuverlässig lesbar
- neuer Regressionstest `tests/Test-BSSEProjectBranding.ps1` fixiert Mapping, Original-Dateigrößen und SHA-256 der fünf freigegebenen ZIP-Assets
- neue Dokumentation `docs/Project-Branding.md`
- erster realer Self-Hosting-Dry-Run am 13.08.2026 bestätigte Azure CLI, Azure-DevOps-CLI-Erweiterung, Organisationsprofil/Tenant, Azure-Anmeldung und Azure-DevOps-Zugriff; dabei wurde fehlerhaftes Array-Splatting bei internen `.ps1`-Aufrufen entdeckt und auf Hashtable-Splatting korrigiert
- weiterer Dry Run bestätigte Core-Topologie, sauberen PlatformBootstrap-Source-of-Truth und den geplanten fehlenden Self-Hosting-Identitätszustand; ein StrictMode-Fehler bei 0/1-Treffer-Cardinality wurde durch explizite Array-Materialisierung korrigiert
- erster realer `-Apply` erreichte den Avatar-PUT für `00-Platform`; Azure DevOps antwortete mit HTTP 204, woraufhin die Erfolgsprüfung auf HTTP 200/204 korrigiert wurde
- zweiter realer `-Apply` erreichte den SHA-256-Marker-PATCH; Azure DevOps antwortete mit HTTP 500, weil das ein-elementige JSON-Patch-Array durch PowerShell-Pipeline-Enumeration als einzelnes JSON-Objekt serialisiert wurde; dies ist code-seitig korrigiert
- nach der JSON-Patch-Korrektur wurden Project Avatar + SHA-256-Marker für `00-Platform`, `10-Automation`, `20-IaC` und `99-LAB` real erfolgreich angewendet und verifiziert; ein Folge-Apply erkennt alle vier Branding-Zustände idempotent als `EXISTS`
- `sp-bsse-platform-bootstrap-azdo` wurde real als passwordless Entra App/Service Principal erstellt
- der unmittelbar anschließende erste ServicePrincipalEntitlements-POST lieferte transient `VS403283`; ein unveränderter Wiederholungslauf nach kurzer Wartezeit konnte das Entitlement erfolgreich anlegen und `Basic + 00-Platform/Readers` anschließend als `EXISTS` verifizieren
- für genau diesen real bestätigten transienten `VS403283`-Materialisierungsfall ist ein begrenzter Retry implementiert; andere/persistente Entitlement-Fehler bleiben Fail Closed
- der nächste reale Lauf erreichte die Collection-ACL-Ermittlung und zeigte, dass `az devops security permission list --output json` `effectiveAllow/effectiveDeny` nicht flach am Tokenobjekt liefert, sondern unter `acesDictionary` / `AccessControlEntry.extendedInfo`
- die Collection-ACL-Auswertung normalisiert nun das dokumentierte verschachtelte Format auf `EffectiveAllow`/`EffectiveDeny`, berücksichtigt effektive Denies und blockiert unbekannte oder mehrdeutige ACE-Zuordnungen
- der korrigierte ACL-Dry-Run lief vollständig ohne `BLOCKED`/Exception durch und erkannte `Create new projects = Allow` als fehlenden Sollzustand
- der anschließende reale Apply setzte `Create new projects = Allow` erfolgreich und verifizierte die Berechtigung unmittelbar danach aus Azure DevOps
- ein späterer Apply erkennt `Create new projects = Allow` idempotent als `EXISTS`
- die realen Service-Endpoint-Type-Metadaten konnten `Azure DevOps` + `WorkloadIdentityFederation` eindeutig identifizieren und die WIF-Service-Connection planen
- der folgende Apply erreichte erstmals `New-BSSEServiceEndpointConfiguration`, stoppte dort jedoch vor der Service-Connection-Erstellung an einem StrictMode-Zugriff auf fehlendes `validation.isRequired`
- Microsofts Service-Endpoint-Metadaten erlauben `validation` ohne `isRequired`; PlatformBootstrap prüft daher nun Property-Existenz und behandelt nur ein explizites `isRequired: true` als Pflichtfeld, unbekannte explizite Pflichtinputs bleiben Fail Closed
- der nächste Apply erreichte den realen `az devops service-endpoint create`-Aufruf; Azure DevOps lehnte das pauschal gesetzte `creationMode` mit der eindeutigen Meldung ab, dass nur im Contribution-/Endpoint-Typ definierte Inputs zulässig sind
- `ServiceEndpoint.data` startet deshalb jetzt leer und wird ausschließlich aus den real gelieferten `EndpointType.inputDescriptors` aufgebaut; `creationMode` wird nur noch gesetzt, wenn Azure DevOps selbst einen entsprechenden Descriptor liefert
- erfolgreicher WIF-Service-Connection-Create nach dieser metadata-driven Korrektur, FIC/Pipeline-Autorisierung und abschließende Idempotenz-Verifikation bleiben offen

## v1.8

- neue Self-Hosting-/Dependency-Initialisierung `bootstrap/Initialize-BSSEPlatformDependencies.ps1`
- lokales `Start-BSSECustomerOnboarding.ps1` prüft vor dem Kunden-Onboarding automatisch die Plattform-Dependencies
- bei einer unvollständigen Erstinstallation wird zunächst ein vollständiger Dependency-Dry-Run angezeigt und eine separate lokale Freigabe verlangt
- mutierende Dependency-Initialisierung ist aus Azure Pipelines explizit gesperrt; die Pipeline darf sich keine eigene Identität oder organisationsweiten Rechte geben
- Core-Projekte/-Repositories werden bei Erstinstallation über den bestehenden idempotenten Core-Bootstrap provisioniert
- ein leeres `00-Platform/PlatformBootstrap` kann ausschließlich aus einem sauberen, committed lokalen Source-of-Truth nach `main` initialisiert werden
- uncommitted lokaler Stand, nicht-leeres abweichendes Azure-Repo oder Branch-Divergenz führen zu `BLOCKED`; kein Force-Push
- dedizierte secretless Entra-App/Service-Principal `sp-bsse-platform-bootstrap-azdo` wird bei Bedarf ohne Passwort und ohne Azure-RBAC-Rollenzuweisung erstellt
- Service Principal wird programmatisch mit `Basic` + `00-Platform/Readers` in Azure DevOps aufgenommen
- Collection-Berechtigung `Create new projects` wird dynamisch über Security Namespace/Permission Bit ermittelt und gezielt vergeben; keine Project-Collection-Administrator-Mitgliedschaft
- Azure-DevOps-WIF-Service-Connection `sc-platform-bootstrap-azdo` wird anhand der zur Laufzeit gelieferten Service-Endpoint-Type-Metadaten geplant/erstellt; unbekannte erforderliche Inputs führen zu Fail Closed
- federated credential `fic-sc-platform-bootstrap-azdo` wird nach Ermittlung von WIF issuer/subject angelegt und bei Wiederholung auf Drift geprüft
- `Customer-Onboarding` wird anschließend idempotent registriert und ausschließlich für diese Service Connection autorisiert
- `Test-BSSECustomerOnboardingReadiness.ps1` verwendet den nicht-mutierenden Dependency-Dry-Run als zentralen Readiness-Nachweis
- Azure-DevOps-Organisation selbst wird bewusst nicht erzeugt; sie muss bereits existieren und der lokale Erstinstallations-Administrator muss die erforderlichen Entra-/Azure-DevOps-Administrationsrechte besitzen
- Runtime-Verifikation der realen Endpoint-Type-Metadaten, WIF-Erstellung und Berechtigungszuweisung bleibt bis zum ersten echten Erstinstallationslauf ausdrücklich offen

## v1.7

- lokaler und zentraler Customer-Onboarding-Weg auf denselben vollständigen Zielablauf vereinheitlicht
- neues `bootstrap/Sync-BSSECustomerConfiguration.ps1` für persistente CustomerConfiguration
- fehlende Bootstrap-Zieldateien werden geplant/angelegt, identische Dateien bleiben unverändert, abweichende vorhandene Zieldateien führen zu `BLOCKED`
- CustomerConfiguration wird nicht mehr nur als flüchtiges lokales/Agent-Scaffold behandelt
- Git-Persistenz verwendet Azure-DevOps-OAuth-/Entra-Token ohne Token in der Remote-URL
- lokales `Start-BSSECustomerOnboarding.ps1` prüft und persistiert Customer Boundary + CustomerConfiguration und verifiziert beide nach Apply erneut
- `customer-onboarding.yml` prüft und persistiert Customer Boundary + CustomerConfiguration
- Pipeline setzt `hasChanges` als Output; Approval/Apply werden ohne geplante Änderung übersprungen
- Post-Apply-Verify prüft beide Bereiche auf verbleibende PLAN/CREATE/RENAME/BLOCKED-Zustände
- neues idempotentes `Register-BSSECustomerOnboardingPipeline.ps1`; erster Run wird bei Registrierung bewusst übersprungen
- neues nicht-mutierendes `Test-BSSECustomerOnboardingReadiness.ps1`
- neues `docs/Customer-Onboarding-Setup.md` für WIF-Service-Connection und Least-Privilege-Plattformsetup
- Zielberechtigung der PlatformBootstrap-Identität: keine pauschale Project-Collection-Administrator-Mitgliedschaft; collection-level `Create new projects = Allow` plus erforderlicher Projektzugriff
- Source-of-Truth auf v1.7 aktualisiert
- Runtime-Verifikation bleibt bis zum geplanten realen Test ausdrücklich offen

## v1.6.2

- neues lokales interaktives Frontend `bootstrap/Start-BSSECustomerOnboarding.ps1`
- lokale Eingabemaske entspricht fachlich der Azure-DevOps-Customer-Onboarding-Pipeline
- lokaler Ablauf: Eingaben → Dry Run → Bestätigung → Apply → Post-Apply Verify
- `[BLOCKED]` verhindert lokal automatisch ein Apply
- ohne `[PLAN]` wird lokal kein Apply angeboten
- lokaler und Pipeline-Weg verwenden weiterhin dasselbe Backend `New-BSSECustomerProject.ps1`
- `docs/Techniker-Workflow.md` und `docs/Umsetzungsplan.md` aktualisiert

## v1.6.1

- Architekturgrenze zwischen Dokumentationsplattform und IaC-Produkten korrigiert
- `Customer-Onboarding` behandelt ausschließlich Kundenbasis, `AzureDocumentation`, `OPNsenseDocumentation` und optionale `Firewall-*` RAW-Repositories
- AVD/Vaultwarden aus `pipelines/customer-onboarding.yml` entfernt
- `New-BSSECustomerProject.ps1` akzeptiert nur noch `AzureDocumentation` und `OPNsenseDocumentation`
- Übergabe von `AVD`, `AVD-Accelerator` oder `Vaultwarden` an `New-BSSECustomerProject.ps1` wird mit eindeutiger IaC-Abgrenzungsfehlermeldung abgewiesen
- CustomerConfiguration-Scaffold erzeugt keine `infrastructure/avd`- oder `infrastructure/vaultwarden`-Bereiche mehr
- bestehender `customer.yml`-Schlüssel `modules:` bleibt aus Kompatibilitätsgründen bestehen und enthält nur noch Dokumentationsmodule
- IaC-Produkte bleiben unter `20-IaC` und erhalten einen separaten Techniker-/Deployment-Workflow
- Dokumentation und Service-Connection-Namenskonventionen entsprechend präzisiert

## v1.6

- gemeinsame Authentifizierungslogik erkennt lokale Ausführung und Azure Pipelines automatisch
- lokale Ausführung behält Azure-CLI-Kontextsuche, Tenant-Korrektur, interaktiven Login und lokalen Browser-Fallback
- Pipeline-Ausführung deaktiviert interaktive Logins und Browser-Fallbacks vollständig
- bevorzugte Pipeline-Authentifizierung über AzureCLI@3 mit Azure-DevOps-Service-Connection / Microsoft Entra Workload Identity Federation
- optionaler nicht-interaktiver Kompatibilitätsfallback über `SYSTEM_ACCESSTOKEN` → `AZURE_DEVOPS_EXT_PAT`
- Pipeline-Session liefert `ExecutionMode` und `AuthenticationMode` zur Diagnose
- neue Techniker-Pipeline `/pipelines/customer-onboarding.yml`
- Onboarding-Pipeline implementiert Validate → Dry Run → Manual Approval → Apply → Verify
- Post-Apply-Verify führt erneut einen Dry Run aus und schlägt bei verbleibenden PLAN/CREATE/RENAME/BLOCKED-Zuständen fehl
- neuer `docs/Techniker-Workflow.md`
- Azure-DevOps-seitig bleiben Service Connection, minimale Berechtigungen, Pipeline-Registrierung und Runtime-Verifikation offen

## v1.5.2

- Sollname des Azure-Collector-Repositories auf `10-Automation-AzureInfrastructureCollector` korrigiert
- `10-Automation` verwendet für die beiden aktuell bestehenden Automations-Repositories nun konsistent die Projektnamenspräfixierung
- Legacy-Name `AzureInfrastructureCollector` wird nicht mehr als Soll-Repository provisioniert
- Fail-safe Legacy-Schutz verhindert bei `AzureInfrastructureCollector` die automatische Anlage eines Duplikats bzw. automatische Umbenennung
- fachlicher Komponentenname `AzureInfrastructureCollector` bleibt unverändert und ist vom Repositorynamen getrennt
- Source-of-Truth, README und Namenskonventionen auf v1.5.2 aktualisiert
- keine globale Umbenennung von Repositories anderer Azure-DevOps-Projekte

## v1.5.1

- Sollname des OPNsense-Dokumentationsrepositories auf `10-Automation-OPNsenseDocumentation` korrigiert
- Core-Bootstrap erkennt das bestehende Repository als `EXISTS / no change`
- Legacy-Namen `OPNsenseDocumentation` und `OpenSenseDocumentation` werden nicht mehr als Soll-Repositories provisioniert
- Fail-safe Legacy-Schutz verhindert bei alten Namen die automatische Anlage eines Duplikats bzw. automatische Umbenennung
- Modulbezeichner `OPNsenseDocumentation` bleibt unverändert, da er kein Repositoryname ist
- Dokumentation/Namenskonventionen aktualisiert; keine globale Umbenennung anderer Repositories

## v1.5

- neues Repository `00-Platform/PlatformBootstrap`
- `PlatformBootstrap` ist künftig das erste Soll-Repository eines neu angelegten `00-Platform` Projekts
- bestehende `PipelineTemplates` Repositories werden bei Upgrades nicht umbenannt und vorhandener Repository-Inhalt bleibt unverändert
- erneuter Bootstrap-Lauf ergänzt bei bestehenden Installationen nur das fehlende `PlatformBootstrap`
- Plattformdokumentation und Namenskonventionen entsprechend aktualisiert

## v1.4.1

- `-Modules` akzeptiert jetzt Komma-/Semikolon-Listen bei Aufruf über `pwsh.exe -File`
- `-Firewalls` akzeptiert ebenfalls Komma-/Semikolon-Listen
- Modulvalidierung erfolgt nach der Normalisierung
- doppelte Module/Firewall-Einträge werden automatisch entfernt

## v1.4

- generische Unterstützung für 0..n OPNsense-Firewalls pro Kundenprojekt
- bestehende Kunden werden primär über die stabile CustomerNumber (`CUST-<ID>-*`) wiedergefunden; Umfirmierungen erzeugen kein Duplikat
- neuer Parameter `-Firewalls`
- Firewall-Repo-Schema `Firewall-<CustomerSlug>-<FirewallSlug>`
- RAW-Firewall-Repositories werden vollständig leer erstellt
- kein README, kein `.gitignore`, kein Pipeline-YAML, kein Initial-Commit
- idempotente Prüfung bestehender Firewall-Repositories
- neues `Add-BSSECustomerFirewall.ps1` für spätere Erweiterungen
- CustomerConfiguration-Scaffold dokumentiert Firewall-Repo-Zuordnung
- OPNsense Backup und OPNsense Documentation bewusst entkoppelt
- Security-Modell um Schutzklasse RAW-CONFIDENTIAL ergänzt

## v1.3

- interne Kunden-/Debitorennummer als stabile Kunden-ID
- Modulmodell
- CustomerConfiguration / Documentation
- Initial-Repository-Wiederverwendung

## v1.2

- Multi-Tenant-Kontextsuche
- Tenant-spezifischer Fallback-Login

## v1.1

- automatischer Azure/Azure-DevOps Login-Bootstrap
