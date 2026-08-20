package auth

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"math/big"
)

const otpLength = 6

// generateOTPCode returns a random N-digit numeric code as a string.
func generateOTPCode() (string, error) {
	max := big.NewInt(1)
	for i := 0; i < otpLength; i++ {
		max.Mul(max, big.NewInt(10))
	}
	n, err := rand.Int(rand.Reader, max)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("%0*d", otpLength, n), nil
}

func hashOTP(code string) string {
	sum := sha256.Sum256([]byte(code))
	return hex.EncodeToString(sum[:])
}

func compareOTP(code, hash string) bool {
	return subtle.ConstantTimeCompare([]byte(hashOTP(code)), []byte(hash)) == 1
}
