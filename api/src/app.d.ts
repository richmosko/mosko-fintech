// See https://svelte.dev/docs/kit/types#app.d.ts
// for information about these interfaces
import type { SupabaseClient, Session, User } from '@supabase/supabase-js';

declare global {
	namespace App {
		// interface Error {}
		interface Locals {
			// Per-request Supabase client (anon key + RLS), wired in hooks.server.ts.
			supabase: SupabaseClient;
			// Validated session helper — resolves the JWT via getUser() against the
			// Auth server. Use the returned `user` for any authorization decision.
			safeGetSession: () => Promise<{ session: Session | null; user: User | null }>;
		}
		// interface PageData {}
		// interface PageState {}
		// interface Platform {}
	}
}

export {};
