API Example
===========

This describes a relatively basic API usage pattern. It assumes you have an instance available to test against.

To authenticate:
```
curl -s -u admin:password -X POST localhost:8081/api/v3/auth/login
```
Returns a payload of:
```
{
  "token": "Q2DbSeycQ20Up/Z6RC4M9w==",
  "accessLevel": "admin",
  "userID": "0BDBE4EA-7003-488D-ACA1-A000D5F2C1CC"
}
```
The token can then be presented in other requests. Heads up! If the token contains a `/` then curl may insert extra escape characters in the response to stdout. It is suggested to process the response through `jq` or similar. https://stackoverflow.com/questions/1580647/json-why-are-forward-slashes-escaped

```
curl -s --oauth2-bearer "Q2DbSeycQ20Up/Z6RC4M9w==" localhost:8081/api/v3/user/whoami | jq
{
  "username": "admin",
  "isLoggedIn": true,
  "userID": "0BDBE4EA-7003-488D-ACA1-A000D5F2C1CC"
}
```

The `--oauth2-bearer` is a simplified way of saying `-H 'Authorization: Bearer Q2DbSeycQ20Up/Z6RC4M9w==` with curl.

To create content or otherwise POST data to an endpoint:
```
curl -H 'Content-Type: application/json' -d '{"text": "test", images: [], postAsModerator: false, postAsTwitarrTeam: false}' -X POST --oauth2-bearer "Q2DbSeycQ20Up/Z6RC4M9w==" localhost:8081/api/v3/forum/E8FB126A-32F8-4FFF-B758-E570C3C5AAF8/create
```