# Generisches Kunden-Onboarding

## Pflichtfelder

- interne Kunden-/Debitorennummer
- Kundenname

## Optional

- Azure Tenant ID
- Plattformmodule
- 0..n OPNsense-Firewalls

## Beispiel Cannon

```powershell
.\bootstrap\New-BSSECustomerProject.ps1 `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "<DEBITORENNUMMER>" `
  -CustomerName "Cannon Deutschland GmbH" `
  -TenantId "b1e23349-29c5-410c-befa-ee649ea88549" `
  -Modules AzureDocumentation,OPNsenseDocumentation `
  -Firewalls "HQ"
```

Resultat:

```text
CUST-<DEBITOR>-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
└── Firewall-Cannon-Deutschland-GmbH-HQ
```

## Weitere Firewall später

```powershell
.\bootstrap\Add-BSSECustomerFirewall.ps1 `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "<DEBITORENNUMMER>" `
  -Firewalls "Branch01"
```

## Firewall-Namen

`-Firewalls` erwartet logische, stabile Geräte-/Standortbezeichnungen:

```powershell
-Firewalls "HQ","Branch01","Warehouse"
```

Daraus entstehen automatisch Slugs.

## OPNsense-Anbindung

Das erzeugte `Firewall-*` Repo bleibt vollständig leer, bis die OPNsense selbst über `os-git-backup` den ersten Push durchführt.
