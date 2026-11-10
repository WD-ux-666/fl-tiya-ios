import { createNotificationHandler } from "../_shared/payment-handlers.mjs";
import { createPaymentServices } from "../_shared/payment-runtime.mjs";

Deno.serve(createNotificationHandler(createPaymentServices(name => Deno.env.get(name))));
