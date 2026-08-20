// Package groq is a minimal client for Groq's OpenAI-compatible chat
// completions API (https://api.groq.com/openai/v1/chat/completions) — just
// enough to send a message list and get a reply, no streaming or tool use.
package groq

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"time"
)

const apiURL = "https://api.groq.com/openai/v1/chat/completions"

var ErrNotConfigured = errors.New("AI assistant is not configured")

type Message struct {
	Role    string `json:"role"` // "system", "user", or "assistant"
	Content string `json:"content"`
}

type Client struct {
	apiKey     string
	model      string
	httpClient *http.Client
}

// NewClient builds a client. apiKey may be empty — Configured() reports
// false in that case, and Complete returns ErrNotConfigured rather than
// making a doomed request.
func NewClient(apiKey, model string) *Client {
	if model == "" {
		model = "llama-3.3-70b-versatile"
	}
	return &Client{
		apiKey:     apiKey,
		model:      model,
		httpClient: &http.Client{Timeout: 20 * time.Second},
	}
}

func (c *Client) Configured() bool {
	return c.apiKey != ""
}

type chatRequest struct {
	Model       string    `json:"model"`
	Messages    []Message `json:"messages"`
	Temperature float64   `json:"temperature"`
	MaxTokens   int       `json:"max_tokens"`
}

type chatResponse struct {
	Choices []struct {
		Message Message `json:"message"`
	} `json:"choices"`
	Error *struct {
		Message string `json:"message"`
	} `json:"error"`
}

// Complete sends the message list and returns the assistant's reply text.
func (c *Client) Complete(ctx context.Context, messages []Message) (string, error) {
	if !c.Configured() {
		return "", ErrNotConfigured
	}

	body, err := json.Marshal(chatRequest{
		Model:       c.model,
		Messages:    messages,
		Temperature: 0.7,
		MaxTokens:   600,
	})
	if err != nil {
		return "", err
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, apiURL, bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+c.apiKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", err
	}

	var parsed chatResponse
	if err := json.Unmarshal(respBody, &parsed); err != nil {
		return "", fmt.Errorf("groq: unexpected response: %s", string(respBody))
	}
	if resp.StatusCode != http.StatusOK {
		if parsed.Error != nil {
			return "", fmt.Errorf("groq: %s", parsed.Error.Message)
		}
		return "", fmt.Errorf("groq: request failed with status %d", resp.StatusCode)
	}
	if len(parsed.Choices) == 0 {
		return "", errors.New("groq: no completion returned")
	}
	return parsed.Choices[0].Message.Content, nil
}
