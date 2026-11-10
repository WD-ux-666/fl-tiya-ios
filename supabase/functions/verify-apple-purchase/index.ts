import { createPurchaseHandler } from "../_shared/payment-handlers.mjs";
import { createPaymentServices } from "../_shared/payment-runtime.mjs";

Deno.serve(createPurchaseHandler(createPaymentServices(name => Deno.env.get(name))));
