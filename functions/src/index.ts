import * as admin from "firebase-admin";

admin.initializeApp();

// ---------------------------------------------------------------------------
// Module: Authentication
// ---------------------------------------------------------------------------
export {provisionUser} from "./callable/users/provisionUser";
export {resetPasswordAdmin} from "./callable/users/resetPasswordAdmin";
export {clearForcePasswordChangeFlag} from "./callable/users/clearForcePasswordChangeFlag";
export {setUserStatus} from "./callable/users/setUserStatus";

// ---------------------------------------------------------------------------
// Module: Owner Portal / Subscription Billing
// ---------------------------------------------------------------------------
export {pauseSchool} from "./callable/schools/pauseSchool";
export {resumeSchool} from "./callable/schools/resumeSchool";
export {recordManualPayment} from "./callable/billing/recordManualPayment";
export {dailyBillingJob} from "./scheduled/dailyBillingJob";
export {gracePeriodCheckJob} from "./scheduled/gracePeriodCheckJob";

// ---------------------------------------------------------------------------
// Cross-cutting: generic audit logging for tenant CRUD collections
// ---------------------------------------------------------------------------
export {onAnyTenantDocWrite} from "./triggers/audit/onAnyTenantDocWrite";

// ---------------------------------------------------------------------------
// Module: QR Attendance
// ---------------------------------------------------------------------------
export {markAttendance} from "./callable/attendance/markAttendance";

// ---------------------------------------------------------------------------
// Module: Payments
// ---------------------------------------------------------------------------
export {recordPayment} from "./callable/payments/recordPayment";
export {recordRefund} from "./callable/payments/recordRefund";

// ---------------------------------------------------------------------------
// Module: Registrar/Cashier Portal
// ---------------------------------------------------------------------------
export {registerStudent} from "./callable/students/registerStudent";
export {setStudentBalance} from "./callable/students/setStudentBalance";

// Additional modules (billing, attendance, payments, notifications, ...)
// export their callables/triggers/scheduled functions here as each module
// is implemented, keeping this file as the single index of everything
// deployed to the project.
