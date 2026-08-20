package calls

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"strconv"
	"time"
)

// turnCredentialTTL is how long a generated TURN credential stays valid.
// Short-lived on purpose — these are handed to the client in an API
// response, not a secret the client is trusted to hold onto.
const turnCredentialTTL = 4 * time.Hour

// generateTURNCredentials implements coturn's standard "TURN REST API"
// time-limited credential mechanism: username is "<unix-expiry>:<label>",
// password is base64(HMAC-SHA1(secret, username)). coturn is configured
// with the same shared secret (its `static-auth-secret` setting) and
// recomputes this HMAC itself to validate a credential — no password is
// ever stored, shared out of band, or hardcoded on the client.
func generateTURNCredentials(secret, label string, ttl time.Duration) (username, credential string) {
	expiry := time.Now().Add(ttl).Unix()
	username = strconv.FormatInt(expiry, 10) + ":" + label

	mac := hmac.New(sha1.New, []byte(secret))
	mac.Write([]byte(username))
	credential = base64.StdEncoding.EncodeToString(mac.Sum(nil))
	return username, credential
}
