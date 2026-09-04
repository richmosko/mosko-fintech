// TaxBracketScheduleEditor.submit-update.dom.test.ts — QA regression test (SELF-265 walk gate,
// 2026-09-04). Isolated from TaxBracketScheduleEditor.dom.test.ts on purpose: it needs a DIFFERENT
// `$app/forms` mock (one that DOES invoke the async result-callback a SubmitFunction returns) than
// every other *.dom.test.ts in this tree relies on — `tests/stubs/app-forms.ts`'s own header states
// the shared stub deliberately stops short of that and names exactly this extension path ("a mocked
// fetch... not assumed by this one"). `vi.mock` is file-scoped in Vitest, so this override cannot
// leak into, or break, any other test file's use of the real shared stub.
//
// WHY THIS TEST EXISTS — a live walk finding, not a spec derived from the code. Editing a federal
// ordinary schedule in a real browser against a real Postgres DB (SELF-265 QA walk arc (b)) showed:
// the save succeeds (confirmed server-side — the DB held exactly the intended new value and nothing
// else changed), but the ON-SCREEN form immediately went blank with "Enter an amount" / "A schedule
// label is required" errors on EVERY field, as if the save had failed or wiped the schedule. A full
// page reload proved the data was intact. The DOM harness's shared `enhance` stub cannot see this at
// all (it never invokes the returned callback — see its own header), which is exactly why the walk,
// not the pre-existing battery, is what caught it.
//
// ROOT CAUSE (read against the component's own `handleSubmit`): SvelteKit's `update()` resets the
// underlying native <form> element back to its DOM defaults unless called as `update({ reset: false
// })` — the FAILURE branch already does this correctly. The SUCCESS branch calls bare `update()`,
// which is the one branch where the user is looking at values they just typed and expects to keep
// seeing them (mode: 'edit' keeps the same editor mounted; mode: 'create' unmounts a moment later,
// masking the same defect there). This test locks in that asymmetry as a spec: on a successful save,
// `update` must be called with `{ reset: false }`, exactly like the failure branch already is.
//
// This test is RED against the code as walked (bare `update()` on success) and will go GREEN the
// moment the success branch is brought in line with the failure branch's own established pattern.

import { describe, it, expect, vi, afterEach } from 'vitest';

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
				// Mirrors the real SvelteKit contract: a SubmitFunction may return an async
				// callback that receives `{ result, update }` once the action responds. This mock
				// answers with a canned SUCCESS result — the shape the component's own
				// `ActionSuccess` type expects — and a spy `update` that records exactly what
				// options it was called with, which is the only thing this test needs to observe.
				if (typeof callback === 'function') {
					const scheduleId = Number(formData.get('schedule_id') ?? 1);
					const update = (opts?: unknown) => {
						updateCalls.push(opts);
						return Promise.resolve();
					};
					void (callback as (arg: unknown) => unknown)({
						result: { type: 'success', status: 200, data: { action: 'saveSchedule', ok: true, scheduleId } },
						update
					});
				}
			};
			form_element.addEventListener('submit', listener as EventListener);
			return { destroy: () => form_element.removeEventListener('submit', listener as EventListener) };
		}
	};
});

const { render, fireEvent } = await import('@testing-library/svelte');
const { default: TaxBracketScheduleEditor } = await import('./TaxBracketScheduleEditor.svelte');

type ScheduleType = 'federal_ordinary' | 'federal_lt_cg' | 'california_ordinary';

const editProps = {
	mode: 'edit' as const,
	scheduleType: 'federal_ordinary' as ScheduleType,
	taxYear: 2026,
	scheduleId: 1,
	initialLabel: 'Single filer, 2026 IRS Schedule X',
	initialStandardDeduction: 15000,
	initialPriorYearBalance: null,
	initialRows: [
		{ bracket_floor: 0, bracket_rate: 0.1 },
		{ bracket_floor: 11000, bracket_rate: 0.22 }
	]
};

afterEach(() => {
	updateCalls.length = 0;
});

describe('TaxBracketScheduleEditor — post-save update() call (QA walk finding, SELF-265)', () => {
	it('calls update with { reset: false } on a successful save — same as the failure branch already does', async () => {
		const { container } = render(TaxBracketScheduleEditor, { props: editProps });
		const form = container.querySelector('form') as HTMLFormElement;

		await fireEvent.submit(form);
		// Let the mocked async result-callback's microtask complete.
		await Promise.resolve();
		await Promise.resolve();

		expect(updateCalls).toHaveLength(1);
		expect(updateCalls[0]).toEqual({ reset: false });
	});
});
