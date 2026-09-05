import * as admin from "firebase-admin";

admin.initializeApp();

// ---------------------------------------------------------------------------
// Module: Authentication
// ---------------------------------------------------------------------------
export {provisionUser} from "./callable/users/provisionUser";
export {bootstrapOwner} from "./callable/users/bootstrapOwner";
export {resetPasswordAdmin} from "./callable/users/resetPasswordAdmin";
// Recovery by SMS: the SIM is the proof, and the number the school
// wrote down is what it is checked against.
export {resetPasswordByPhone} from "./callable/users/resetPasswordByPhone";
export {clearForcePasswordChangeFlag} from "./callable/users/clearForcePasswordChangeFlag";
export {setUserStatus} from "./callable/users/setUserStatus";
export {setParentLink} from "./callable/users/setParentLink";

// ---------------------------------------------------------------------------
// Module: Owner Portal / Subscription Billing
// ---------------------------------------------------------------------------
export {createSchool} from "./callable/schools/createSchool";
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
// Module: Per-subject attendance
//
// Gate attendance answers "did they come to school". These answer "were
// they in Physics", which is what a subject teacher, a failing grade and
// a worried parent all need. Callables rather than client writes,
// because the roll is built server-side from the section's enrolment
// and the register is the record a grade gets argued over.
// ---------------------------------------------------------------------------
export {openClassSession} from "./callable/classSessions/openClassSession";
export {closeClassSession} from "./callable/classSessions/closeClassSession";
export {markSubjectAttendance} from "./callable/classSessions/markSubjectAttendance";

// ---------------------------------------------------------------------------
// Module: Payments
// ---------------------------------------------------------------------------
export {recordPayment} from "./callable/payments/recordPayment";
export {recordRefund} from "./callable/payments/recordRefund";
export {assessStudentFees} from "./callable/payments/assessStudentFees";
export {voidAssessment} from "./callable/payments/voidAssessment";

// Timetable. Clash detection is the feature, so both writes are
// callables and firestore.rules refuses every client write.
export {saveScheduleBlock} from "./callable/schedule/saveScheduleBlock";
export {deleteScheduleBlock} from "./callable/schedule/deleteScheduleBlock";
export {decidePaymentSubmission} from "./callable/payments/decidePaymentSubmission";

// ---------------------------------------------------------------------------
// Module: Registrar/Cashier Portal
// ---------------------------------------------------------------------------
export {registerStudent} from "./callable/students/registerStudent";
export {runYearEndRollover} from "./callable/academics/runYearEndRollover";
export {saveApplicant} from "./callable/admissions/saveApplicant";
export {advanceApplicant} from "./callable/admissions/advanceApplicant";
export {enrolApplicant} from "./callable/admissions/enrolApplicant";
export {setStudentBalance} from "./callable/students/setStudentBalance";

// ---------------------------------------------------------------------------
// Module: Announcements (push notifications)
// ---------------------------------------------------------------------------
export {onAnnouncementCreated} from "./triggers/announcements/onAnnouncementCreated";

// ---------------------------------------------------------------------------
// Module: Coursework (automatic marking)
// ---------------------------------------------------------------------------
export {onCourseworkSubmissionWritten} from "./triggers/coursework/onCourseworkSubmissionWritten";

// ---------------------------------------------------------------------------
// Module: Emergency alerts
// ---------------------------------------------------------------------------
export {onEmergencyAlertCreated} from "./triggers/emergency/onEmergencyAlertCreated";

// ---------------------------------------------------------------------------
// Module: Guidance Office
//
// A summons is the one guidance record a family is allowed to see, and
// the one with a date it is no use learning about afterwards.
// ---------------------------------------------------------------------------
export {onSummonsWritten} from "./triggers/guidance/onSummonsWritten";

// ---------------------------------------------------------------------------
// Module: Employee leave
//
// The decision is already on the employee's own screen; this is what
// tells them it is there. Somebody who filed for Thursday and never
// heard back either comes in when they should not have, or stays away
// when they were expected.
// ---------------------------------------------------------------------------
export {onLeaveRequestDecided} from "./triggers/leave/onLeaveRequestDecided";

// ---------------------------------------------------------------------------
// Module: Parent-teacher messaging
//
// Starting a thread is a callable because deciding whether these two
// people may talk needs a query, and rules cannot query. Everything
// after that is an ordinary client write, policed by membership of the
// conversation this produced.
// ---------------------------------------------------------------------------
export {startConversation} from "./callable/messaging/startConversation";
export {onMessageCreated} from "./triggers/messaging/onMessageCreated";

// Additional modules (billing, attendance, payments, ...)
// export their callables/triggers/scheduled functions here as each module
// is implemented, keeping this file as the single index of everything
// deployed to the project.
