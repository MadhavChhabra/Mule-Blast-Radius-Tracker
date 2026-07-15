package com.apiguard.core.diff;

/**
 * Risk classification of a single detected change.
 *
 * <p>The central rule that drives every classification is the
 * <b>request/response asymmetry</b>:
 * <ul>
 *   <li>Widening what the server <i>accepts</i> (request side) is safe.</li>
 *   <li>Widening what the server <i>returns</i> (response side) can break strict consumers.</li>
 *   <li>Narrowing <i>either</i> side is breaking.</li>
 * </ul>
 */
public enum Classification {
    /** A consumer (or the server) can break because of this change. */
    BREAKING,
    /** Safe, but not purely additive (e.g. a docs change or a relaxed constraint). */
    NON_BREAKING,
    /** Purely additive: new optional input, new endpoint, new response field. */
    ADDITIVE
}
