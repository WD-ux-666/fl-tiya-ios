import { createGuideDiscoveryHandler, createGuideDiscoveryServices } from '../_shared/guide-discovery.mjs';

// verify_jwt=false: this service endpoint verifies its own 256-bit Cron token.
Deno.serve(createGuideDiscoveryHandler(createGuideDiscoveryServices(name => Deno.env.get(name))));
