import {createAccountDeletionHandler,createAccountDeletionServices} from '../_shared/account-deletion.mjs';
Deno.serve(createAccountDeletionHandler(createAccountDeletionServices(name=>Deno.env.get(name))));
