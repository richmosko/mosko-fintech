// OwnerIdentificationEditor.dom.test.ts — SELF-359 verification battery. Covers:
//   - the field prefills from `initialHeaderText`, blank when null (AC1/AC2).
//   - the helper copy, empty-state copy, and forward-only statement render VERBATIM (AC2).
//   - the empty state disappears once a non-blank value is typed, and reappears once cleared.
//   - client-side trim-to-null / length / single-line mirror gates the Save button (AC3's client
//     mirror) and cancels a forced submit while invalid — the pre-submit half is reachable
//     through `tests/stubs/app-forms.ts`'s enhance stub (it invokes the SubmitFunction
//     synchronously on a real submit); the async server-error-rendering half is NOT (same
//     documented harness limit TaxBracketScheduleEditor.dom.test.ts / PurchaseEntryForm.dom.test.ts
//     already accept).
//   - the posted FormData carries the field under its server-expected name, and the form posts to
//     `?/save`.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render, fireEvent } from '@testing-library/svelte';
import OwnerIdentificationEditor from './OwnerIdentificationEditor.svelte';

const HELPER_TEXT =
	'Appears at the top of every monthly report generated after you save. Plain text, one line, up to 120 characters. Example: THE ⟨NAME⟩ 2023 TRUST.';
const EMPTY_STATE_TEXT = 'No header set — reports show no owner line until you add one.';
const FORWARD_ONLY_TEXT = 'Reports already generated keep the header they were generated with.';

describe('OwnerIdentificationEditor — prefill (AC1)', () => {
	it('renders blank when initialHeaderText is null', () => {
		const { getByLabelText } = render(OwnerIdentificationEditor, { props: { initialHeaderText: null } });
		expect((getByLabelText('Owner identification') as HTMLInputElement).value).toBe('');
	});

	it('renders an existing header value prefilled', () => {
		const { getByLabelText } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: 'THE SMITH 2023 TRUST' }
		});
		expect((getByLabelText('Owner identification') as HTMLInputElement).value).toBe('THE SMITH 2023 TRUST');
	});
});

describe('OwnerIdentificationEditor — copy folded verbatim (AC2)', () => {
	it('renders the helper text', () => {
		const { getByText } = render(OwnerIdentificationEditor, { props: { initialHeaderText: null } });
		expect(getByText(HELPER_TEXT)).toBeTruthy();
	});

	it('renders the forward-only statement unconditionally', () => {
		const { getByText } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: 'THE SMITH 2023 TRUST' }
		});
		expect(getByText(FORWARD_ONLY_TEXT)).toBeTruthy();
	});

	it('renders the empty state when no header is set', () => {
		const { getByText } = render(OwnerIdentificationEditor, { props: { initialHeaderText: null } });
		expect(getByText(EMPTY_STATE_TEXT)).toBeTruthy();
	});

	it('does NOT render the empty state when a header is set', () => {
		const { queryByText } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: 'THE SMITH 2023 TRUST' }
		});
		expect(queryByText(EMPTY_STATE_TEXT)).toBeNull();
	});
});

describe('OwnerIdentificationEditor — empty state tracks the LIVE draft, not only the initial value', () => {
	it('the empty state disappears once a non-blank value is typed', async () => {
		const { getByLabelText, queryByText } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: null }
		});
		await fireEvent.input(getByLabelText('Owner identification'), {
			target: { value: 'THE SMITH 2023 TRUST' }
		});
		expect(queryByText(EMPTY_STATE_TEXT)).toBeNull();
	});

	it('the empty state reappears once a set value is cleared to blank', async () => {
		const { getByLabelText, getByText } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: 'THE SMITH 2023 TRUST' }
		});
		await fireEvent.input(getByLabelText('Owner identification'), { target: { value: '' } });
		expect(getByText(EMPTY_STATE_TEXT)).toBeTruthy();
	});

	it('the empty state reappears when the field is cleared to whitespace-only (trim-to-blank)', async () => {
		const { getByLabelText, getByText } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: 'THE SMITH 2023 TRUST' }
		});
		await fireEvent.input(getByLabelText('Owner identification'), { target: { value: '   ' } });
		expect(getByText(EMPTY_STATE_TEXT)).toBeTruthy();
	});
});

describe('OwnerIdentificationEditor — client mirror gates Save (AC3 client mirror)', () => {
	it('Save is enabled for a blank field (a valid CLEAR, not an error)', () => {
		const { getByRole } = render(OwnerIdentificationEditor, { props: { initialHeaderText: null } });
		expect((getByRole('button', { name: 'Save' }) as HTMLButtonElement).disabled).toBe(false);
	});

	it('Save is disabled and an error shown once the field exceeds 120 characters', async () => {
		const { getByLabelText, getByRole, findByRole } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: null }
		});
		await fireEvent.input(getByLabelText('Owner identification'), { target: { value: 'A'.repeat(121) } });
		const alert = await findByRole('alert');
		expect(alert.textContent).toMatch(/120 characters/);
		expect((getByRole('button', { name: 'Save' }) as HTMLButtonElement).disabled).toBe(true);
	});

	it('exactly 120 characters is accepted (boundary)', async () => {
		const { getByLabelText, getByRole } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: null }
		});
		await fireEvent.input(getByLabelText('Owner identification'), { target: { value: 'A'.repeat(120) } });
		expect((getByRole('button', { name: 'Save' }) as HTMLButtonElement).disabled).toBe(false);
	});

	it('an embedded Unicode line-boundary code point is rejected (single-line mirror) and disables Save', async () => {
		// LINE SEPARATOR (U+2028), not LF: a native <input type="text"> SANITIZES literal CR/LF out
		// of its own `.value` on assignment (the HTML "value sanitization algorithm" strips only
		// those two code points, per spec) — so a client-side test injecting '\n' can never observe
		// this schema's LF leg at all; the browser has already removed it before this component's
		// code runs. U+2028 (and VT/FF/NEL/PS) are NOT stripped by that algorithm and so are the
		// only line-boundary code points a real single-line <input> can actually carry — this test
		// exercises one of those, and the LF/CR legs are covered instead in
		// owner-id.server.test.ts, which posts raw FormData with no browser sanitization in the way.
		const { getByLabelText, getByRole, findByRole } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: null }
		});
		const lineSeparator = String.fromCharCode(0x2028);
		await fireEvent.input(getByLabelText('Owner identification'), {
			target: { value: `line one${lineSeparator}line two` }
		});
		const alert = await findByRole('alert');
		expect(alert.textContent).toMatch(/single line/i);
		expect((getByRole('button', { name: 'Save' }) as HTMLButtonElement).disabled).toBe(true);
	});

	it('a forced submit while Save is disabled does not throw (the SubmitFunction cancels it)', async () => {
		const { getByLabelText, container } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: null }
		});
		await fireEvent.input(getByLabelText('Owner identification'), { target: { value: 'A'.repeat(121) } });
		const form = container.querySelector('form') as HTMLFormElement;
		await expect(fireEvent.submit(form)).resolves.not.toThrow();
	});
});

describe('OwnerIdentificationEditor — form transport', () => {
	it('posts to the ?/save action', () => {
		const { container } = render(OwnerIdentificationEditor, { props: { initialHeaderText: null } });
		const form = container.querySelector('form') as HTMLFormElement;
		expect(form.getAttribute('action')).toBe('?/save');
	});

	it('the posted FormData carries the field under owner_id_header_text', async () => {
		const { getByLabelText, container } = render(OwnerIdentificationEditor, {
			props: { initialHeaderText: null }
		});
		await fireEvent.input(getByLabelText('Owner identification'), { target: { value: 'THE SMITH 2023 TRUST' } });
		const form = container.querySelector('form') as HTMLFormElement;
		expect(new FormData(form).get('owner_id_header_text')).toBe('THE SMITH 2023 TRUST');
	});
});
