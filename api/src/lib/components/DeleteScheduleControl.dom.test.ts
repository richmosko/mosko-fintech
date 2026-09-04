// DeleteScheduleControl.dom.test.ts — Sec F-3 regression test (SELF-265 Sec review, 2026-09-04).
//
// FINDING: the `use:enhance` callback handled ONLY `result.type === 'success'` (specifically the
// `deleted: false` sub-case); a `fail()` response — the action's own 409 refusal — fell through
// to the bare `await update()` at the end with NO message rendered anywhere. Neither
// +page.svelte nor TaxBracketSchedulesList.svelte reads the page's shared `form` prop, so a
// server-side refusal was silently swallowed. REACHABLE WITHOUT AN ATTACKER: the list's own
// `is_seed_template` gate is fail-open (an EXPECTED-CONTRACT field defaulting to "not a seed
// template" on a transient loader read failure), so a Delete control can render on a seed row,
// the server correctly refuses with 409, and — before this fix — the user saw nothing at all.
//
// Same isolation technique TaxBracketScheduleEditor.submit-update.dom.test.ts already
// established: a file-scoped `vi.mock('$app/forms', ...)` that DOES invoke the async
// result-callback a SubmitFunction returns (the shared `tests/stubs/app-forms.ts` deliberately
// does not — see that stub's own header). File-scoped `vi.mock` cannot leak into other test
// files.
//
// @vitest-environment jsdom

import { describe, it, expect, vi, afterEach } from 'vitest';

type MockResult =
	| { type: 'success'; data: { action: 'deleteSchedule'; scheduleId: number; deleted: boolean } }
	| { type: 'failure'; data: { action: 'deleteSchedule'; errors: Record<string, string[]> } }
	| { type: 'error' };

let nextResult: MockResult = { type: 'success', data: { action: 'deleteSchedule', scheduleId: 1, deleted: true } };
const updateCalls: unknown[] = [];

vi.mock('$app/forms', () => {
	return {
		enhance(form_element: HTMLFormElement, submit?: (...args: unknown[]) => unknown) {
			const listener = (event: SubmitEvent) => {
				event.preventDefault();
				if (!submit) return;
				const formData = new FormData(form_element);
				const action = new URL(
					form_element.getAttribute('action') || '',
					window.location.href || 'http://localhost/'
				);
				const callback = submit({
					action,
					formData,
					formElement: form_element,
					controller: new AbortController(),
					cancel: () => {},
					submitter: null
				});
				if (typeof callback === 'function') {
					const update = (opts?: unknown) => {
						updateCalls.push(opts);
						return Promise.resolve();
					};
					if (nextResult.type === 'error') {
						void (callback as (arg: unknown) => unknown)({
							result: { type: 'error', error: new Error('network down') },
							update
						});
					} else {
						void (callback as (arg: unknown) => unknown)({ result: nextResult, update });
					}
				}
			};
			form_element.addEventListener('submit', listener as EventListener);
			return { destroy: () => form_element.removeEventListener('submit', listener as EventListener) };
		}
	};
});

const { render, fireEvent } = await import('@testing-library/svelte');
const { default: DeleteScheduleControl } = await import('./DeleteScheduleControl.svelte');

afterEach(() => {
	updateCalls.length = 0;
	nextResult = { type: 'success', data: { action: 'deleteSchedule', scheduleId: 1, deleted: true } };
});

async function confirmAndSubmit(getByRole: (role: string, opts: { name: string | RegExp }) => HTMLElement) {
	await fireEvent.click(getByRole('button', { name: /^Delete /i }));
	await fireEvent.click(getByRole('button', { name: 'Yes, delete' }));
	await Promise.resolve();
	await Promise.resolve();
}

describe('DeleteScheduleControl — Sec F-3: a fail() response renders its message, not silence', () => {
	it('renders `errors._form` on a 409 refusal (e.g. E38’s seed-template guard) and calls update({ reset: false })', async () => {
		nextResult = {
			type: 'failure',
			data: {
				action: 'deleteSchedule',
				errors: { _form: ['This schedule is part of the provisioned template and cannot be deleted. Edit it instead.'] }
			}
		};
		const { getByRole, findByText } = render(DeleteScheduleControl, {
			props: { scheduleId: 1, itemLabel: 'California (FTB) — Ordinary Income (tax year 2025)' }
		});
		await confirmAndSubmit(getByRole);

		expect(
			await findByText('This schedule is part of the provisioned template and cannot be deleted. Edit it instead.')
		).toBeTruthy();
		expect(updateCalls).toHaveLength(1);
		expect(updateCalls[0]).toEqual({ reset: false });
	});

	it('joins multiple field errors when `_form` is absent', async () => {
		nextResult = {
			type: 'failure',
			data: { action: 'deleteSchedule', errors: { schedule_id: ['Invalid schedule.'] } }
		};
		const { getByRole, findByText } = render(DeleteScheduleControl, {
			props: { scheduleId: 1, itemLabel: 'Federal — Ordinary Income (tax year 2024)' }
		});
		await confirmAndSubmit(getByRole);
		expect(await findByText('Invalid schedule.')).toBeTruthy();
	});

	it('renders a generic message on a thrown/network error', async () => {
		nextResult = { type: 'error' };
		const { getByRole, findByText } = render(DeleteScheduleControl, {
			props: { scheduleId: 1, itemLabel: 'Federal — Ordinary Income (tax year 2024)' }
		});
		await confirmAndSubmit(getByRole);
		expect(await findByText('Something went wrong. Please try again.')).toBeTruthy();
	});

	it('still renders the pre-existing deleted:false message on a benign no-op success', async () => {
		nextResult = { type: 'success', data: { action: 'deleteSchedule', scheduleId: 1, deleted: false } };
		const { getByRole, findByText } = render(DeleteScheduleControl, {
			props: { scheduleId: 1, itemLabel: 'Federal — Ordinary Income (tax year 2024)' }
		});
		await confirmAndSubmit(getByRole);
		expect(await findByText('Not removed — refresh to confirm its current state.')).toBeTruthy();
	});

	it('renders no message on a clean successful delete', async () => {
		nextResult = { type: 'success', data: { action: 'deleteSchedule', scheduleId: 1, deleted: true } };
		const { getByRole, queryByText } = render(DeleteScheduleControl, {
			props: { scheduleId: 1, itemLabel: 'Federal — Ordinary Income (tax year 2024)' }
		});
		await confirmAndSubmit(getByRole);
		expect(queryByText(/Not removed|Could not delete|Something went wrong|provisioned template/)).toBeNull();
	});
});
