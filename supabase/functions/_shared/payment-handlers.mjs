import {
  PaymentError, requireSettings, validateTransaction, reconciliationFor, validateCreditResult,
} from "./payment-validation.mjs";
import { bearerToken, readPaymentJSON, jsonResponse, errorResponse } from "./payment-http.mjs";

function requirePOST(request) {
  if (request.method !== "POST") return jsonResponse(405, { error: "method_not_allowed" }, { Allow: "POST" });
  return null;
}

function hintEnvironment(hint, settings) {
  const environment = hint.environment ?? settings.store_environment;
  if (!["Production", "Sandbox"].includes(environment) || (environment === "Sandbox" && !settings.allow_sandbox)) {
    throw new PaymentError(422, "invalid_transaction");
  }
  return environment;
}

export function createPurchaseHandler(services) {
  return async function purchase(request) {
    const methodError = requirePOST(request);
    if (methodError) return methodError;
    try {
      const token = bearerToken(request.headers);
      const signedTransaction = await readPaymentJSON(request, "signed_transaction", 65536);
      const actor = await services.authenticate(token);
      // Disabling new checkout must not strand an already-paid transaction.
      const settings = requireSettings(await services.getSettings(), false);
      // This hint never supplies ownership, value or revocation state. The only
      // trusted transaction facts come from the fixed Apple HTTPS API endpoint.
      const hint = services.transactionHint(signedTransaction);
      const environment = hintEnvironment(hint, settings);
      if (environment !== settings.store_environment) throw new PaymentError(409, "transaction_environment_mismatch");
      const authoritativeTransaction = await services.fetchTransaction(hint.transactionId, settings, environment);
      const transaction = validateTransaction(authoritativeTransaction, settings, actor.userId, environment);
      if (transaction.transactionId !== hint.transactionId) throw new PaymentError(422, "invalid_transaction");
      // Apply both refund and active snapshots before credit. Active snapshots
      // resolve reversals, but the RPC cannot credit an undelivered transaction.
      await services.reconcile(reconciliationFor(transaction));
      const credited = await services.credit({
        target_user_id: actor.userId, target_session_id: actor.sessionId,
        apple_environment: transaction.environment, apple_transaction_id: transaction.transactionId,
        apple_product_id: transaction.productId, apple_account_token: transaction.accountToken,
      });
      return jsonResponse(200, validateCreditResult(credited, transaction.transactionId, transaction.environment));
    } catch (error) { return errorResponse(error); }
  };
}

export function createNotificationHandler(services) {
  return async function notification(request) {
    const methodError = requirePOST(request);
    if (methodError) return methodError;
    try {
      await services.authenticateNotification(request);
      const signedPayload = await readPaymentJSON(request, "signedPayload", 131072);
      // Incoming notifications are untrusted lookup triggers. Do not use their
      // notificationType, UUID, signedDate, account token or revocation claims.
      // Always obtain the current state directly from Apple's authenticated API.
      const hint = services.notificationHint(signedPayload);
      const settings = requireSettings(await services.getSettings(), false);
      const environment = hintEnvironment(hint, settings);
      const authoritativeTransaction = await services.fetchTransaction(hint.transactionId, settings, environment);
      const transaction = validateTransaction(authoritativeTransaction, settings, undefined, environment);
      if (transaction.transactionId !== hint.transactionId) throw new PaymentError(422, "invalid_transaction");
      await services.reconcile(reconciliationFor(transaction));
      return jsonResponse(200, { received: true });
    } catch (error) { return errorResponse(error); }
  };
}
