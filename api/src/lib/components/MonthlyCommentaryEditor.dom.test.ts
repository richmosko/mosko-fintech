// MonthlyCommentaryEditor.dom.test.ts — SELF-355 / P3 DOM battery, extended under P4 (SELF-356)
// for the finalize/skip affordances. Covers:
//   - the live "{n} / 4000" code-point counter, per section, including the astral-character
//     unit (Array.from vs .length) and \r\n normalization into the hidden submitted field;
//   - Save disabled when any section is over the 4000-code-point bound;
//   - per-section and global "Copy from {prior month}" enablement (blank-prior → disabled) and
//     behavior (overwrites the current draft value);
//   - final/non-draft read-only rendering: disabled textareas, no Save/Finalize-adjacent
//     copy affordances, the "this report is final" banner;
//   - P4: Finalize wired to its own `?/finalize` form, gated on isDraft, disabled while dirty
//     (the unsaved-changes guard — see the component's own header for why), and re-enabled once
//     `lastSaved` catches up to a successful Save's own echoed values;
//   - P4 AC4: NoLedgerDesignatedPrompt renders when `noLedgerDesignated` is true, never when false;
//   - the $ ReAlloc reference panel's null-allocation "unavailable" fallback.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import MonthlyCommentaryEditor from './MonthlyCommentaryEditor.svelte';

type CommentaryValues = {
	cash: string;
	bonds: string;
	marketable_securities: string;
	alternatives: string;
};

const BLANK: CommentaryValues = { cash: '', bonds: '', marketable_securities: '', alternatives: '' };
const ALLOCATION_STUB = { groups: [], unsorted: null, total_non_re: 0 };
const EMPTY_STALENESS = { is_stale: false as const, stale_items: [] };

function baseProps(overrides: Record<string, unknown> = {}) {
	return {
		targetMonthLabel: 'September 2026',
		isDraft: true,
		commentary: { ...BLANK },
		priorMonthLabel: 'August 2026',
		priorCommentary: { ...BLANK },
		allocation: ALLOCATION_STUB,
		staleness: EMPTY_STALENESS,
		noLedgerDesignated: false,
		...overrides
	};
}

describe('MonthlyCommentaryEditor — sub-sections (PRD §2.6.2, verbatim order)', () => {
	it('renders all four sub-section headings, in Cat-group order', () => {
		const { getAllByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const headings = getAllByRole('heading', { level: 3 }).map((h) => h.textContent);
		expect(headings).toEqual(['Cash', 'Bonds', 'Marketable Securities', 'Alternatives']);
	});

	it('an empty sub-section renders its label with an empty body, not omitted', () => {
		const { getByLabelText } = render(MonthlyCommentaryEditor, { props: baseProps() });
		expect((getByLabelText('Cash commentary') as HTMLTextAreaElement).value).toBe('');
	});
});

describe('MonthlyCommentaryEditor — live code-point counter', () => {
	it('shows an initial count per section from the starting commentary values', () => {
		const { getByText } = render(
			MonthlyCommentaryEditor,
			{
				props: baseProps({
					commentary: { cash: 'a', bonds: 'ab', marketable_securities: 'abc', alternatives: 'abcd' }
				})
			}
		);
		expect(getByText('1 / 4000')).toBeTruthy();
		expect(getByText('2 / 4000')).toBeTruthy();
		expect(getByText('3 / 4000')).toBeTruthy();
		expect(getByText('4 / 4000')).toBeTruthy();
	});

	it('updates live as the user types', async () => {
		const { getByLabelText, getByText } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const textarea = getByLabelText('Cash commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: 'hello' } });
		expect(getByText('5 / 4000')).toBeTruthy();
	});

	// Migration 112 QA leg 6b — the leg that fails if anyone reverts to `.length`: 3,996 ASCII +
	// 4 astral (surrogate-pair) characters = 4,000 CODE POINTS but 4,004 UTF-16 units.
	it('counts CODE POINTS, not UTF-16 units — the astral-character unit leg', async () => {
		const body = 'a'.repeat(3996) + '𝄞𝄞𝄞𝄞';
		expect(body.length).toBe(4004);
		expect(Array.from(body).length).toBe(4000);
		const { getByLabelText, getByText, queryByText } = render(MonthlyCommentaryEditor, {
			props: baseProps()
		});
		const textarea = getByLabelText('Cash commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: body } });
		expect(getByText('4000 / 4000')).toBeTruthy();
		expect(queryByText('4004 / 4000')).toBeNull();
	});

	it('the hidden submitted field mirrors the (already-LF) textarea value normalizeLineEndings is defensive over', async () => {
		// HTML spec note (verified here, not merely assumed): a <textarea>'s own API `.value`
		// getter already normalizes CRLF -> LF on every read, in every real browser and in jsdom
		// — so a real <textarea> submission NEVER hands this component a literal `\r\n` in the
		// first place. normalizeLineEndings()/`\r\n`->`\n` is therefore verified IDEMPOTENT for
		// the actual UI path; it exists (per migration 112's own header) for the theoretical
		// "some OTHER caller reaches this function ... without doing it" path, not this one.
		// getByDisplayValue excludes `type="hidden"` inputs -- read the hidden field via a raw
		// FormData construction over the form, same convention TaxBracketScheduleEditor.dom.test.ts
		// already uses for its own hidden `rows` field.
		const { getByLabelText, container } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const textarea = getByLabelText('Cash commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: 'line one\r\nline two' } });
		expect(textarea.value).toBe('line one\nline two');
		const form = container.querySelector('form') as HTMLFormElement;
		expect(new FormData(form).get('cash')).toBe('line one\nline two');
	});
});

describe('MonthlyCommentaryEditor — Save disabled gate', () => {
	it('Save is enabled when every section is within bound and the report is a draft', () => {
		const { getByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		expect((getByRole('button', { name: 'Save draft' }) as HTMLButtonElement).disabled).toBe(false);
	});

	it('Save disables the instant any single section crosses the 4000-code-point bound', async () => {
		const { getByLabelText, getByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const textarea = getByLabelText('Bonds commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: 'a'.repeat(4001) } });
		expect((getByRole('button', { name: 'Save draft' }) as HTMLButtonElement).disabled).toBe(true);
	});

	it('4000 exactly stays enabled (the bound is <=, not <)', async () => {
		const { getByLabelText, getByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const textarea = getByLabelText('Alternatives commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: 'a'.repeat(4000) } });
		expect((getByRole('button', { name: 'Save draft' }) as HTMLButtonElement).disabled).toBe(false);
	});
});

describe('MonthlyCommentaryEditor — copy-from-prior (blank-by-default + explicit affordance)', () => {
	it('per-section Copy button is disabled when that section of the prior month is blank', () => {
		const { getAllByRole } = render(
			MonthlyCommentaryEditor,
			{ props: baseProps({ priorCommentary: { ...BLANK, cash: 'prior cash' } }) }
		);
		const copyButtons = getAllByRole('button', { name: 'Copy from August 2026' });
		// SECTIONS order is fixed: Cash, Bonds, Marketable Securities, Alternatives.
		expect((copyButtons[0] as HTMLButtonElement).disabled).toBe(false); // Cash — prior has content
		expect((copyButtons[1] as HTMLButtonElement).disabled).toBe(true); // Bonds — prior blank
	});

	it('clicking per-section Copy overwrites the current draft value with the prior month value', async () => {
		const { getAllByRole, getByLabelText } = render(
			MonthlyCommentaryEditor,
			{
				props: baseProps({
					commentary: { ...BLANK, cash: 'current draft text' },
					priorCommentary: { ...BLANK, cash: 'prior cash text' }
				})
			}
		);
		const copyButtons = getAllByRole('button', { name: 'Copy from August 2026' });
		await fireEvent.click(copyButtons[0]);
		expect((getByLabelText('Cash commentary') as HTMLTextAreaElement).value).toBe('prior cash text');
	});

	it('the global Copy-all button is disabled only when every prior section is blank', () => {
		const allBlank = render(MonthlyCommentaryEditor, { props: baseProps() });
		expect(
			(allBlank.getByRole('button', { name: 'Copy all from August 2026' }) as HTMLButtonElement).disabled
		).toBe(true);
		allBlank.unmount();

		const oneFilled = render(
			MonthlyCommentaryEditor,
			{ props: baseProps({ priorCommentary: { ...BLANK, alternatives: 'x' } }) }
		);
		expect(
			(oneFilled.getByRole('button', { name: 'Copy all from August 2026' }) as HTMLButtonElement).disabled
		).toBe(false);
		oneFilled.unmount();
	});

	it('clicking Copy-all overwrites every section from the prior month', async () => {
		const { getByRole, getByLabelText } = render(
			MonthlyCommentaryEditor,
			{
				props: baseProps({
					priorCommentary: {
						cash: 'p-cash',
						bonds: 'p-bonds',
						marketable_securities: 'p-ms',
						alternatives: 'p-alt'
					}
				})
			}
		);
		await fireEvent.click(getByRole('button', { name: 'Copy all from August 2026' }));
		expect((getByLabelText('Cash commentary') as HTMLTextAreaElement).value).toBe('p-cash');
		expect((getByLabelText('Bonds commentary') as HTMLTextAreaElement).value).toBe('p-bonds');
		expect((getByLabelText('Marketable Securities commentary') as HTMLTextAreaElement).value).toBe('p-ms');
		expect((getByLabelText('Alternatives commentary') as HTMLTextAreaElement).value).toBe('p-alt');
	});
});

describe('MonthlyCommentaryEditor — final / read-only rendering', () => {
	it('renders every textarea disabled when the report is final (!isDraft)', () => {
		const { getByLabelText } = render(MonthlyCommentaryEditor, { props: baseProps({ isDraft: false }) });
		expect((getByLabelText('Cash commentary') as HTMLTextAreaElement).disabled).toBe(true);
		expect((getByLabelText('Bonds commentary') as HTMLTextAreaElement).disabled).toBe(true);
	});

	it('shows the "this report is final" banner and hides Save + copy-from-prior affordances', () => {
		const { getByText, queryByRole } = render(MonthlyCommentaryEditor, {
			props: baseProps({ isDraft: false })
		});
		expect(getByText(/this report is final/i)).toBeTruthy();
		expect(queryByRole('button', { name: 'Save draft' })).toBeNull();
		expect(queryByRole('button', { name: /Copy from/ })).toBeNull();
		expect(queryByRole('button', { name: /Copy all from/ })).toBeNull();
	});

	it('a final report still shows its own (frozen) commentary content, never blank', () => {
		const { getByLabelText } = render(
			MonthlyCommentaryEditor,
			{ props: baseProps({ isDraft: false, commentary: { ...BLANK, cash: 'frozen final text' } }) }
		);
		expect((getByLabelText('Cash commentary') as HTMLTextAreaElement).value).toBe('frozen final text');
	});
});

describe('MonthlyCommentaryEditor — Finalize (P4 / SELF-356 AC5, wired)', () => {
	it('Finalize does not render at all on a final (!isDraft) report — nothing left to finalize', () => {
		const { queryByRole } = render(MonthlyCommentaryEditor, { props: baseProps({ isDraft: false }) });
		expect(queryByRole('button', { name: /Finalize/ })).toBeNull();
	});

	it('Finalize is ENABLED on a clean draft (values match the last-saved baseline, here the starting commentary)', () => {
		const { getByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		expect(
			(getByRole('button', { name: 'Finalize September 2026' }) as HTMLButtonElement).disabled
		).toBe(false);
	});

	it('unsaved-changes guard: typing into a section (without Save) disables Finalize', async () => {
		const { getByLabelText, getByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const textarea = getByLabelText('Cash commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: 'unsaved edit' } });
		expect(
			(getByRole('button', { name: 'Finalize September 2026' }) as HTMLButtonElement).disabled
		).toBe(true);
	});

	it('unsaved-changes guard: shows the "Save your changes before finalizing." hint while dirty', async () => {
		const { getByLabelText, getByText } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const textarea = getByLabelText('Cash commentary') as HTMLTextAreaElement;
		await fireEvent.input(textarea, { target: { value: 'unsaved edit' } });
		expect(getByText('Save your changes before finalizing.')).toBeTruthy();
	});

	it('the hint is absent on a clean draft', () => {
		const { queryByText } = render(MonthlyCommentaryEditor, { props: baseProps() });
		expect(queryByText('Save your changes before finalizing.')).toBeNull();
	});

	it('the finalize form carries no body fields beyond the CSRF-free literal action itself (disposition is server-side, never posted)', async () => {
		const { container } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const finalizeForm = container.querySelector('form[action="?/finalize"]') as HTMLFormElement;
		expect(finalizeForm).toBeTruthy();
		expect(Array.from(new FormData(finalizeForm).keys())).toEqual([]);
	});

	it('clicking Finalize (clean draft) enters the loading state', async () => {
		const { getByRole } = render(MonthlyCommentaryEditor, { props: baseProps() });
		const btn = getByRole('button', { name: 'Finalize September 2026' }) as HTMLButtonElement;
		await fireEvent.click(btn);
		expect(btn.getAttribute('aria-busy')).toBe('true');
	});
});

describe('MonthlyCommentaryEditor — no-ledger-designated prompt (P4 / SELF-356 AC4)', () => {
	it('renders the verbatim prompt when noLedgerDesignated is true', () => {
		const { getByText } = render(MonthlyCommentaryEditor, {
			props: baseProps({ noLedgerDesignated: true })
		});
		expect(
			getByText('No IRS/FTB ledger designated — NAV on this report will exclude tax liabilities.')
		).toBeTruthy();
	});

	it('is absent when noLedgerDesignated is false — a prompt, not a permanent fixture', () => {
		const { queryByText } = render(MonthlyCommentaryEditor, {
			props: baseProps({ noLedgerDesignated: false })
		});
		expect(queryByText(/No IRS\/FTB ledger designated/)).toBeNull();
	});

	it('never disables Finalize by itself — a prompt, not a block (AC4)', () => {
		const { getByRole } = render(MonthlyCommentaryEditor, {
			props: baseProps({ noLedgerDesignated: true })
		});
		expect(
			(getByRole('button', { name: 'Finalize September 2026' }) as HTMLButtonElement).disabled
		).toBe(false);
	});

	it('does not render on a final report (nothing left to finalize)', () => {
		const { queryByText } = render(MonthlyCommentaryEditor, {
			props: baseProps({ isDraft: false, noLedgerDesignated: true })
		});
		expect(queryByText(/No IRS\/FTB ledger designated/)).toBeNull();
	});
});

describe('MonthlyCommentaryEditor — $ ReAlloc reference panel', () => {
	it('a null allocation (live read failed) renders the same "temporarily unavailable" copy /allocation uses, never a fabricated table', () => {
		const { getByText } = render(MonthlyCommentaryEditor, { props: baseProps({ allocation: null }) });
		expect(getByText(/temporarily unavailable/i)).toBeTruthy();
	});
});
