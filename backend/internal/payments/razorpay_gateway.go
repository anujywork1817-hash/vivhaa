package payments

import (
	"bytes"
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"net/http"
	"time"
)

const razorpayOrdersURL = "https://api.razorpay.com/v1/orders"
const razorpayPaymentsURL = "https://api.razorpay.com/v1/payments/"

// RazorpayGateway is the real implementation, calling Razorpay's REST API
// directly (Basic Auth with key_id:key_secret) rather than pulling in
// their SDK for a single endpoint.
type RazorpayGateway struct {
	keyID     string
	keySecret string
	client    *http.Client
}

func NewRazorpayGateway(keyID, keySecret string) *RazorpayGateway {
	return &RazorpayGateway{keyID: keyID, keySecret: keySecret, client: &http.Client{Timeout: 10 * time.Second}}
}

func (g *RazorpayGateway) KeyID() string { return g.keyID }

func (g *RazorpayGateway) CreateOrder(ctx context.Context, amountPaise int64, currency, receipt string) (Order, error) {
	body, err := json.Marshal(map[string]any{
		"amount":   amountPaise,
		"currency": currency,
		"receipt":  receipt,
	})
	if err != nil {
		return Order{}, err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, razorpayOrdersURL, bytes.NewReader(body))
	if err != nil {
		return Order{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.SetBasicAuth(g.keyID, g.keySecret)

	resp, err := g.client.Do(req)
	if err != nil {
		return Order{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return Order{}, fmt.Errorf("razorpay create order failed: status %d", resp.StatusCode)
	}

	var parsed struct {
		ID       string `json:"id"`
		Amount   int64  `json:"amount"`
		Currency string `json:"currency"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return Order{}, err
	}

	return Order{ID: parsed.ID, AmountPaise: parsed.Amount, Currency: parsed.Currency}, nil
}

// VerifySignature replicates Razorpay's documented check:
// HMAC-SHA256(order_id + "|" + payment_id, key_secret) == signature.
func (g *RazorpayGateway) VerifySignature(orderID, paymentID, signature string) bool {
	return verifyHMAC(orderID, paymentID, signature, g.keySecret)
}

// FetchPayment calls Razorpay's Fetch Payment API — the independent
// source of truth for what a payment actually settled as, since a valid
// VerifySignature only proves the (orderID, paymentID) pairing is
// genuine, not that the full amount was actually captured.
func (g *RazorpayGateway) FetchPayment(ctx context.Context, paymentID string) (FetchedPayment, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, razorpayPaymentsURL+paymentID, nil)
	if err != nil {
		return FetchedPayment{}, err
	}
	req.SetBasicAuth(g.keyID, g.keySecret)

	resp, err := g.client.Do(req)
	if err != nil {
		return FetchedPayment{}, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return FetchedPayment{}, fmt.Errorf("razorpay fetch payment failed: status %d", resp.StatusCode)
	}

	var parsed struct {
		ID       string `json:"id"`
		OrderID  string `json:"order_id"`
		Amount   int64  `json:"amount"`
		Currency string `json:"currency"`
		Status   string `json:"status"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return FetchedPayment{}, err
	}

	return FetchedPayment{
		ID: parsed.ID, OrderID: parsed.OrderID, AmountPaise: parsed.Amount,
		Currency: parsed.Currency, Status: parsed.Status,
	}, nil
}

// FetchOrderPayments calls Razorpay's "Fetch Payments for an Order" API —
// used for reconciliation, where our own DB never saw a payment_id at
// all (the row is stuck at "created"), so FetchPayment (which needs a
// payment_id) can't help; this looks the order up the other way round.
func (g *RazorpayGateway) FetchOrderPayments(ctx context.Context, orderID string) ([]FetchedPayment, error) {
	url := razorpayOrdersURL + "/" + orderID + "/payments"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.SetBasicAuth(g.keyID, g.keySecret)

	resp, err := g.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= 300 {
		return nil, fmt.Errorf("razorpay fetch order payments failed: status %d", resp.StatusCode)
	}

	var parsed struct {
		Items []struct {
			ID       string `json:"id"`
			OrderID  string `json:"order_id"`
			Amount   int64  `json:"amount"`
			Currency string `json:"currency"`
			Status   string `json:"status"`
		} `json:"items"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return nil, err
	}

	out := make([]FetchedPayment, 0, len(parsed.Items))
	for _, item := range parsed.Items {
		out = append(out, FetchedPayment{
			ID: item.ID, OrderID: item.OrderID, AmountPaise: item.Amount,
			Currency: item.Currency, Status: item.Status,
		})
	}
	return out, nil
}

func computeHMAC(orderID, paymentID, secret string) string {
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(orderID + "|" + paymentID))
	return hex.EncodeToString(mac.Sum(nil))
}

func verifyHMAC(orderID, paymentID, signature, secret string) bool {
	expected := computeHMAC(orderID, paymentID, secret)
	return hmac.Equal([]byte(expected), []byte(signature))
}
