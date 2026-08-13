# Temporärer AzureRM-WIF-Bridge-Test

**Status:** implementiert, noch nicht runtime-verifiziert  
**Stand:** 2026-08-13

Der produktive Zielzustand bleibt die dedizierte Azure-DevOps-WIF-Service-Connection `sc-platform-bootstrap-azdo`. Deren neuer `workloadidentityuser`-Finish-Setup-Pfad ist aktuell separat als BLOCKED dokumentiert.

Für die E2E-Validierung des fachlichen Customer-Onboardings existiert deshalb eine getrennte Testpipeline:

```text
pipelines/customer-onboarding-azure-rm-wif-bridge-test.yml
Customer-Onboarding-TEST-AzureRmWifBridge
```

Die Testpipeline verwendet eine temporäre AzureRM-Service-Connection mit Microsoft Entra Workload Identity Federation und derselben dedizierten Plattformidentität. Sie führt keine Azure-Ressourcen-Deployments aus und benötigt keine Azure-RBAC-Zuweisung.

Ablauf:

```text
AzureCLI@3 / AzureRM-WIF
        ↓
Entra-Session der Plattformidentität
        ↓
Azure-DevOps-Entra-Token
        ↓
New-BSSECustomerProject.ps1
Sync-BSSECustomerConfiguration.ps1
        ↓
Validate → DryRun → Approval → Apply → Verify
```

Die Pipeline verlangt das explizite Run-Opt-in:

```text
confirmTemporaryAzureRmWifBridge = true
```

Der Validate-Stage prüft zuerst, ob aus der AzureRM-WIF-Session ein Azure-DevOps-Entra-Token bezogen und gegen Azure DevOps verwendet werden kann. Erst danach läuft der Customer-Onboarding-Dry-Run.

Dieser Testpfad ist keine Architekturänderung und ersetzt den produktiven `workloadidentityuser`-Zielzustand nicht. Nach Klärung der produktiven WIF-Service-Connection wird die Bridge wieder entfernt beziehungsweise deaktiviert.

Der bereits vorhandene `System.AccessToken`-Testpfad bleibt nur sekundärer Fallback. Die AzureRM-WIF-Bridge wird bevorzugt, weil sie die bereits dedizierte Plattformidentität verwendet und keine zusätzlichen Customer-Onboarding-Rechte auf eine Build-Service-Identität verlagert.
