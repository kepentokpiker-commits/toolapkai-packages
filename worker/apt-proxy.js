// Cloudflare Worker (gratis): jembatan antara apt dan GitHub.
//  /<repo>/dists/...        -> indeks di branch apt-repo (raw.githubusercontent)
//  /<repo>/pool/<tag>/<.deb> -> berkas di GitHub Release
// Ganti OWNER dan REPO, lalu deploy di dashboard Cloudflare Workers.
const OWNER = "kepentokpiker-commits";
const REPO = "toolapkai-packages";
const BRANCH = "apt-repo";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    const deb = url.pathname.match(/^\/([^/]+)\/pool\/([^/]+)\/([A-Za-z0-9._-]+\.deb)$/);
    if (deb) {
      return Response.redirect(
        `https://github.com/${OWNER}/${REPO}/releases/download/${deb[2]}/${deb[3]}`, 302);
    }
    if (/^\/[^/]+\/dists\//.test(url.pathname) || url.pathname === "/toolapkai.gpg") {
      const raw = `https://raw.githubusercontent.com/${OWNER}/${REPO}/${BRANCH}${url.pathname}`;
      const r = await fetch(raw, { cf: { cacheTtl: 60 } });
      return new Response(r.body, { status: r.status, headers: r.headers });
    }
    return new Response("not found", { status: 404 });
  },
};
