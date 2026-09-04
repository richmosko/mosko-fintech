// new-page.dom.test.ts — accounts/new/+page.svelte, SELF-267 Sec joint-review note (non-blocking,
// same PR): the create-then-update path in +page.server.ts can commit the account and still fail
// the SUBSEQUENT tax_jurisdiction UPDATE (409 conflict on the uniq index, or another 422) — those
// two fail() branches echo `accountId` so the caller can route the user to the account that
// already exists. Sec found the field was produced and asserted in new.server.test.ts but never
// read by this page. This suite pins the render-side consumption: the notice + link appear only
// when `form.accountId` is present, never on an ordinary field-only validation failure.
//
// Mirrors the established +page.svelte DOM-test precedent (cash-flow-page.dom.test.ts,
// us-equity-page.dom.test.ts): @testing-library/svelte render() against the route component
// directly, no server/loader involved.
//
// @vitest-environment jsdom

import { describe, it, expect } from 'vitest';
import { render } from '@testing-library/svelte';
import NewAccountPage from './+page.svelte';
import type { ActionData } from './$types';

// The `as ActionData` casts below are load-bearing, not decoration: `accountId` comes off an
// untyped (`any`) Supabase `.rpc()` result in +page.server.ts, which makes TS's control-flow
// return-type inference for `actions.default` treat the accountId-carrying fail() branches as
// redundant subtypes of the plain {errors, values} branches and DROP `accountId` from the
// inferred `ActionData` union entirely (verified via `tsc` probes — the generated proxy's own
// inferred function type only carries 2 of the 5 fail() shapes). `'accountId' in form` still
// narrows fine in +page.svelte itself (an `in`-check degrades to an `unknown`-valued intersection
// rather than erroring), but constructing a fixture object literal WITH `accountId` inline hits
// TS's excess-property check against that narrowed union — hence the assertion, not a plain
// annotation (which would hit the same check).
describe('accounts/new/+page.svelte — SELF-267 create-then-update accountId notice', () => {
	it('renders the notice + link to the created account when form.accountId is present', () => {
		const { getByRole, getByText } = render(NewAccountPage, {
			props: {
				form: {
					errors: {
						tax_jurisdiction: ['Another account is already designated as your tax authority ledger.']
					},
					values: {},
					accountId: 42
				} as ActionData
			}
		});

		// The notice's own text is split across text nodes by the <a> link, so getByText's exact
		// match is done against the containing element's textContent rather than the link's own
		// accessible name query above.
		const link = getByRole('link', { name: 'Go to the account' });
		expect(link.getAttribute('href')).toBe('/accounts/42');
		expect(link.closest('p')?.textContent).toContain(
			'The account was created, but the tax authority designation could not be saved.'
		);
		// The field error still renders inline via TaxJurisdictionField — the notice is additive,
		// not a replacement for it.
		expect(
			getByText('Another account is already designated as your tax authority ledger.')
		).toBeTruthy();
	});

	it('does not render the notice or link on an ordinary field-only validation failure', () => {
		const { queryByRole, queryByText } = render(NewAccountPage, {
			props: {
				form: {
					errors: { tax_jurisdiction: ['Select a tax jurisdiction.'] },
					values: {}
				}
			}
		});

		expect(
			queryByText('The account was created, but the tax authority designation could not be saved.')
		).toBeNull();
		expect(queryByRole('link', { name: 'Go to the account' })).toBeNull();
	});

	it('does not render the notice when form is null (initial load)', () => {
		const { queryByRole } = render(NewAccountPage, { props: { form: null } });
		expect(queryByRole('link', { name: 'Go to the account' })).toBeNull();
	});
});
