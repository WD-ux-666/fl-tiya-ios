import policy from './policy.json' with { type: 'json' };
import { documents } from './documents.mjs';
import { createLegalDocumentsHandler } from '../_shared/legal-documents.mjs';
import { createPrivacyPolicyHandler } from '../_shared/privacy-policy.mjs';

// The text, metadata and PDFs must be accessible before sign-in.
Deno.serve(createLegalDocumentsHandler({
  baseURL: Deno.env.get('SUPABASE_URL')!,
  documents,
  legacyHandler: createPrivacyPolicyHandler(policy),
}));
