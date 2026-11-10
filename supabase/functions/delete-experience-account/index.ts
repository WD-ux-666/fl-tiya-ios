import {createExperienceDeletionHandler,createExperienceDeletionServices} from '../_shared/experience-deletion.mjs';
Deno.serve(createExperienceDeletionHandler(createExperienceDeletionServices(name=>Deno.env.get(name))));
