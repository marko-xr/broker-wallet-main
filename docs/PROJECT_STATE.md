# Project state

Broker Wallet is in a staged Firebase → Supabase migration. This is not a full Supabase cutover; Firebase behavior remains for sections not yet migrated.

The existing-account Supabase Email Change flow is VERIFIED_RUNTIME. It failed
its first real-device test, was fixed, and the product owner has since confirmed
a successful end-to-end change — including the Secure Email Change two-mailbox
flow — on a real device. It derives pending state from Supabase Auth, keeps
`auth.users.email` canonical until confirmation, reuses the existing auth
callback, and relies on the server identity-sync trigger for
`public.profiles.email`.

The Edit Profile screen's UI polish is VERIFIED_RUNTIME / accepted by the
product owner on a real device in both English and Arabic, with name save,
profile image save, Email Change entry and Add Phone entry all confirmed
working and no reported regression.

Phone Login and Phone Sign-up UI is present and selectable on both screens at
the product owner's request, and that restoration is VERIFIED_UI. Phone
authentication itself is NOT implemented and NOT runtime verified in Supabase
mode: it is legacy-Firebase only, and the screens say so in EN/AR. The
signed-in Add Phone / verification flow is preserved, and real UAE SMS delivery
remains externally deferred.
