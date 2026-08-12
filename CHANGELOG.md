# Changelog

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
- bestehende `PipelineTemplates` Repositories werden bei Upgrades nicht umbenannt oder verändert
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