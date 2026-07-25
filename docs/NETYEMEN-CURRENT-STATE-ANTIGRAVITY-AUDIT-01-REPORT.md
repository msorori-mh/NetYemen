# NETYEMEN CURRENT-STATE AUDIT REPORT (NY-AUDIT-004)

**Task ID:** NY-AUDIT-004<br>
**Title:** NETYEMEN-CURRENT-STATE-ANTIGRAVITY-AUDIT-01<br>
**Report File Path:** `docs/NETYEMEN-CURRENT-STATE-ANTIGRAVITY-AUDIT-01-REPORT.md`<br>
**Repository:** msorori-mh/NetYemen<br>
**Branch:** `antigravity/NY-AUDIT-004`<br>
**Audit Date:** 2026-07-26<br>
**Auditor:** Antigravity Autonomous Agent

---

## 1. Executive Summary

An independent, forensic, and operational audit was performed on the current codebase of the NetYemen project to establish its actual state prior to any refactoring or feature additions.

The codebase represents an early-stage Flutter mobile client MVP designed for local Wi-Fi card sales in Yemen using Supabase as the backend. However, the repository in its current state is non-functional, non-buildable, and incomplete. Crucial platform configuration (`android/`), database scripts (`sql/`), project documentation (`docs/`), and test suites (`test/`) are completely missing from the version control repository. Note that Android is the first mobile release target, iOS is deferred, and the administration website will be a separate Web application rather than Flutter Web. Furthermore, 4 critical compilation errors block the project from building or running.

Security audit findings have been evaluated and classified into 8 total security/data-handling findings: **1 Critical, 2 High, 2 Medium, 2 Low, and 1 Informational**.

---

## 2. Final Decision

### **Decision: HOLD**

**Justification for HOLD:**
1. **Compilation Failure:** The project fails static code analysis (`flutter analyze`) with 4 blocking syntax/type compilation errors.
2. **Missing Build Target:** The `android/` platform folder is absent (iOS release is deferred, and the administration portal will be a separate Web application, not Flutter Web). `flutter build apk` fails immediately.
3. **Missing Schema Artifacts:** The SQL database definitions and RLS policies mentioned in documentation (`sql/netyemen_schema_fixed.sql`) do not exist in the repository.
4. **Missing Version Control Hygiene & Test Suite:** Essential configuration files like `.gitignore` are missing, resulting in binary build artifacts (`build/`, `.dart_tool/`) being committed directly to Git, and the test suite (`test/` directory) is completely absent.

---

## 3. Git Baseline

| Metric | Value |
|---|---|
| **Current Branch** | `antigravity/NY-AUDIT-004` |
| **Working Tree Status** | Clean |
| **HEAD Commit SHA** | `34e8e0f63f2b61647aea9153f67c8b342b5d410b` |
| **origin/main SHA** | `34e8e0f63f2b61647aea9153f67c8b342b5d410b` |
| **Branch Safety** | Verified NOT on `main` branch |

### Recent Git Log (Last 3 commits):
* `34e8e0f` fix: compilation error in providers — avoid provider nesting
* `99d3f8a` feat: filter networks by governorate + search across all governorates
* `e57b757` NetYemen MVP: Flutter + Supabase + Auth + Wallet + Purchases

---

## 4. Repository Inventory

### Present Files & Folders:
* `lib/`
  * `lib/main.dart`
  * `lib/models/card_model.dart`
  * `lib/models/network_model.dart`
  * `lib/models/user_model.dart`
  * `lib/providers/app_providers.dart`
  * `lib/screens/auth/login_screen.dart`
  * `lib/screens/auth/otp_screen.dart`
  * `lib/screens/home/home_screen.dart`
  * `lib/screens/home/network_detail_screen.dart`
  * `lib/screens/home/purchase_success_screen.dart`
  * `lib/screens/main_screen.dart`
  * `lib/screens/profile/profile_screen.dart`
  * `lib/screens/purchases/purchases_screen.dart`
  * `lib/screens/splash_screen.dart`
  * `lib/screens/wallet/deposit_screen.dart`
  * `lib/screens/wallet/wallet_screen.dart`
  * `lib/services/supabase_service.dart`
  * `lib/utils/app_theme.dart`
  * `lib/utils/constants.dart`
* `pubspec.yaml` & `pubspec.lock`
* `README.md`
* `.flutter-plugins-dependencies` (committed improperly)
* `.dart_tool/` (committed improperly)
* `build/` (committed improperly)

### Erroneously Committed Build Artifacts:
* `.dart_tool/` (Package graph, version, file cache)
* `build/` (Compiled native hooks, flutter assets cache, shaders)
* `.flutter-plugins-dependencies`

---

## 5. README vs. Actual Repository Matrix

| Claimed Item in README | Actual Repository State | Status |
|---|---|---|
| `docs/PROJECT_CONTEXT.md` | Missing | 🔴 MISSING |
| `docs/PROMPT_TEMPLATE.md` | Missing | 🔴 MISSING |
| `sql/netyemen_schema_fixed.sql` | Missing | 🔴 MISSING |
| `assets/images/` (declared in pubspec) | Missing | 🔴 MISSING |
| `Flutter 3.x` app | Target platform folder (`android/`) missing | 🔴 INCOMPLETE |
| `.gitignore` | Missing | 🔴 MISSING |
| `test/` | Missing | 🔴 MISSING |
| `supabase/` | Missing | 🔴 MISSING |
| `.github/workflows` | Missing | 🔴 MISSING |

---

## 6. Flutter Command Results

All baseline commands were executed without modifying code:

| Command | Exit Code | Result | Errors | Warnings / Info | Blocker? |
|---|---|---|---|---|---|
| `fvm flutter pub get` | 1 | `fvm` tool unavailable in Antigravity execution environment | N/A | N/A | YES (Tooling baseline issue; separate from application code defects. Version pinning must be completed before remediation.) |
| `flutter pub get` | 0 | Dependencies resolved successfully | 0 | 14 outdated packages | NO |
| `flutter analyze` | 1 | Failed static analysis | 4 | 21 (3 unused imports, 1 missing asset dir, 1 deprecated parameter, 14 deprecated methods, 2 unnecessary null checks) | **YES** |
| `flutter test` | 1 | Test directory `test` not found | 1 | 0 | **YES** (Test-governance blocker: Exit 1 occurs because test directory is absent. Proves test suite is missing; does not prove existing tests failed.) |
| `flutter build apk --debug` | 1 | Unsupported Gradle project (Missing `android/`) | 1 | 0 | **YES** |

---

## 7. Compilation Blockers

The following 4 errors cause `flutter analyze` and compilation to fail:

1. **`lib/main.dart:52:20`**:
   * **Error:** `The argument type 'CardTheme' can't be assigned to the parameter type 'CardThemeData?'.`
   * **Root Cause:** Incorrect class name in `ThemeData` configuration (`CardTheme` constructor used instead of `CardThemeData`).
   * **Impact:** Prevents app initialization and theme compilation.

2. **`lib/providers/app_providers.dart:40:51`**:
   * **Error:** `The name 'Purchase' isn't a type, so it can't be used as a type argument.`
   * **Root Cause:** `app_providers.dart` uses `Purchase` model type but fails to import `../models/card_model.dart`.
   * **Impact:** Prevents Riverpod provider graph compilation.

3. **`lib/screens/auth/login_screen.dart:29:32`**:
   * **Error:** `Undefined name 'supabaseServiceProvider'.`
   * **Root Cause:** `login_screen.dart` attempts to read `supabaseServiceProvider` without importing `../../providers/app_providers.dart`.
   * **Impact:** Prevents login screen compilation.

4. **`lib/screens/auth/otp_screen.dart:31:32`**:
   * **Error:** `Undefined name 'supabaseServiceProvider'.`
   * **Root Cause:** `otp_screen.dart` attempts to read `supabaseServiceProvider` without importing `../../providers/app_providers.dart`.
   * **Impact:** Prevents OTP verification screen compilation.

---

## 8. Architecture Findings

* **Unused & Disconnected Search State:** `networksSearchQueryProvider` is defined and modified in `home_screen.dart`, but `networksProvider` in `app_providers.dart` fetches networks blindly without applying the search query filter.
* **Hardcoded UI Denominations:** `network_detail_screen.dart` hardcodes denomination cards `[200, 500, 1000, 5000]` in UI layout instead of loading prices dynamically from `NetworkPrice` table via `getNetworkPrices()`.
* **Incomplete Actions:**
  * Notification button on `home_screen.dart` has empty handler `onPressed: () {}`.
  * Resend OTP button on `otp_screen.dart` has empty handler `onPressed: () {}`.
* **Client-driven User Profile Creation:** `otp_screen.dart` executes a direct client upsert to the `users` table upon successful OTP login instead of relying on a database trigger (`on auth.users create`).
* **Lack of Offline Handling:** Neither `SupabaseService` nor Riverpod providers handle network timeouts, retries, or offline states.

---

## 9. Security Audit Findings

| ID | Vulnerability / Issue | Severity | Location | Description |
|---|---|---|---|---|
| SEC-01 | Missing SQL Schema & RLS Policies | **CRITICAL** | Repository | `sql/netyemen_schema_fixed.sql` is missing. RLS policies and reveal authorization cannot be audited locally to verify database row isolation. |
| SEC-02 | Card-Number Copy Capability & Data Handling | **LOW** | `purchases_screen.dart:133` | UI/Data-handling observation: Copying complete purchased card numbers is an intended capability for authorized purchasers. Risk is in access/logging policies. |
| SEC-03 | Arbitrary `userId` Parameter Passing | **HIGH** | `supabase_service.dart` | Methods `getUserPurchases`, `getWalletTransactions`, and `purchaseCard` accept `userId` from client. If backend RLS or RPC does not validate `auth.uid() = userId`, IDOR vulnerabilities exist. |
| SEC-04 | Hardcoded Client Price Selection | **HIGH** | `network_detail_screen.dart` | Denomination amounts are passed directly to `purchaseCard` RPC from client state rather than validated against active `network_prices` records. |
| SEC-05 | Missing `.gitignore` & Committed Build Secrets | **MEDIUM** | Project Root | Lack of `.gitignore` exposes build folders, environment caches, and potential secret leaks in git history. |
| SEC-06 | Client-side User Table Upsert | **MEDIUM** | `otp_screen.dart:35` | Client directly upserts `users` table record (`wallet_balance: 0`) post-OTP login. If RLS is weak, users could tamper with user table metadata. |
| SEC-07 | Hardcoded Country Code Assumption | **LOW** | `login_screen.dart:30` | `+967` prefix is prepended automatically without validation. |
| SEC-08 | Deprecated Supabase Parameter | **INFORMATIONAL** | `main.dart:20` | `anonKey` parameter is deprecated in current `supabase_flutter` SDK versions in favor of `publishableKey`. |

### Severity Summary:
* **CRITICAL:** 1 (`SEC-01`)
* **HIGH:** 2 (`SEC-03`, `SEC-04`)
* **MEDIUM:** 2 (`SEC-05`, `SEC-06`)
* **LOW:** 2 (`SEC-02`, `SEC-07`)
* **INFORMATIONAL:** 1 (`SEC-08`)
* **TOTAL FINDINGS:** 8

### Clarification on SEC-02 (Card-Number Copying & Security Requirements):
* **Intended Product Capability:** Copying the complete purchased internet-card number is an intended product feature for the authorized purchaser following a successful purchase.
* **Security Scope:** The copy action itself is not a security vulnerability.
* **Security Requirements for Card Numbers:**
  1. **Purchaser Access:** Only the authorized purchaser may reveal and copy the purchased card number.
  2. **Owner Authorization:** Network owners/vendors must not see full sold-card numbers unless explicitly authorized.
  3. **Third-Party Isolation:** Other customers must never access or view cards purchased by another user.
  4. **Unsold Card Protection:** Unsold card numbers must never be client-readable in plain text.
  5. **Log & Trace Hygiene:** Full card numbers must not appear in application logs, analytics events, notifications, error messages, or unrestricted administrative tables.
  6. **Auditability:** Every privileged reveal of card numbers must be auditable.
* **Reclassification:** SEC-02 is reclassified from CRITICAL to **LOW** (UI/data-handling observation). The technical inability to verify RLS enforcement and reveal authorization policies remains part of **SEC-01** (missing SQL schema/RLS policies) and **SEC-03** (client-side parameter passing), where it belongs.

> **Note on Secrets Audit:** `lib/utils/constants.dart` contains a public `supabaseAnonKey` (`sb_publishable_...`). No `service_role` keys, database passwords, or private API secrets were found in the codebase.

---

## 10. UX / Runtime Findings

* **Runtime Execution Status:** **FAILED / UNABLE TO RUN**.
* **Reason:** Unable to run on emulator or physical device due to:
  1. Missing `android/` platform folder (`unsupported Gradle project`).
  2. 4 fatal compilation errors in Dart code.
* **UX Gaps Identified statically:**
  * Missing asset images directory (`assets/images/`).
  * Empty button callbacks (notifications, resend OTP).
  * No error recovery UI for poor network conditions in Yemen.

---

## 11. Missing Project Components

1. **Flutter Platform Directory:** `android/` (iOS is deferred; admin website will be a separate Web application, not Flutter Web)
2. **Version Control Settings:** `.gitignore`
3. **Database Specifications:** `sql/netyemen_schema_fixed.sql`
4. **Documentation:** `docs/PROJECT_CONTEXT.md`, `docs/PROMPT_TEMPLATE.md`
5. **Testing Suite:** `test/` directory, `integration_test/` directory
6. **CI/CD Workflows:** `.github/workflows/`

---

## 12. Risk Register

| Risk ID | Category | Description | Likelihood | Impact | Mitigating Strategy |
|---|---|---|---|---|---|
| R-01 | Build | Inability to compile or release APK due to missing `android/` directory | High | Critical | Execute controlled platform restoration: `flutter create --platforms=android .` on a dedicated remediation branch. Review generated diff prior to commit to prevent blindly overwriting source files/configs. |
| R-02 | Security | RLS bypass or IDOR data leaks on purchases and wallets | High | Critical | Locate or write standard SQL schema with strict RLS policies checking `auth.uid()`. |
| R-03 | Financial | Double-charging or price forgery during card purchases | Medium | High | Ensure `purchase_card` RPC operates inside an atomic database transaction with `FOR UPDATE` locks. |
| R-04 | Repo Hygiene | Git bloat from committed `build/` and `.dart_tool/` folders | High | Medium | Add `.gitignore`, purge `build/` and `.dart_tool/` from git index (`git rm -r --cached`). |

---

## 13. Recommended Remediation Order

Before adding any new feature or conducting refactoring, the following steps must be completed sequentially:

1. **Phase 1: Tooling Baseline & Project Restoration**
   * Complete Flutter version pinning using `fvm` on developer workstations before remediation work begins.
   * Add a standard Flutter `.gitignore` file.
   * Remove `build/` and `.dart_tool/` from Git tracking.
   * On a **dedicated remediation branch**, run controlled platform restoration:
     `flutter create --platforms=android .`
     *(Note: Android is the first mobile release target. iOS is deferred, and the administration portal will be a separate Web app, not Flutter Web. Review the generated diff before committing to ensure existing source files and configuration are not overwritten blindly.)*

2. **Phase 2: Fix Compilation Blockers**
   * Fix `CardThemeData` issue in `lib/main.dart`.
   * Add `import '../models/card_model.dart';` in `lib/providers/app_providers.dart`.
   * Add `import '../../providers/app_providers.dart';` in `lib/screens/auth/login_screen.dart` and `otp_screen.dart`.

3. **Phase 3: Security & Database Infrastructure**
   * Re-create and commit `sql/netyemen_schema_fixed.sql` including all tables, functions (`purchase_card`), and strict RLS policies.
   * Update `SupabaseService` to remove client-side `userId` parameter passing where `auth.uid()` can be implicitly used.

4. **Phase 4: Architecture, Testing & UI Polish**
   * Wire `networksSearchQueryProvider` to filter `networksProvider`.
   * Dynamic loading of network prices from Supabase.
   * Establish automated unit & widget test suite under `test/` directory to resolve test-governance blocker.

---

## 14. Explicit List of Actions Not Performed

* **NO** production database reads/writes performed.
* **NO** real SMS OTPs sent or requested.
* **NO** card purchases executed.
* **NO** Supabase migrations applied.
* **NO** app source code modified or bug fixes applied.
* **NO** Pull Requests merged.
* **NO** force push executed.

---

## 15. Confirmation of Zero Production Impact

I explicitly confirm that:
1. No write operation was executed on any Supabase or external database instance.
2. No modification was made to the `main` branch.
3. All audit operations were strictly read-only and static inspections.

---
