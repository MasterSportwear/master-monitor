import { createHandler } from './handler.js';
Deno.serve(createHandler({
  url: Deno.env.get('SUPABASE_URL'),
  serviceKey: Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'),
  origin: Deno.env.get('MM_ALLOWED_ORIGIN') ?? 'https://mastersportwear.github.io',
}));
