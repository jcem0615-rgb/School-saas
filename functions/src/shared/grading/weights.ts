/**
 * How much each component counts for one class.
 *
 * DepEd Order 8, s. 2015 sets weights per subject group, and the school
 * confirms them once for the whole school -- that scheme is unchanged and
 * is still what a report card is printed against by default.
 *
 * What this adds is the case the school-wide scheme cannot express: a
 * subject teacher whose class is marked on a different split, agreed with
 * their department. The override is per subject and section, carries the
 * name of whoever set it, and is subject to the one rule that makes a
 * grading scheme mean anything -- the three must add up to a hundred.
 * The class record names which weights produced the grade, so a set that
 * nobody agreed to is visible rather than silently in effect.
 */

import {GradingComponent, GradingError, round2} from "./assessment";

export interface ComponentWeights {
  writtenWork: number;
  performanceTask: number;
  quarterlyAssessment: number;
}

export function weightFor(weights: ComponentWeights, component: GradingComponent): number {
  switch (component) {
  case "written_work":
    return weights.writtenWork;
  case "performance_task":
    return weights.performanceTask;
  case "quarterly_assessment":
    return weights.quarterlyAssessment;
  }
}

export function weightTotal(weights: ComponentWeights): number {
  return round2(
    weights.writtenWork + weights.performanceTask + weights.quarterlyAssessment
  );
}

/**
 * Whether the three add up to a hundred.
 *
 * The one misconfiguration that does not announce itself: 30/50/30
 * produces grades that look entirely plausible and are wrong for every
 * child in the class, all quarter.
 */
export function balances(weights: ComponentWeights): boolean {
  return Math.abs(weightTotal(weights) - 100) < 0.01;
}

export function validateWeights(input: {
  writtenWork: unknown;
  performanceTask: unknown;
  quarterlyAssessment: unknown;
}): ComponentWeights {
  const read = (raw: unknown, label: string): number => {
    const value = typeof raw === "number" ? raw : Number(raw);
    if (!Number.isFinite(value)) {
      throw new GradingError(`${label} has to be a number.`);
    }
    if (value < 0) {
      throw new GradingError(`${label} cannot be negative.`);
    }
    if (value > 100) {
      throw new GradingError(`${label} cannot be more than 100 per cent.`);
    }
    return round2(value);
  };

  const weights: ComponentWeights = {
    writtenWork: read(input.writtenWork, "Written work"),
    performanceTask: read(input.performanceTask, "Performance tasks"),
    quarterlyAssessment: read(input.quarterlyAssessment, "Quarterly assessment"),
  };

  if (!balances(weights)) {
    throw new GradingError(
      "Written work, performance tasks and quarterly assessment have to add " +
        `up to 100 per cent. These come to ${weightTotal(weights)}.`
    );
  }
  return weights;
}

/** Reads a class-weights document, tolerating an absent one. */
export function weightsFromDoc(
  data: Record<string, unknown> | undefined
): ComponentWeights | null {
  if (!data) return null;
  const num = (raw: unknown) => {
    const value = Number(raw);
    return Number.isFinite(value) ? value : NaN;
  };
  const weights: ComponentWeights = {
    writtenWork: num(data.writtenWork),
    performanceTask: num(data.performanceTask),
    quarterlyAssessment: num(data.quarterlyAssessment),
  };
  if (
    !Number.isFinite(weights.writtenWork) ||
    !Number.isFinite(weights.performanceTask) ||
    !Number.isFinite(weights.quarterlyAssessment)
  ) {
    return null;
  }
  // A stored set that does not balance is not honoured. It should be
  // impossible -- the callable refuses to write one -- and honouring it
  // anyway would be this module computing grades off a scheme it knows
  // is broken.
  return balances(weights) ? weights : null;
}
