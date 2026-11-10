-- Rollback-only fixtures. Use an authorized database connection after applying
-- the email-password migration. These are Auth schema fixtures, not mail tests.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $test$
declare
  email_user uuid := gen_random_uuid();
  unconfirmed_user uuid := gen_random_uuid();
  phone_user uuid := gen_random_uuid();
  apple_user uuid := gen_random_uuid();
  experience_user uuid := gen_random_uuid();
  password_session uuid := gen_random_uuid();
  another_session uuid := gen_random_uuid();
  otp_session uuid := gen_random_uuid();
  expired_session uuid := gen_random_uuid();
  unconfirmed_session uuid := gen_random_uuid();
  phone_session uuid := gen_random_uuid();
  apple_session uuid := gen_random_uuid();
  apple_password_session uuid := gen_random_uuid();
  experience_session uuid := gen_random_uuid();
  email_address text := 'email-test-' || email_user || '@example.invalid';
  unconfirmed_address text := 'email-test-' || unconfirmed_user || '@example.invalid';
  apple_address text := 'email-test-' || apple_user || '@example.invalid';
  result jsonb;
  reason text;
begin
  insert into auth.users(id, aud, role, is_anonymous, email, email_confirmed_at, raw_user_meta_data)
  values
    (email_user, 'authenticated', 'authenticated', false, email_address, now(), '{}'::jsonb),
    (unconfirmed_user, 'authenticated', 'authenticated', false, unconfirmed_address, null, '{}'::jsonb),
    (phone_user, 'authenticated', 'authenticated', false, null, null, jsonb_build_object('email_verified', true, 'provider', 'email')),
    (apple_user, 'authenticated', 'authenticated', false, apple_address, now(), '{}'::jsonb),
    (experience_user, 'authenticated', 'authenticated', true, null, null, jsonb_build_object('experience_email', email_address));

  insert into auth.identities(provider_id, user_id, identity_data, provider)
  values
    (email_user::text, email_user, jsonb_build_object('sub', email_user, 'email', email_address), 'email'),
    (unconfirmed_user::text, unconfirmed_user, jsonb_build_object('sub', unconfirmed_user, 'email', unconfirmed_address), 'email'),
    (phone_user::text, phone_user, jsonb_build_object('sub', phone_user), 'phone'),
    (apple_user::text, apple_user, jsonb_build_object('sub', apple_user, 'email', apple_address), 'apple');

  insert into auth.sessions(id, user_id, not_after)
  values
    (password_session, email_user, null),
    (another_session, email_user, null),
    (otp_session, email_user, null),
    (expired_session, email_user, now() - interval '1 minute'),
    (unconfirmed_session, unconfirmed_user, null),
    (phone_session, phone_user, null),
    (apple_session, apple_user, null),
    (apple_password_session, apple_user, null),
    (experience_session, experience_user, null);

  insert into auth.mfa_amr_claims(id, session_id, authentication_method, created_at, updated_at)
  select gen_random_uuid(), session_id, method, now(), now() from (values
    (password_session, 'password'), (another_session, 'password'), (otp_session, 'otp'),
    (expired_session, 'password'), (unconfirmed_session, 'password'), (phone_session, 'password'),
    (apple_session, 'oauth'), (apple_password_session, 'password'), (experience_session, 'anonymous')
  ) fixtures(session_id, method);

  assert exists(select 1 from private.accounts where user_id = email_user and cohort = 'production' and not is_experience), 'signup must provision a separate full account';
  assert exists(select 1 from public.profiles where id = email_user), 'signup must provision a profile';
  assert exists(select 1 from public.wallets where user_id = email_user), 'signup must provision a wallet';
  assert private.call_session_active(email_user, password_session), 'confirmed email and password must be eligible';
  assert not private.call_session_active(email_user, otp_session), 'email confirmation or OTP alone must not unlock the app';
  assert not private.call_session_active(email_user, expired_session), 'expired password session must be denied';
  assert not private.call_session_active(email_user, experience_session), 'another user session must be denied';
  assert not private.call_session_active(unconfirmed_user, unconfirmed_session), 'unconfirmed email must be denied';
  assert not private.call_session_active(phone_user, phone_session), 'phone password plus editable metadata must be denied';
  assert private.call_session_active(apple_user, apple_session), 'Apple OAuth must remain eligible';
  assert not private.call_session_active(apple_user, apple_password_session), 'Apple-only identity must not stand in for email identity';
  assert private.call_session_active(experience_user, experience_session), 'existing anonymous experience must remain eligible';
  assert not private.call_session_active(experience_user, password_session), 'matching anonymous email metadata must not link accounts';

  insert into auth.identities(provider_id, user_id, identity_data, provider)
  values(apple_user::text, apple_user, jsonb_build_object('sub', apple_user, 'email', apple_address), 'email');
  assert private.call_session_active(apple_user, apple_password_session), 'linked account can use a real confirmed email and password';

  perform set_config('request.jwt.claims', jsonb_build_object('sub', email_user, 'role', 'authenticated', 'session_id', password_session, 'is_anonymous', false)::text, true);
  set local role authenticated;
  result := public.session_context();
  assert result ->> 'user_id' = email_user::text and result ->> 'cohort' = 'production' and result ->> 'is_experience' = 'false', 'client RPC must accept password sessions without marking them as experience';
  result := public.payment_state();
  assert result ->> 'purchases_enabled' = 'false' and result ->> 'purchase_unavailable_reason' = 'apple_sign_in_required', 'Apple-only checkout stays unavailable for password sessions';
  reset role;

  perform set_config('request.jwt.claims', jsonb_build_object('sub', email_user, 'role', 'authenticated', 'session_id', otp_session, 'is_anonymous', false, 'amr', jsonb_build_array(jsonb_build_object('method', 'password')))::text, true);
  set local role authenticated;
  begin
    perform public.session_context();
    raise exception 'JWT test claim bypassed server session AMR';
  exception when insufficient_privilege then null;
  end;
  reset role;

  set local role service_role;
  begin
    perform public.prepare_account_deletion(email_user, otp_session);
    raise exception 'OTP session was allowed to delete an email account';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.prepare_account_deletion(apple_user, apple_password_session);
    raise exception 'Password session bypassed Apple revocation protection';
  exception when insufficient_privilege then
    get stacked diagnostics reason = message_text;
    assert reason = 'apple_revocation_configuration_required', 'linked Apple account must fail before mutation';
  end;
  begin
    perform public.prepare_experience_deletion(email_user, password_session);
    raise exception 'legacy anonymous-only endpoint accepted a password account';
  exception when insufficient_privilege then null;
  end;
  reset role;
  assert (select state = 'active' from private.accounts where user_id = apple_user), 'linked account remained active';

  set local role service_role;
  result := public.prepare_account_deletion(email_user, password_session);
  assert result ->> 'user_id' = email_user::text, 'password account must support self-service deletion';
  reset role;
  assert not private.call_session_active(email_user, password_session), 'deleting account must lose app access';
  assert not exists(select 1 from auth.sessions where id = another_session), 'other sessions must be revoked';

  set local role service_role;
  perform public.prepare_account_deletion(email_user, password_session);
  result := public.finish_account_deletion(email_user, password_session);
  assert result = '{"deleted":true}'::jsonb, 'same password session can retry and finish deletion';
  reset role;
  assert not exists(select 1 from auth.users where id = email_user), 'deleted Auth record must be removed';
  assert exists(select 1 from auth.users where id = experience_user), 'independent anonymous account with matching metadata must remain';
end $test$;

rollback;
