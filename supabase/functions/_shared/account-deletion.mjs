// Share the bounded request parser, owner-checked Storage manifest and deletion
// orchestration with the original anonymous-only compatibility endpoint.
export {createAccountDeletionHandler,createAccountDeletionServices} from './experience-deletion.mjs';
