// Unit test of the CloudFront Function in
// modules/cdn/templates/www_redirect.js.tftpl. Terraform renders the template
// with a test domain, as the cdn module does, and Node runs the handler
// against fake viewer requests.
//
// Usage, from the repository root: node --test "tests/functions/*.test.cjs"
// Needs Node 21 or newer (for the glob), and terraform on the PATH or
// TERRAFORM=<path to terraform>.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const { mkdtempSync, rmSync } = require("node:fs");
const { tmpdir } = require("node:os");
const { join, resolve } = require("node:path");

const template = resolve("modules/cdn/templates/www_redirect.js.tftpl").replaceAll("\\", "/");
const work = mkdtempSync(join(tmpdir(), "www-redirect-"));
let output;
try {
  output = execFileSync(process.env.TERRAFORM || "terraform", ["console", "-no-color"], {
    cwd: work,
    input: `templatefile("${template}", { domain_name = "webschool.example" })`,
    encoding: "utf8",
  });
} finally {
  rmSync(work, { recursive: true, force: true });
}

// terraform console prints a multi-line string between <<EOT and EOT.
const lines = output.replaceAll("\r", "").split("\n");
assert.equal(lines[0], "<<EOT", "terraform console must print the rendered function");
const code = lines.slice(1, lines.indexOf("EOT")).join("\n");
const handler = new Function(`${code}\nreturn handler;`)();

// A viewer request event, in the shape that CloudFront Functions passes.
function viewerRequest(host, uri, query) {
  return {
    request: {
      method: "GET",
      uri,
      headers: { host: { value: host } },
      rawQueryString: () => query,
    },
  };
}

test("www gets a permanent redirect to the same path on the apex", () => {
  const response = handler(viewerRequest("www.webschool.example", "/about/", undefined));
  assert.equal(response.statusCode, 301);
  assert.equal(response.headers.location.value, "https://webschool.example/about/");
});

test("the query string survives the redirect as sent", () => {
  const response = handler(viewerRequest("www.webschool.example", "/", "p=123&s=a%20b"));
  assert.equal(response.headers.location.value, "https://webschool.example/?p=123&s=a%20b");
});

test("a bare question mark is dropped", () => {
  const response = handler(viewerRequest("www.webschool.example", "/", ""));
  assert.equal(response.headers.location.value, "https://webschool.example/");
});

test("the host is matched without regard to case", () => {
  const response = handler(viewerRequest("WWW.WebSchool.example", "/", undefined));
  assert.equal(response.statusCode, 301);
});

test("the apex passes through unchanged", () => {
  const event = viewerRequest("webschool.example", "/about/", "p=1");
  assert.equal(handler(event), event.request);
});

// Only www.<domain>, never a name taken from the request, so the function
// cannot be turned into a redirect to someone else's site.
test("any other host passes through unchanged", () => {
  for (const host of ["d111111abcdef8.cloudfront.net", "www.example.org", "www.webschool.example.org"]) {
    const event = viewerRequest(host, "/", undefined);
    assert.equal(handler(event), event.request, host);
  }
});
