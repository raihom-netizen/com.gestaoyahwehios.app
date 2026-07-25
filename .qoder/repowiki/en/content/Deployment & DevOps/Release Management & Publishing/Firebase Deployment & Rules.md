# Firebase Deployment & Rules

<cite>
**Referenced Files in This Document**
- [firebase.json](file://firebase.json)
- [firestore.rules](file://firestore.rules)
- [storage.rules](file://storage.rules)
- [.firebaserc](file://.firebaserc)
- [cors.json](file://cors.json)
- [storage_cors.json](file://flutter_app/storage_cors.json)
- [STORAGE_CORS_README.txt](file://flutter_app/STORAGE_CORS_README.txt)
- [deploy_firebase_rules.ps1](file://scripts/deploy_firebase_rules.ps1)
- [deploy_firebase_rules.bat](file://scripts/deploy_firebase_rules.bat)
- [apply_storage_cors.ps1](file://scripts/apply_storage_cors.ps1)
- [apply_firebase_storage_cors.ps1](file://scripts/apply_firebase_storage_cors.ps1)
- [firebase_rules_gcp_publish.cjs](file://scripts/firebase_rules_gcp_publish.cjs)
- [publish_firestore_rules_rest.cjs](file://scripts/publish_firestore_rules_rest.cjs)
- [gcp_rules_auth.cjs](file://scripts/gcp_rules_auth.cjs)
- [grant_gcp_firebase_rules_iam.cjs](file://scripts/grant_gcp_firebase_rules_iam.cjs)
- [firebase_indexes_gcp_publish.cjs](file://scripts/firebase_indexes_gcp_publish.cjs)
- [firestore_rules_patch_release.cjs](file://scripts/firestore_rules_patch_release.cjs)
- [fix_firestore_rules_encoding.cjs](file://scripts/fix_firestore_rules_encoding.cjs)
- [firebase_rules_preflight.ps1](file://scripts/firebase_rules_preflight.ps1)
- [firebase_rules_gcp_watchdog.ps1](file://scripts/firebase_rules_gcp_watchdog.ps1)
- [forcar_regras_gcp_owner.ps1](file://scripts/forcar_regras_gcp_owner.ps1)
- [regras_pipeline_engenharia.ps1](file://scripts/regras_pipeline_engenharia.ps1)
- [publis_force_update_online.ps1](file://scripts/publish_force_update_online.ps1)
- [DEPLOY_PRODUCAO_YAHWEH.ps1](file://scripts/DEPLOY_PRODUCAO_YAHWEH.ps1)
- [build_e_deploy_web.ps1](file://scripts/build_e_deploy_web.ps1)
- [deploy_web_hosting.ps1](file://scripts/deploy_web_hosting.ps1)
- [deploy_full_gestao_yahweh.ps1](file://scripts/deploy_full_gestao_yahweh.ps1)
- [README_DEPLOY_PRODUCAO.md](file://README_DEPLOY_PRODUCAO.md)
- [COMO_SUBIR_VERSAO_E_REGRAS.md](file://COMO_SUBIR_VERSAO_E_REGRAS.md)
- [FIREBASE_OBSERVABILITY.md](file://docs/FIREBASE_OBSERVABILITY.md)
- [FIREBASE_PADRAO_CONTROLE_TOTAL.md](file://docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md)
- [security_rules_test_firestore/test/firestore.rules.test.js](file://security_rules_test_firestore/test/firestore.rules.test.js)
- [security_rules_test_firestore/package.json](file://security_rules_test_firestore/package.json)
</cite>

## Table of Contents
1. [Introduction](#introduction)
2. [Project Structure](#project-structure)
3. [Core Components](#core-components)
4. [Architecture Overview](#architecture-overview)
5. [Detailed Component Analysis](#detailed-component-analysis)
6. [Dependency Analysis](#dependency-analysis)
7. [Performance Considerations](#performance-considerations)
8. [Troubleshooting Guide](#troubleshooting-guide)
9. [Conclusion](#conclusion)
10. [Appendices](#appendices)

## Introduction
This document provides comprehensive guidance for deploying and managing Firebase resources in this project, with a focus on Firestore security rules, Storage security rules, and CORS configuration. It explains the automated deployment scripts, rule validation processes, rollback procedures, and best practices for staging and production environments. It also covers performance optimization techniques, CDN integration via Firebase Hosting, and troubleshooting common errors related to permissions and CORS.

## Project Structure
The repository organizes Firebase-related configuration and automation as follows:
- Root-level Firebase configuration files define hosting, functions, storage, and rules targets.
- Security rules are stored at the repository root for easy version control and CI/CD integration.
- Scripts under scripts/ automate publishing rules, applying CORS, validating rules, and orchestrating full deployments.
- Documentation under docs/ outlines observability, standards, and operational practices.
- A dedicated test directory contains unit tests for Firestore rules.

```mermaid
graph TB
subgraph "Root"
FJSON["firebase.json"]
FIREBC[".firebaserc"]
FR["firestore.rules"]
SR["storage.rules"]
CORS["cors.json"]
end
subgraph "Scripts"
DFR_PS["deploy_firebase_rules.ps1"]
DFR_BAT["deploy_firebase_rules.bat"]
ASC_PS["apply_storage_cors.ps1"]
AFSC_PS["apply_firebase_storage_cors.ps1"]
GCPPUB["firebase_rules_gcp_publish.cjs"]
PFRREST["publish_firestore_rules_rest.cjs"]
GRAUTH["gcp_rules_auth.cjs"]
IAM["grant_gcp_firebase_rules_iam.cjs"]
IDX["firebase_indexes_gcp_publish.cjs"]
PATCH["firestore_rules_patch_release.cjs"]
FIXENC["fix_firestore_rules_encoding.cjs"]
PREFLIGHT["firebase_rules_preflight.ps1"]
WATCHDOG["firebase_rules_gcp_watchdog.ps1"]
OWNER["forcar_regras_gcp_owner.ps1"]
PIPELINE["regras_pipeline_engenharia.ps1"]
FORCEUPDATE["publish_force_update_online.ps1"]
DEPLOYPROD["DEPLOY_PRODUCAO_YAHWEH.ps1"]
BUILDWEB["build_e_deploy_web.ps1"]
HOSTING["deploy_web_hosting.ps1"]
FULLDEPLOY["deploy_full_gestao_yahweh.ps1"]
end
subgraph "Docs"
OBS["FIREBASE_OBSERVABILITY.md"]
STD["FIREBASE_PADRAO_CONTROLE_TOTAL.md"]
end
subgraph "Tests"
TESTJS["security_rules_test_firestore/test/firestore.rules.test.js"]
PKGTEST["security_rules_test_firestore/package.json"]
end
FJSON --> DFR_PS
FJSON --> DFR_BAT
FJSON --> ASC_PS
FJSON --> AFSC_PS
FJSON --> GCPPUB
FJSON --> PFRREST
FJSON --> IDX
FR --> PREFLIGHT
FR --> GCPPUB
FR --> PFRREST
SR --> ASC_PS
SR --> AFSC_PS
CORS --> ASC_PS
CORS --> AFSC_PS
OBS --> PIPELINE
STD --> PIPELINE
TESTJS --> PKGTEST
```

**Diagram sources**
- [firebase.json:1-200](file://firebase.json#L1-L200)
- [.firebaserc:1-50](file://.firebaserc#L1-L50)
- [firestore.rules:1-200](file://firestore.rules#L1-L200)
- [storage.rules:1-200](file://storage.rules#L1-L200)
- [cors.json:1-50](file://cors.json#L1-L50)
- [deploy_firebase_rules.ps1:1-200](file://scripts/deploy_firebase_rules.ps1#L1-L200)
- [deploy_firebase_rules.bat:1-200](file://scripts/deploy_firebase_rules.bat#L1-L200)
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)
- [apply_firebase_storage_cors.ps1:1-200](file://scripts/apply_firebase_storage_cors.ps1#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [publish_firestore_rules_rest.cjs:1-200](file://scripts/publish_firestore_rules_rest.cjs#L1-L200)
- [firebase_indexes_gcp_publish.cjs:1-200](file://scripts/firebase_indexes_gcp_publish.cjs#L1-L200)
- [firestore_rules_patch_release.cjs:1-200](file://scripts/firestore_rules_patch_release.cjs#L1-L200)
- [fix_firestore_rules_encoding.cjs:1-200](file://scripts/fix_firestore_rules_encoding.cjs#L1-L200)
- [firebase_rules_preflight.ps1:1-200](file://scripts/firebase_rules_preflight.ps1#L1-L200)
- [firebase_rules_gcp_watchdog.ps1:1-200](file://scripts/firebase_rules_gcp_watchdog.ps1#L1-L200)
- [forcar_regras_gcp_owner.ps1:1-200](file://scripts/forcar_regras_gcp_owner.ps1#L1-L200)
- [regras_pipeline_engenharia.ps1:1-200](file://scripts/regras_pipeline_engenharia.ps1#L1-L200)
- [publish_force_update_online.ps1:1-200](file://scripts/publish_force_update_online.ps1#L1-L200)
- [DEPLOY_PRODUCAO_YAHWEH.ps1:1-200](file://scripts/DEPLOY_PRODUCAO_YAHWEH.ps1#L1-L200)
- [build_e_deploy_web.ps1:1-200](file://scripts/build_e_deploy_web.ps1#L1-L200)
- [deploy_web_hosting.ps1:1-200](file://scripts/deploy_web_hosting.ps1#L1-L200)
- [deploy_full_gestao_yahweh.ps1:1-200](file://scripts/deploy_full_gestao_yahweh.ps1#L1-L200)
- [FIREBASE_OBSERVABILITY.md:1-200](file://docs/FIREBASE_OBSERVABILITY.md#L1-L200)
- [FIREBASE_PADRAO_CONTROLE_TOTAL.md:1-200](file://docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md#L1-L200)
- [security_rules_test_firestore/test/firestore.rules.test.js:1-200](file://security_rules_test_firestore/test/firestore.rules.test.js#L1-L200)
- [security_rules_test_firestore/package.json:1-200](file://security_rules_test_firestore/package.json#L1-L200)

**Section sources**
- [firebase.json:1-200](file://firebase.json#L1-L200)
- [.firebaserc:1-50](file://.firebaserc#L1-L50)
- [README_DEPLOY_PRODUCAO.md:1-200](file://README_DEPLOY_PRODUCAO.md#L1-L200)
- [COMO_SUBIR_VERSAO_E_REGRAS.md:1-200](file://COMO_SUBIR_VERSAO_E_REGRAS.md#L1-L200)

## Core Components
- Firebase configuration and targets: firebase.json defines hosting, functions, storage, and rules targets; .firebaserc maps projects and environments.
- Security rules: firestore.rules and storage.rules enforce data access and file operations.
- CORS configuration: cors.json and storage_cors.json define cross-origin policies for web and Storage buckets.
- Automation scripts: PowerShell and Node/CJS scripts publish rules, apply CORS, validate syntax, and orchestrate deployments.
- Testing: Unit tests for Firestore rules ensure correctness before deployment.

Key responsibilities:
- Rule publishing uses either Firebase CLI or direct REST APIs via CJS scripts.
- CORS is applied through Google Cloud SDK commands invoked by PowerShell scripts.
- Preflight checks validate rule syntax and environment readiness.
- Rollback procedures rely on backups and targeted re-deployment of previous versions.

**Section sources**
- [firebase.json:1-200](file://firebase.json#L1-L200)
- [.firebaserc:1-50](file://.firebaserc#L1-L50)
- [firestore.rules:1-200](file://firestore.rules#L1-L200)
- [storage.rules:1-200](file://storage.rules#L1-L200)
- [cors.json:1-50](file://cors.json#L1-L50)
- [storage_cors.json:1-50](file://flutter_app/storage_cors.json#L1-L50)
- [STORAGE_CORS_README.txt:1-200](file://flutter_app/STORAGE_CORS_README.txt#L1-L200)
- [deploy_firebase_rules.ps1:1-200](file://scripts/deploy_firebase_rules.ps1#L1-L200)
- [deploy_firebase_rules.bat:1-200](file://scripts/deploy_firebase_rules.bat#L1-L200)
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)
- [apply_firebase_storage_cors.ps1:1-200](file://scripts/apply_firebase_storage_cors.ps1#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [publish_firestore_rules_rest.cjs:1-200](file://scripts/publish_firestore_rules_rest.cjs#L1-L200)
- [firebase_indexes_gcp_publish.cjs:1-200](file://scripts/firebase_indexes_gcp_publish.cjs#L1-L200)
- [firestore_rules_patch_release.cjs:1-200](file://scripts/firestore_rules_patch_release.cjs#L1-L200)
- [fix_firestore_rules_encoding.cjs:1-200](file://scripts/fix_firestore_rules_encoding.cjs#L1-L200)
- [firebase_rules_preflight.ps1:1-200](file://scripts/firebase_rules_preflight.ps1#L1-L200)
- [firebase_rules_gcp_watchdog.ps1:1-200](file://scripts/firebase_rules_gcp_watchdog.ps1#L1-L200)
- [forcar_regras_gcp_owner.ps1:1-200](file://scripts/forcar_regras_gcp_owner.ps1#L1-L200)
- [regras_pipeline_engenharia.ps1:1-200](file://scripts/regras_pipeline_engenharia.ps1#L1-L200)
- [publish_force_update_online.ps1:1-200](file://scripts/publish_force_update_online.ps1#L1-L200)
- [security_rules_test_firestore/test/firestore.rules.test.js:1-200](file://security_rules_test_firestore/test/firestore.rules.test.js#L1-L200)
- [security_rules_test_firestore/package.json:1-200](file://security_rules_test_firestore/package.json#L1-L200)

## Architecture Overview
The deployment architecture integrates local scripts, Firebase CLI, and Google Cloud REST APIs to manage Firestore rules, Storage rules, and CORS settings. Hosting is configured to serve static assets and integrate with CDN. Observability and standards guide operational practices.

```mermaid
sequenceDiagram
participant Dev as "Developer"
participant Script as "Deploy Script (PowerShell/CJS)"
participant FirebaseCLI as "Firebase CLI"
participant GCPAPI as "Google Cloud REST API"
participant Hosting as "Firebase Hosting"
participant Storage as "Cloud Storage"
participant Firestore as "Firestore"
Dev->>Script : Run deploy script
Script->>FirebaseCLI : Validate rules (preflight)
FirebaseCLI-->>Script : Validation result
Script->>GCPAPI : Publish Firestore rules (REST)
GCPAPI-->>Script : Publish status
Script->>Storage : Apply CORS config
Storage-->>Script : CORS applied
Script->>Hosting : Deploy static assets
Hosting-->>Script : Deploy status
Script->>Firestore : Confirm rules active
Firestore-->>Script : Active
Script-->>Dev : Deployment complete
```

**Diagram sources**
- [firebase.json:1-200](file://firebase.json#L1-L200)
- [deploy_firebase_rules.ps1:1-200](file://scripts/deploy_firebase_rules.ps1#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)
- [deploy_web_hosting.ps1:1-200](file://scripts/deploy_web_hosting.ps1#L1-L200)

## Detailed Component Analysis

### Firestore Rules Publishing
- Purpose: Publish and validate Firestore security rules using CLI or REST APIs.
- Key scripts:
  - deploy_firebase_rules.ps1/bat: Orchestrates rule publishing via Firebase CLI.
  - firebase_rules_gcp_publish.cjs: Publishes rules directly to GCP using REST endpoints.
  - publish_firestore_rules_rest.cjs: Alternative REST-based publisher with error handling.
  - fix_firestore_rules_encoding.cjs: Ensures UTF-8 encoding for rule files.
  - firebase_rules_preflight.ps1: Validates syntax and environment prerequisites.
  - firebase_rules_gcp_watchdog.ps1: Monitors rule deployment health.
  - grant_gcp_firebase_rules_iam.cjs: Grants necessary IAM permissions for rule publishing.
  - gcp_rules_auth.cjs: Handles authentication for GCP REST calls.
  - firestore_rules_patch_release.cjs: Applies targeted patches for release rollouts.

```mermaid
flowchart TD
Start(["Start Firestore Rules Publish"]) --> CheckEnv["Check Environment & Auth"]
CheckEnv --> ValidateRules["Validate Rule Syntax"]
ValidateRules --> Valid{"Valid?"}
Valid --> |No| FixEncoding["Fix Encoding if Needed"]
FixEncoding --> ValidateRules
Valid --> |Yes| PublishViaCLI["Publish via Firebase CLI"]
PublishViaCLI --> PublishREST["Publish via REST (fallback)"]
PublishREST --> MonitorHealth["Monitor Deployment Health"]
MonitorHealth --> Success{"Success?"}
Success --> |No| Rollback["Rollback to Previous Version"]
Success --> |Yes| Complete(["Complete"])
```

**Diagram sources**
- [deploy_firebase_rules.ps1:1-200](file://scripts/deploy_firebase_rules.ps1#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [publish_firestore_rules_rest.cjs:1-200](file://scripts/publish_firestore_rules_rest.cjs#L1-L200)
- [fix_firestore_rules_encoding.cjs:1-200](file://scripts/fix_firestore_rules_encoding.cjs#L1-L200)
- [firebase_rules_preflight.ps1:1-200](file://scripts/firebase_rules_preflight.ps1#L1-L200)
- [firebase_rules_gcp_watchdog.ps1:1-200](file://scripts/firebase_rules_gcp_watchdog.ps1#L1-L200)
- [grant_gcp_firebase_rules_iam.cjs:1-200](file://scripts/grant_gcp_firebase_rules_iam.cjs#L1-L200)
- [gcp_rules_auth.cjs:1-200](file://scripts/gcp_rules_auth.cjs#L1-L200)
- [firestore_rules_patch_release.cjs:1-200](file://scripts/firestore_rules_patch_release.cjs#L1-L200)

**Section sources**
- [deploy_firebase_rules.ps1:1-200](file://scripts/deploy_firebase_rules.ps1#L1-L200)
- [deploy_firebase_rules.bat:1-200](file://scripts/deploy_firebase_rules.bat#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [publish_firestore_rules_rest.cjs:1-200](file://scripts/publish_firestore_rules_rest.cjs#L1-L200)
- [fix_firestore_rules_encoding.cjs:1-200](file://scripts/fix_firestore_rules_encoding.cjs#L1-L200)
- [firebase_rules_preflight.ps1:1-200](file://scripts/firebase_rules_preflight.ps1#L1-L200)
- [firebase_rules_gcp_watchdog.ps1:1-200](file://scripts/firebase_rules_gcp_watchdog.ps1#L1-L200)
- [grant_gcp_firebase_rules_iam.cjs:1-200](file://scripts/grant_gcp_firebase_rules_iam.cjs#L1-L200)
- [gcp_rules_auth.cjs:1-200](file://scripts/gcp_rules_auth.cjs#L1-L200)
- [firestore_rules_patch_release.cjs:1-200](file://scripts/firestore_rules_patch_release.cjs#L1-L200)

### Storage Rules Management
- Purpose: Manage Cloud Storage security rules and CORS configuration.
- Key scripts:
  - apply_storage_cors.ps1: Applies CORS policy using Google Cloud SDK.
  - apply_firebase_storage_cors.ps1: Firebase-specific CORS application.
  - storage.rules: Defines file access policies.
  - cors.json and storage_cors.json: Define CORS policies for web and Storage.

```mermaid
sequenceDiagram
participant Dev as "Developer"
participant Script as "CORS Script (PowerShell)"
participant GCS as "Cloud Storage"
participant Hosting as "Firebase Hosting"
Dev->>Script : Run apply_storage_cors.ps1
Script->>GCS : Set CORS configuration
GCS-->>Script : CORS applied
Script->>Hosting : Verify cross-origin requests
Hosting-->>Script : CORS verified
Script-->>Dev : CORS setup complete
```

**Diagram sources**
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)
- [apply_firebase_storage_cors.ps1:1-200](file://scripts/apply_firebase_storage_cors.ps1#L1-L200)
- [storage.rules:1-200](file://storage.rules#L1-L200)
- [cors.json:1-50](file://cors.json#L1-L50)
- [storage_cors.json:1-50](file://flutter_app/storage_cors.json#L1-L50)

**Section sources**
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)
- [apply_firebase_storage_cors.ps1:1-200](file://scripts/apply_firebase_storage_cors.ps1#L1-L200)
- [storage.rules:1-200](file://storage.rules#L1-L200)
- [cors.json:1-50](file://cors.json#L1-L50)
- [storage_cors.json:1-50](file://flutter_app/storage_cors.json#L1-L50)
- [STORAGE_CORS_README.txt:1-200](file://flutter_app/STORAGE_CORS_README.txt#L1-L200)

### CORS Configuration
- Purpose: Enable cross-origin requests for web applications accessing Firebase services.
- Key files:
  - cors.json: General CORS policy for Firebase Hosting.
  - storage_cors.json: Specific CORS policy for Cloud Storage.
  - STORAGE_CORS_README.txt: Guidance on configuring CORS.

Best practices:
- Restrict allowed origins to trusted domains.
- Limit HTTP methods and headers to required ones.
- Test CORS behavior across browsers and platforms.

**Section sources**
- [cors.json:1-50](file://cors.json#L1-L50)
- [storage_cors.json:1-50](file://flutter_app/storage_cors.json#L1-L50)
- [STORAGE_CORS_README.txt:1-200](file://flutter_app/STORAGE_CORS_README.txt#L1-L200)

### Automated Deployment Scripts
- Purpose: Orchestrate end-to-end deployment including rules, hosting, and indexing.
- Key scripts:
  - DEPLOY_PRODUCAO_YAHWEH.ps1: Production deployment orchestrator.
  - build_e_deploy_web.ps1: Builds and deploys web assets.
  - deploy_web_hosting.ps1: Deploys static content to Firebase Hosting.
  - deploy_full_gestao_yahweh.ps1: Full deployment pipeline.
  - regras_pipeline_engenharia.ps1: Engineering pipeline for rules.
  - publish_force_update_online.ps1: Forces online updates.

```mermaid
flowchart TD
Start(["Start Deployment"]) --> BuildWeb["Build Web Assets"]
BuildWeb --> DeployHosting["Deploy to Firebase Hosting"]
DeployHosting --> PublishRules["Publish Firestore Rules"]
PublishRules --> ApplyCORS["Apply Storage CORS"]
ApplyCORS --> PublishIndexes["Publish Firestore Indexes"]
PublishIndexes --> Verify["Verify Deployment"]
Verify --> Success{"Success?"}
Success --> |No| Rollback["Rollback Changes"]
Success --> |Yes| Complete(["Deployment Complete"])
```

**Diagram sources**
- [DEPLOY_PRODUCAO_YAHWEH.ps1:1-200](file://scripts/DEPLOY_PRODUCAO_YAHWEH.ps1#L1-L200)
- [build_e_deploy_web.ps1:1-200](file://scripts/build_e_deploy_web.ps1#L1-L200)
- [deploy_web_hosting.ps1:1-200](file://scripts/deploy_web_hosting.ps1#L1-L200)
- [deploy_full_gestao_yahweh.ps1:1-200](file://scripts/deploy_full_gestao_yahweh.ps1#L1-L200)
- [regras_pipeline_engenharia.ps1:1-200](file://scripts/regras_pipeline_engenharia.ps1#L1-L200)
- [publish_force_update_online.ps1:1-200](file://scripts/publish_force_update_online.ps1#L1-L200)

**Section sources**
- [DEPLOY_PRODUCAO_YAHWEH.ps1:1-200](file://scripts/DEPLOY_PRODUCAO_YAHWEH.ps1#L1-L200)
- [build_e_deploy_web.ps1:1-200](file://scripts/build_e_deploy_web.ps1#L1-L200)
- [deploy_web_hosting.ps1:1-200](file://scripts/deploy_web_hosting.ps1#L1-L200)
- [deploy_full_gestao_yahweh.ps1:1-200](file://scripts/deploy_full_gestao_yahweh.ps1#L1-L200)
- [regras_pipeline_engenharia.ps1:1-200](file://scripts/regras_pipeline_engenharia.ps1#L1-L200)
- [publish_force_update_online.ps1:1-200](file://scripts/publish_force_update_online.ps1#L1-L200)

### Rule Validation and Testing
- Purpose: Ensure Firestore rules are syntactically correct and functionally valid.
- Key components:
  - firebase_rules_preflight.ps1: Pre-deployment validation.
  - security_rules_test_firestore/test/firestore.rules.test.js: Unit tests for rules.
  - security_rules_test_firestore/package.json: Dependencies for testing.

Testing strategies:
- Use emulator suite for local testing.
- Write unit tests covering edge cases.
- Integrate validation into CI/CD pipelines.

**Section sources**
- [firebase_rules_preflight.ps1:1-200](file://scripts/firebase_rules_preflight.ps1#L1-L200)
- [security_rules_test_firestore/test/firestore.rules.test.js:1-200](file://security_rules_test_firestore/test/firestore.rules.test.js#L1-L200)
- [security_rules_test_firestore/package.json:1-200](file://security_rules_test_firestore/package.json#L1-L200)

### Rollback Procedures
- Purpose: Revert to previous versions of rules and configurations.
- Key practices:
  - Maintain backups of rule files (e.g., firestore.rules.bak-*).
  - Use targeted deployment scripts to re-apply previous versions.
  - Monitor deployment health and trigger rollbacks on failures.

**Section sources**
- [firestore.rules:1-200](file://firestore.rules#L1-L200)
- [firebase_rules_gcp_watchdog.ps1:1-200](file://scripts/firebase_rules_gcp_watchdog.ps1#L1-L200)
- [DEPLOY_PRODUCAO_YAHWEH.ps1:1-200](file://scripts/DEPLOY_PRODUCAO_YAHWEH.ps1#L1-L200)

## Dependency Analysis
The deployment system relies on Firebase CLI, Google Cloud SDK, and Node.js/CJS scripts. Dependencies include authentication mechanisms, REST APIs, and environment variables.

```mermaid
graph TB
Scripts["Deployment Scripts"] --> FirebaseCLI["Firebase CLI"]
Scripts --> GCPSDK["Google Cloud SDK"]
Scripts --> NodeJS["Node.js/CJS Runtime"]
FirebaseCLI --> FirebaseAPI["Firebase REST API"]
GCPSDK --> GCPAPI["Google Cloud REST API"]
NodeJS --> NPM["NPM Packages"]
```

**Diagram sources**
- [firebase.json:1-200](file://firebase.json#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)

**Section sources**
- [firebase.json:1-200](file://firebase.json#L1-L200)
- [firebase_rules_gcp_publish.cjs:1-200](file://scripts/firebase_rules_gcp_publish.cjs#L1-L200)
- [apply_storage_cors.ps1:1-200](file://scripts/apply_storage_cors.ps1#L1-L200)

## Performance Considerations
- Optimize Firestore rules to minimize read/write operations.
- Use caching strategies in Hosting for static assets.
- Configure CDN settings for optimal content delivery.
- Monitor rule evaluation performance using observability tools.

[No sources needed since this section provides general guidance]

## Troubleshooting Guide
Common issues and resolutions:
- CORS errors: Verify cors.json and storage_cors.json configurations.
- Permission denied: Review Firestore and Storage rules for access control.
- Deployment failures: Check authentication and IAM permissions.
- Rule syntax errors: Use preflight validation and fix encoding issues.

**Section sources**
- [cors.json:1-50](file://cors.json#L1-L50)
- [storage_cors.json:1-50](file://flutter_app/storage_cors.json#L1-L50)
- [firestore.rules:1-200](file://firestore.rules#L1-L200)
- [storage.rules:1-200](file://storage.rules#L1-L200)
- [firebase_rules_preflight.ps1:1-200](file://scripts/firebase_rules_preflight.ps1#L1-L200)
- [fix_firestore_rules_encoding.cjs:1-200](file://scripts/fix_firestore_rules_encoding.cjs#L1-L200)

## Conclusion
This documentation outlines the end-to-end process for deploying and managing Firebase resources, focusing on security rules, CORS configuration, and automation. By following the provided scripts and best practices, teams can ensure secure, performant, and reliable deployments across staging and production environments.

[No sources needed since this section summarizes without analyzing specific files]

## Appendices
- Observability: Refer to FIREBASE_OBSERVABILITY.md for monitoring and logging practices.
- Standards: Consult FIREBASE_PADRAO_CONTROLE_TOTAL.md for operational standards.
- Deployment guides: See README_DEPLOY_PRODUCAO.md and COMO_SUBIR_VERSAO_E_REGRAS.md for step-by-step instructions.

**Section sources**
- [FIREBASE_OBSERVABILITY.md:1-200](file://docs/FIREBASE_OBSERVABILITY.md#L1-L200)
- [FIREBASE_PADRAO_CONTROLE_TOTAL.md:1-200](file://docs/FIREBASE_PADRAO_CONTROLE_TOTAL.md#L1-L200)
- [README_DEPLOY_PRODUCAO.md:1-200](file://README_DEPLOY_PRODUCAO.md#L1-L200)
- [COMO_SUBIR_VERSAO_E_REGRAS.md:1-200](file://COMO_SUBIR_VERSAO_E_REGRAS.md#L1-L200)