import {Accounts} from "./accounts";
import {JournalLineInput} from "./postJournalEntry";

/** Only the parts of a payslip the ledger cares about. */
export interface PostablePayslip {
  grossPay: number;
  netPay: number;
  totalDeductions: number;
  employerContributions: number;
  employerByKind?: Record<string, number>;
  deductions: {amount: number; kind?: string | null}[];
}

const PAYABLE_FOR: Record<string, string> = {
  sss: Accounts.payableSss,
  philhealth: Accounts.payablePhilHealth,
  pagibig: Accounts.payablePagIbig,
  withholding_tax: Accounts.payableWithholding,
};

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * The journal entry a payroll run posts.
 *
 * A payroll is four facts at once and it is easy to post three of them:
 * the school owes its staff their gross pay, it owes four agencies the
 * contributions withheld, it owes those agencies its own share as well,
 * and cash leaves for the net. Miss the employer share and the entry
 * still balances -- it just understates both the expense and the
 * liability, and nobody notices until a remittance is short.
 *
 * Pure, and separate from the callable, because this is the arithmetic
 * worth testing. An unbalanced entry is refused at the point of posting,
 * which means a mistake here fails a payroll run rather than quietly
 * writing bad books -- the right failure, and still one to catch here.
 */
export function payrollJournalLines(payslips: PostablePayslip[]): JournalLineInput[] {
  const totalGross = round2(payslips.reduce((sum, p) => sum + p.grossPay, 0));
  const totalNet = round2(payslips.reduce((sum, p) => sum + p.netPay, 0));
  const totalEmployer = round2(
    payslips.reduce((sum, p) => sum + (p.employerContributions ?? 0), 0)
  );

  // Everything owed to an agency, employee side and employer side
  // together, because that is how it is remitted: one payment per
  // agency, not one per half.
  const owedByKind: Record<string, number> = {};
  let statutoryWithheld = 0;
  let totalDeducted = 0;

  for (const payslip of payslips) {
    totalDeducted = round2(totalDeducted + payslip.totalDeductions);
    for (const line of payslip.deductions) {
      if (line.kind) {
        owedByKind[line.kind] = round2((owedByKind[line.kind] ?? 0) + line.amount);
        statutoryWithheld = round2(statutoryWithheld + line.amount);
      }
    }
    for (const [kind, amount] of Object.entries(payslip.employerByKind ?? {})) {
      if (amount > 0) {
        owedByKind[kind] = round2((owedByKind[kind] ?? 0) + amount);
      }
    }
  }

  // A deduction that is not a statutory contribution never became a
  // liability. Absences are the one the payslip has today: that is pay
  // the school did not owe in the first place, so it reduces what is
  // charged to salaries rather than creating something owed to anybody.
  const nonStatutory = round2(totalDeducted - statutoryWithheld);
  const salaries = round2(totalGross - nonStatutory);

  const lines: JournalLineInput[] = [];
  if (salaries > 0) {
    lines.push({accountCode: Accounts.expenseSalaries, debit: salaries});
  }
  if (totalEmployer > 0) {
    lines.push({accountCode: Accounts.expenseBenefits, debit: totalEmployer});
  }
  // Sorted so the entry reads the same way every run, which matters when
  // somebody is comparing this month's voucher against last month's.
  for (const kind of Object.keys(owedByKind).sort()) {
    const amount = round2(owedByKind[kind]);
    if (amount > 0) {
      lines.push({accountCode: PAYABLE_FOR[kind] ?? Accounts.payableTrade, credit: amount});
    }
  }
  if (totalNet > 0) {
    lines.push({accountCode: Accounts.cashInBank, credit: totalNet});
  }
  return lines;
}
