import { createCallHandler, createCallServices } from '../_shared/call-service.mjs';

Deno.serve(createCallHandler(createCallServices(name => Deno.env.get(name))));
