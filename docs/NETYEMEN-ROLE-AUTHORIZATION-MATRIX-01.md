# NETYEMEN ROLE AUTHORIZATION MATRIX (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-ROLE-AUTHORIZATION-MATRIX-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Security Access Control, Role Governance, and RLS Matrix  

---

## 1. Role Architecture & Persona Definitions

The NetYemen security architecture implements strict **Role-Based Access Control (RBAC)** coupled with **Row-Level Security (RLS)** in PostgreSQL. Every request must be authenticated, authorized by role, and verified against resource ownership.

```
+-----------------------------------------------------------------------------------+
|                            NETYEMEN PLATFORM ROLES                                |
+-----------------------------------------------------------------------------------+
|  1. UNAUTHENTICATED (Anonymous Public Guest)                                      |
|  2. CUSTOMER (Authenticated Retail Card Purchaser)                                |
|  3. NETWORK_OWNER (Verified Hotspot Business Owner)                               |
|  4. NETWORK_OPERATOR (Delegated Owner Staff Account)                              |
|  5. FINANCE_OFFICER (Internal Financial Operations Personnel)                     |
|  6. SUPPORT_AGENT (Customer Care & Dispute Resolution Specialist)                |
|  7. PLATFORM_ADMIN (System Superadmin & Role Authority)                           |
|  8. SYSTEM_AUDITOR (Read-Only Compliance & Forensic Auditor)                      |
+-----------------------------------------------------------------------------------+
```

### 1.1 Detailed Role Definitions
* **`UNAUTHENTICATED`:** Anonymous public app visitors. Restricted exclusively to viewing active/approved networks and public prices.
* **`CUSTOMER`:** Authenticated retail phone user. Permitted to maintain wallet balance, request deposits, execute atomic card purchases, view own purchased cards, and submit card complaints.
* **`NETWORK_OWNER`:** Verified proprietor of one or more Wi-Fi networks. Permitted to configure network details, manage price catalogs, upload card batches, void unsold stock, assign operators, and view own network settlement reports.
* **`NETWORK_OPERATOR`:** Staff member delegated by a Network Owner. Permitted to upload card batches and view inventory for assigned networks only; prohibited from viewing settlement payouts.
* **`FINANCE_OFFICER`:** Internal financial reviewer. Permitted to inspect deposit receipts, approve/reject wallet deposits, audit ledger entries, and calculate owner settlement vouchers.
* **`SUPPORT_AGENT`:** Customer care specialist. Permitted to view customer support tickets, investigate card disputes, quarantine reported cards, and issue approved wallet refunds.
* **`PLATFORM_ADMIN`:** Full administrative lead. Permitted to verify owner accounts, approve network listings, suspend accounts, configure platform settings, and manage staff role assignments.
* **`SYSTEM_AUDITOR`:** Read-only compliance reviewer. Permitted global read access to audit logs, ledger entries, system activity, and security event streams; strictly prohibited from executing mutations or data changes.

---

## 2. Platform Action Authorization Matrix

### 2.1 Matrix Legend
* `ALLOWED`: Permitted without conditional ownership restrictions.
* `DENIED`: Strictly prohibited by backend RBAC and RLS policies (`FORBIDDEN_BEHAVIOR`).
* `CONDITIONAL`: Permitted ONLY IF specific resource ownership or contextual constraint evaluates to `TRUE`.

### 2.2 Complete Action Matrix

| Operation Category | Action Description | UNAUTH | CUST | OWNER | OPERATOR | FINANCE | SUPPORT | ADMIN | AUDITOR |
|---|---|---|---|---|---|---|---|---|---|
| **Public Marketplace** | View Active/Approved Networks | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` |
| **Public Marketplace** | View Network Prices | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` |
| **Authentication** | Request SMS OTP | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Authentication** | Verify SMS OTP | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **User Profile** | Read Own Profile (`auth.uid()`) | `DENIED` | `COND-1` | `COND-1` | `COND-1` | `ALLOWED` | `ALLOWED` | `ALLOWED` | `ALLOWED` |
| **User Profile** | Update Own Profile | `DENIED` | `COND-1` | `COND-1` | `COND-1` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **User Profile** | Suspend Any User Account | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Network Management** | Submit New Network | `DENIED` | `DENIED` | `COND-2` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Network Management** | Update Own Network Details | `DENIED` | `DENIED` | `COND-3` | `COND-4` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Network Management** | Approve / Reject Network | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Card Inventory** | Upload Card Batch File | `DENIED` | `DENIED` | `COND-3` | `COND-4` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Card Inventory** | View Unsold Card PINs | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Card Inventory** | Void / Cancel Unsold Stock | `DENIED` | `DENIED` | `COND-3` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Wallet & Purchases**| Create Deposit Request | `DENIED` | `COND-1` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Wallet & Purchases**| Review / Approve Deposit | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Wallet & Purchases**| Execute Atomic Purchase RPC | `DENIED` | `COND-5` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Wallet & Purchases**| Reveal Purchased Card PIN | `DENIED` | `COND-6` | `DENIED` | `DENIED` | `DENIED` | `COND-7` | `DENIED` | `DENIED` |
| **Disputes & Refunds**| File Card Complaint | `DENIED` | `COND-6` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |
| **Disputes & Refunds**| Approve Wallet Refund | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `ALLOWED` | `DENIED` |
| **Settlements** | View Own Network Settlement | `DENIED` | `DENIED` | `COND-3` | `DENIED` | `ALLOWED` | `DENIED` | `ALLOWED` | `ALLOWED` |
| **Settlements** | Approve Settlement Payout | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Platform Governance**| Assign Platform Roles | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `DENIED` |
| **Audit & Forensics** | View System Audit Logs | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `ALLOWED` | `ALLOWED` |
| **Audit & Forensics** | Modify Audit Logs / Ledger | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` | `DENIED` |

### 2.3 Conditional Access Definitions
* `COND-1`: Allowed ONLY IF target resource `user_id` matches `auth.uid()`.
* `COND-2`: Allowed ONLY IF user profile status is `verified`.
* `COND-3`: Allowed ONLY IF network `owner_id` matches `auth.uid()`.
* `COND-4`: Allowed ONLY IF active row exists in `network_operators` mapping `auth.uid()` to target `network_id`.
* `COND-5`: Allowed ONLY IF `auth.uid()` account is `active`, wallet balance >= price, and network is active.
* `COND-6`: Allowed ONLY IF purchase record `user_id` matches `auth.uid()`.
* `COND-7`: Allowed ONLY IF support agent is actively assigned to an open support ticket referencing the specific `card_id`.

---

## 3. Mandatory Anti-Bypass Security Principles

To ensure bulletproof defense-in-depth, the implementation MUST enforce the following 8 anti-bypass security controls:

1. **UI Visibility Is Not Authorization:** Disabling or hiding UI buttons in mobile/web clients is strictly UX polish. Backend API, RPC, and RLS policies MUST independently re-validate role, state, and permissions on every request.
2. **Backend Enforcement on Every Operation:** Every database table MUST have Row-Level Security (`ENABLE ROW LEVEL SECURITY`) with explicit `DEFAULT DENY` rules.
3. **No General Admin Bypass in Commercial RPCs:** Administrative users (`PLATFORM_ADMIN`) CANNOT bypass commercial logic (e.g., Admins cannot execute `purchase_card` RPC without sufficient wallet balance or buy cards on behalf of users).
4. **Client-Supplied Identifiers Are Untrusted:** Client applications MUST NEVER supply `userId` parameters to RPCs or queries. The backend MUST extract identity strictly from `auth.uid()`.
5. **Dual Role and Resource Ownership Verification:** RLS policies MUST evaluate BOTH the actor's role AND their explicit ownership relationship to the target resource.
6. **Direct RPC and REST Invocation Testing:** Security validation must test direct Postman/cURL HTTP REST calls to Supabase endpoints, ensuring client UI bypass cannot compromise data isolation.
7. **Default-Deny Scoping:** Every role is denied access to all unrelated workflow actions by default. Permissions must be explicitly granted.
8. **Information Leakage Prevention:** Authorization failures MUST return generic `404 Not Found` or `403 Access Denied` errors without revealing whether a user ID, wallet, or card exists.

---

## 4. Negative-Authorization Test Matrix

The following matrix documents security tests designed to attempt unauthorized access across roles:

| Test ID | Attempted Actor | Target Operation | Target Asset Owner | Expected Result | Enforcement Mechanism |
|---|---|---|---|---|---|
| `NEG-AUTH-001` | `CUSTOMER` (User A) | View Wallet Transactions | Customer (User B) | `403 Forbidden / Empty` | RLS `wallet_transactions.user_id = auth.uid()` |
| `NEG-AUTH-002` | `CUSTOMER` (User A) | Call `purchase_card` with `p_user_id = User B` | Customer (User B) | `400 Error (Identity Spoof)` | RPC check `p_user_id = auth.uid()` |
| `NEG-AUTH-003` | `NETWORK_OWNER` (Owner 1)| View Imported Cards | Network Owner (Owner 2) | `0 Rows Returned` | RLS `cards.network_id IN (SELECT id FROM networks WHERE owner_id = auth.uid())` |
| `NEG-AUTH-004` | `NETWORK_OPERATOR` | View Owner Payout Settlement | Network Owner | `403 Forbidden` | RLS `settlements` denies `NETWORK_OPERATOR` |
| `NEG-AUTH-005` | `CUSTOMER` | Approve Pending Deposit | Self Wallet | `403 Forbidden` | RLS `wallet_deposit_requests` update restricted to `FINANCE_OFFICER` |
| `NEG-AUTH-006` | `PLATFORM_ADMIN` | Delete Row in `audit_logs` | System Audit Table | `403 SQL Error (Immutable)`| Database trigger & RLS zero DELETE policy |
| `NEG-AUTH-007` | `UNAUTHENTICATED` | Call `purchase_card` RPC | Any Available Card | `401 Unauthorized` | Supabase Auth JWT requirement |
| `NEG-AUTH-008` | `SUPPORT_AGENT` | View Unsold Card PIN | Unsold Card Stock | `403 Forbidden` | RLS `cards.status = 'sold'` check |
