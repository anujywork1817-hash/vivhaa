// Package elasticsearch wraps the official Elasticsearch client with the
// small set of generic operations the app needs (index/get/delete/search
// a JSON document by ID). Domain-specific query building (e.g. profile
// filters) lives in the calling package, not here.
package elasticsearch

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"strings"

	esv8 "github.com/elastic/go-elasticsearch/v8"

	"matrimony-backend/configs"
)

type Client struct {
	es *esv8.Client
}

func NewClient(cfg configs.ElasticsearchConfig) (*Client, error) {
	es, err := esv8.NewClient(esv8.Config{
		Addresses: cfg.Addresses,
		// The client's connection pool otherwise updates itself from
		// whatever address the cluster's own nodes-info response reports
		// for each node — inside Docker, Elasticsearch commonly reports
		// itself as 127.0.0.1, which is meaningless to a remote client
		// (works fine when the API and ES share one host, breaks the
		// instant they're on separate machines like this AWS deployment:
		// the client silently switches from the configured address to
		// "127.0.0.1:9200" and every subsequent request fails with
		// "connection refused"). Disabling discovery keeps it pinned to
		// exactly the Addresses given here.
		DiscoverNodesOnStart:  false,
		DiscoverNodesInterval: 0,
	})
	if err != nil {
		return nil, fmt.Errorf("create elasticsearch client: %w", err)
	}
	return &Client{es: es}, nil
}

// Ping confirms the cluster is reachable, for use by the app's readiness
// check (see the 2026-08-24 incident where Elasticsearch was unreachable
// from the API for hours — a missing security-group rule — and nothing
// caught it until a real /search/profiles request timed out).
func (c *Client) Ping(ctx context.Context) error {
	res, err := c.es.Ping(c.es.Ping.WithContext(ctx))
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.IsError() {
		return fmt.Errorf("elasticsearch ping: status %d", res.StatusCode)
	}
	return nil
}

// EnsureIndex creates the index with the given mapping if it doesn't
// already exist. mapping is the raw JSON body for the create-index call.
func (c *Client) EnsureIndex(ctx context.Context, index string, mapping []byte) error {
	exists, err := c.es.Indices.Exists([]string{index}, c.es.Indices.Exists.WithContext(ctx))
	if err != nil {
		return err
	}
	defer exists.Body.Close()
	if exists.StatusCode == 200 {
		return nil
	}

	res, err := c.es.Indices.Create(index,
		c.es.Indices.Create.WithContext(ctx),
		c.es.Indices.Create.WithBody(bytes.NewReader(mapping)),
	)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.IsError() {
		body, _ := io.ReadAll(res.Body)
		return fmt.Errorf("create index %q: %s", index, string(body))
	}
	return nil
}

func (c *Client) IndexDocument(ctx context.Context, index, docID string, doc any) error {
	body, err := json.Marshal(doc)
	if err != nil {
		return err
	}

	res, err := c.es.Index(
		index,
		bytes.NewReader(body),
		c.es.Index.WithContext(ctx),
		c.es.Index.WithDocumentID(docID),
	)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.IsError() {
		respBody, _ := io.ReadAll(res.Body)
		return fmt.Errorf("index document %q: %s", docID, string(respBody))
	}
	return nil
}

func (c *Client) DeleteDocument(ctx context.Context, index, docID string) error {
	res, err := c.es.Delete(index, docID, c.es.Delete.WithContext(ctx))
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.IsError() && res.StatusCode != 404 {
		respBody, _ := io.ReadAll(res.Body)
		return fmt.Errorf("delete document %q: %s", docID, string(respBody))
	}
	return nil
}

// SearchResult is the subset of Elasticsearch's search response shape
// callers need: matched document sources plus the total hit count.
type SearchResult struct {
	Total int
	Hits  []json.RawMessage
}

// Search runs a raw query DSL body against index and returns document
// sources (not the full ES envelope).
func (c *Client) Search(ctx context.Context, index string, query map[string]any) (SearchResult, error) {
	body, err := json.Marshal(query)
	if err != nil {
		return SearchResult{}, err
	}

	res, err := c.es.Search(
		c.es.Search.WithContext(ctx),
		c.es.Search.WithIndex(index),
		c.es.Search.WithBody(bytes.NewReader(body)),
		c.es.Search.WithTrackTotalHits(true),
	)
	if err != nil {
		return SearchResult{}, err
	}
	defer res.Body.Close()
	if res.IsError() {
		respBody, _ := io.ReadAll(res.Body)
		return SearchResult{}, fmt.Errorf("search %q: %s", index, string(respBody))
	}

	var parsed struct {
		Hits struct {
			Total struct {
				Value int `json:"value"`
			} `json:"total"`
			Hits []struct {
				Source json.RawMessage `json:"_source"`
			} `json:"hits"`
		} `json:"hits"`
	}
	if err := json.NewDecoder(res.Body).Decode(&parsed); err != nil {
		return SearchResult{}, err
	}

	result := SearchResult{Total: parsed.Hits.Total.Value, Hits: make([]json.RawMessage, 0, len(parsed.Hits.Hits))}
	for _, h := range parsed.Hits.Hits {
		result.Hits = append(result.Hits, h.Source)
	}
	return result, nil
}

// IsNotFoundIndexError reports whether err looks like a "no such index"
// error, so callers can decide whether to treat a fresh, empty index the
// same as a genuinely empty search result.
func IsNotFoundIndexError(err error) bool {
	return err != nil && strings.Contains(err.Error(), "index_not_found_exception")
}
