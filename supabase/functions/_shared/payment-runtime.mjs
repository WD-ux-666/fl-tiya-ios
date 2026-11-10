import {
  AppleAPIError, fetchAppleTransaction,
  decodeUntrustedTransactionHint, decodeUntrustedNotificationHint,
} from "./apple-api.mjs";
import { PaymentError } from "./payment-validation.mjs";
import { authenticateUser, rpcCall } from "./payment-http.mjs";
import { authenticateNotification } from "./notification-auth.mjs";

function translateAppleError(error) {
  if (error instanceof AppleAPIError && [400, 401, 403, 404, 409, 422, 429, 502, 503].includes(error.status)) {
    return new PaymentError(error.status, error.code);
  }
  return new PaymentError(503, "payment_service_unavailable");
}

export function createPaymentServices(readEnvironment, fetchImpl = fetch) {
  function configuration() {
    const url = readEnvironment("SUPABASE_URL")?.replace(/\/$/, "");
    const serviceRoleKey = readEnvironment("SUPABASE_SERVICE_ROLE_KEY");
    const anonKey = readEnvironment("SUPABASE_ANON_KEY");
    if (!url?.startsWith("https://") || !serviceRoleKey || !anonKey) {
      throw new PaymentError(503, "payment_service_unavailable");
    }
    return { url, serviceRoleKey, anonKey };
  }
  function appleSecrets() {
    return {
      APPLE_IAP_ISSUER_ID: readEnvironment("APPLE_IAP_ISSUER_ID"),
      APPLE_IAP_KEY_ID: readEnvironment("APPLE_IAP_KEY_ID"),
      APPLE_IAP_PRIVATE_KEY: readEnvironment("APPLE_IAP_PRIVATE_KEY"),
    };
  }
  return {
    authenticate: token => authenticateUser(token, configuration(), fetchImpl),
    authenticateNotification: request => authenticateNotification(request, readEnvironment("APPLE_IAP_NOTIFICATION_TOKEN")),
    getSettings: () => rpcCall("payment_server_settings", {}, configuration(), fetchImpl),
    transactionHint(signedTransaction) {
      try { return decodeUntrustedTransactionHint(signedTransaction); }
      catch (error) { throw translateAppleError(error); }
    },
    notificationHint(signedPayload) {
      try { return decodeUntrustedNotificationHint(signedPayload); }
      catch (error) { throw translateAppleError(error); }
    },
    async fetchTransaction(transactionId, settings, environment) {
      try {
        return await fetchAppleTransaction(transactionId, settings, {
          environment, secrets: appleSecrets(), fetchImpl,
        });
      } catch (error) { throw translateAppleError(error); }
    },
    reconcile: parameters => rpcCall("apply_apple_refund", parameters, configuration(), fetchImpl),
    credit: parameters => rpcCall("credit_apple_purchase", parameters, configuration(), fetchImpl),
  };
}
