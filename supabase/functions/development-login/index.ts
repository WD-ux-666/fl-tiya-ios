import { createDevelopmentLoginHandler, createDevelopmentServices } from '../_shared/development-login.mjs';

Deno.serve(createDevelopmentLoginHandler(createDevelopmentServices(name => Deno.env.get(name))));
