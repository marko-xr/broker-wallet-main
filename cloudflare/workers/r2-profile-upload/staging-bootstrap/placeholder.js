// First-time bootstrap placeholder for `r2-profile-upload-staging`.
//
// Exists only so the staging Worker name can hold its secrets before the real
// code is deployed (`wrangler deploy --env staging` refuses to run until every
// required secret exists). It has no bindings, no triggers, no route and no
// workers.dev URL, reads no secret, and calls nothing: every request gets 404.
export default {
  async fetch() {
    return new Response(null, { status: 404 });
  },
};
