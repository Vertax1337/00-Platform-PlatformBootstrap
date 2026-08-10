# Changelog

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
