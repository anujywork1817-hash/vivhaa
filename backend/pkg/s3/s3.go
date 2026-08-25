// Package s3 wraps the AWS SDK v2 S3 client for object storage (profile
// photos, verification docs). Pointing Config.Endpoint at a local MinIO
// instance makes this usable without real AWS credentials in dev.
package s3

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
	smithy "github.com/aws/smithy-go"

	"matrimony-backend/configs"
)

// ErrBucketNotFound distinguishes a missing/un-provisioned bucket from a
// generic storage failure. Surfaced so callers can log and respond with a
// specific, actionable message instead of a bare 500 — see the 2026-08-24
// incident where a never-provisioned "matrimony-verification-docs" bucket
// on a fresh environment made every ID-verification upload fail with a
// generic "internal_error" that took manual log-diving to diagnose.
var ErrBucketNotFound = errors.New("storage bucket not found")

// wrapBucketError checks whether err is S3's "no such bucket" response and,
// if so, wraps it in ErrBucketNotFound naming the bucket; otherwise it
// passes err through wrapped with the given context message.
func wrapBucketError(err error, msg, bucket string) error {
	var apiErr smithy.APIError
	if errors.As(err, &apiErr) && apiErr.ErrorCode() == "NoSuchBucket" {
		return fmt.Errorf("%w: bucket %q: %s", ErrBucketNotFound, bucket, msg)
	}
	return fmt.Errorf("%s: %w", msg, err)
}

type Client struct {
	s3            *s3.Client
	presign       *s3.PresignClient
	bucket        string // public-read: profile photos
	publicBaseURL string
	docsBucket    string // private: verification documents
}

func NewClient(ctx context.Context, cfg configs.S3Config) (*Client, error) {
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx,
		awsconfig.WithRegion(cfg.Region),
		awsconfig.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(cfg.AccessKey, cfg.SecretKey, "")),
	)
	if err != nil {
		return nil, fmt.Errorf("load aws config: %w", err)
	}

	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		if cfg.Endpoint != "" {
			o.BaseEndpoint = aws.String(cfg.Endpoint)
		}
		o.UsePathStyle = cfg.UsePathStyle
	})

	// Presigned URLs are handed to a browser outside the API container's
	// own network, so they must be signed against an address that browser
	// can reach — which may differ from Endpoint (see S3Config.PublicEndpoint).
	publicEndpoint := cfg.PublicEndpoint
	if publicEndpoint == "" {
		publicEndpoint = cfg.Endpoint
	}
	presignClient := client
	if publicEndpoint != cfg.Endpoint {
		presignClient = s3.NewFromConfig(awsCfg, func(o *s3.Options) {
			if publicEndpoint != "" {
				o.BaseEndpoint = aws.String(publicEndpoint)
			}
			o.UsePathStyle = cfg.UsePathStyle
		})
	}

	return &Client{
		s3:            client,
		presign:       s3.NewPresignClient(presignClient),
		bucket:        cfg.Bucket,
		publicBaseURL: cfg.PublicBaseURL,
		docsBucket:    cfg.DocsBucket,
	}, nil
}

// BucketsReachable confirms both the public photos bucket and the private
// verification-docs bucket exist and are reachable — read-only, unlike
// EnsureBucket/EnsureDocsBucket, so it's safe to call on every readiness
// probe rather than only at APP_ENV=dev startup. Returns a descriptive
// error naming whichever bucket is missing, since "storage unavailable"
// alone sent someone down an hour of log-diving on 2026-08-24 to learn it
// was specifically matrimony-verification-docs that had never been created.
func (c *Client) BucketsReachable(ctx context.Context) error {
	for _, bucket := range []string{c.bucket, c.docsBucket} {
		if _, err := c.s3.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(bucket)}); err != nil {
			return fmt.Errorf("bucket %q unreachable: %w", bucket, err)
		}
	}
	return nil
}

// EnsureBucket creates the configured public profile-photos bucket if it
// doesn't already exist. Intended for local/dev use against MinIO; in
// staging/prod the bucket (and its public-read policy) is expected to be
// provisioned via infra tooling.
func (c *Client) EnsureBucket(ctx context.Context) error {
	return c.ensureBucket(ctx, c.bucket)
}

// EnsureDocsBucket creates the private verification-documents bucket if it
// doesn't already exist. Unlike EnsureBucket, this must NEVER be given a
// public-read policy — access is exclusively via short-lived presigned
// URLs (see PresignDocURL). A freshly created S3/MinIO bucket is private
// by default, so this intentionally does nothing beyond CreateBucket.
func (c *Client) EnsureDocsBucket(ctx context.Context) error {
	return c.ensureBucket(ctx, c.docsBucket)
}

func (c *Client) ensureBucket(ctx context.Context, bucket string) error {
	_, err := c.s3.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(bucket)})
	if err == nil {
		return nil
	}
	_, err = c.s3.CreateBucket(ctx, &s3.CreateBucketInput{Bucket: aws.String(bucket)})
	return err
}

// Upload puts an object in the public profile-photos bucket and returns
// its public URL.
func (c *Client) Upload(ctx context.Context, key string, body []byte, contentType string) (string, error) {
	_, err := c.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(body),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return "", wrapBucketError(err, "upload object", c.bucket)
	}
	return fmt.Sprintf("%s/%s", c.publicBaseURL, key), nil
}

// PublicURL builds key's public URL from the *current* publicBaseURL
// config rather than trusting whatever was stored at upload time — a
// photo uploaded while S3_PUBLIC_BASE_URL (or the S3_PUBLIC_HOST it can be
// derived from) was misconfigured would otherwise stay permanently
// unreachable even after the config is fixed, since Upload's returned URL
// gets frozen into the DB. Recomputing it on every read self-heals any
// such row automatically, the same way verification documents already do
// via presigned URLs.
func (c *Client) PublicURL(key string) string {
	return fmt.Sprintf("%s/%s", c.publicBaseURL, key)
}

func (c *Client) Delete(ctx context.Context, key string) error {
	_, err := c.s3.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(c.bucket),
		Key:    aws.String(key),
	})
	return err
}

// UploadDoc puts an object in the private verification-documents bucket.
// Unlike Upload, it returns no URL — the object isn't publicly reachable
// at any URL; callers must go through PresignDocURL to get a viewable
// (and time-limited) link.
func (c *Client) UploadDoc(ctx context.Context, key string, body []byte, contentType string) error {
	_, err := c.s3.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(c.docsBucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(body),
		ContentType: aws.String(contentType),
	})
	if err != nil {
		return wrapBucketError(err, "upload doc object", c.docsBucket)
	}
	return nil
}

func (c *Client) DeleteDoc(ctx context.Context, key string) error {
	_, err := c.s3.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(c.docsBucket),
		Key:    aws.String(key),
	})
	return err
}

// PresignDocURL generates a time-limited signed GET URL for an object in
// the private docs bucket — the only way to view a verification document,
// since the bucket itself has no public-read access. Callers should
// generate this on demand (e.g. when an admin opens the review screen),
// not store it, since it expires after ttl.
func (c *Client) PresignDocURL(ctx context.Context, key string, ttl time.Duration) (string, error) {
	req, err := c.presign.PresignGetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(c.docsBucket),
		Key:    aws.String(key),
	}, s3.WithPresignExpires(ttl))
	if err != nil {
		return "", fmt.Errorf("presign doc url: %w", err)
	}
	return req.URL, nil
}
