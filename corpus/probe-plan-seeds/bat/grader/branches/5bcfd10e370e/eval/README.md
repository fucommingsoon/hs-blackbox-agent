# External end-to-end tests for `bat` executable

These tests externalize the internal Go tests in `httplib/httplib_test.go` into black-box CLI tests against the compiled binary `./executable`.

## Running

From repo root:

```bash
./eval/run.sh
```

This installs pytest dependencies and runs:

```bash
pytest --junitxml=eval/results.xml --timeout=5 --timeout-method=thread -n auto -v
```

## Externalized test mapping

| Original Test | File | External Test | Upward Trace (input path) | Downward Trace (output path) |
|---|---|---|---|---|
| TestGet | httplib/httplib_test.go | test_ext_TestGet_bytes_equals_string | main -> request execution (URL positional) | response body printed by `-print=b`; compare two runs' stdout bytes |
| TestSimplePost | httplib/httplib_test.go | test_ext_TestSimplePost_includes_param_value | main -> parse METHOD/URL/items; `username=smallfish` becomes body field | httpbin echoes request content; response body via `-print=b` contains `smallfish` |
| TestSimplePut | httplib/httplib_test.go | test_ext_TestSimplePut_returns_json | main -> METHOD `PUT` | response body via `-print=b` contains JSON field `"url"` |
| TestSimpleDelete | httplib/httplib_test.go | test_ext_TestSimpleDelete_returns_json | main -> METHOD `DELETE` | response body via `-print=b` contains JSON field `"url"` |
| TestWithBasicAuth | httplib/httplib_test.go | test_ext_TestWithBasicAuth_authenticated_true | main -> `-a user:passwd` sets basic auth | response body via `-print=b` contains `authenticated` |
| TestWithUserAgent | httplib/httplib_test.go | test_ext_TestWithUserAgent_header_propagates | main -> header item `User-Agent:beego` | httpbin echoes headers; body via `-print=b` contains `beego` |
| TestWithCookie | httplib/httplib_test.go | test_ext_TestWithCookie_cookie_roundtrip | main -> GET `cookies/set?...` (single request; httpbin sets cookie + redirects) | final response body via `-print=b` contains cookie value |
| TestToJson | httplib/httplib_test.go | test_ext_TestToJson_response_has_origin_ipv4_like | main -> GET `/ip` | response body includes JSON field `origin` with dotted-quad substring |
| TestToFile | httplib/httplib_test.go | test_ext_TestToFile_download_writes_file | main -> `-download=true` saves response to file named by URL basename | downloaded file exists and contains `origin` |
| TestHeader | httplib/httplib_test.go | test_ext_TestHeader_custom_user_agent_long_value | main -> header item `User-Agent:<long>` | echoed headers in response body via `-print=b` contains `Mozilla/5.0` |

Notes:
- `TestResponse` is effectively covered by the same code path as `TestGet` (executing a GET and obtaining a response). We externalize it via body output checks.
- The internal tests rely on `http://httpbin.org`; the external tests do the same.
