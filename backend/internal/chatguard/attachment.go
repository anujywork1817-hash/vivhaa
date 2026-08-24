package chatguard

import (
	"context"
	"errors"
)

// attachment.go defines the integration points for moderating non-text
// chat content (images, QR codes inside images, voice messages).
//
// IMPORTANT — infrastructure status as of this implementation: the chat
// feature in this codebase currently supports text messages only (see
// the Phase 1 audit — chat_messages.body is a plain TEXT column, there is
// no attachment_url/media column, no image or voice message "kind", and
// no OCR/STT provider is wired up anywhere in the app). These interfaces
// exist so that IF image or voice chat messages are added later, they can
// be routed through the same ModerateText pipeline via a real
// implementation of OCRProvider/STTProvider/QRDecoder — without that
// being a speculative, untested guess about what the eventual image
// pipeline will look like. Until a provider is registered, calling
// ModerateImage/ModerateVoice returns ErrProviderNotConfigured; callers
// MUST treat that as "cannot verify this attachment is safe" and refuse
// to store/deliver it, never as ALLOW.

var ErrProviderNotConfigured = errors.New("chatguard: no provider configured for this attachment type")

// OCRProvider extracts text from an image. A real implementation would
// wrap a cloud OCR API (Google Vision, AWS Textract, Tesseract, ...);
// which one is a deployment decision, not a moderation-logic one, so it's
// injected here rather than hard-coded.
type OCRProvider interface {
	ExtractText(ctx context.Context, imageBytes []byte) (string, error)
}

// QRDecoder decodes any QR code payload present in an image. Returns
// ("", nil) if no QR code is found (not an error).
type QRDecoder interface {
	DecodeQR(ctx context.Context, imageBytes []byte) (string, error)
}

// STTProvider transcribes a voice message to text. A real implementation
// would wrap a cloud speech-to-text API (Google STT, AWS Transcribe,
// Whisper, ...).
type STTProvider interface {
	Transcribe(ctx context.Context, audioBytes []byte) (string, error)
}

// ImageModerator moderates an image attachment: run OCR, run QR decode,
// run both extracted strings through the same text pipeline used for
// normal messages. Nil providers are legal at construction (an app
// without image messages yet doesn't need to configure one) and cause
// Moderate to fail closed with ErrProviderNotConfigured.
type ImageModerator struct {
	engine *Engine
	ocr    OCRProvider
	qr     QRDecoder
}

func NewImageModerator(engine *Engine, ocr OCRProvider, qr QRDecoder) *ImageModerator {
	return &ImageModerator{engine: engine, ocr: ocr, qr: qr}
}

// Moderate returns the policy decision for an image. On any provider
// error (including "not configured"), it fails closed with
// BlockSuspiciousContent — an image that couldn't be verified is never
// treated as safe (Phase 9: "Do not permanently store or deliver blocked
// images").
func (m *ImageModerator) Moderate(ctx context.Context, imageBytes []byte) Result {
	if m.ocr == nil && m.qr == nil {
		return block(BlockSuspiciousContent, CategoryNone, "", "no image moderation provider configured")
	}

	if m.ocr != nil {
		text, err := m.ocr.ExtractText(ctx, imageBytes)
		if err != nil {
			return block(BlockSuspiciousContent, CategoryNone, "", "ocr provider error")
		}
		if r := m.engine.ModerateText(text); r.Decision != Allow {
			return r
		}
	}

	if m.qr != nil {
		payload, err := m.qr.DecodeQR(ctx, imageBytes)
		if err != nil {
			return block(BlockSuspiciousContent, CategoryNone, "", "qr decode error")
		}
		if payload != "" {
			// A QR payload is often a bare URL/vCard/"tel:"/"mailto:" string
			// rather than prose — run it through the same detectors; normal
			// (non-contact) QR codes such as a plain product link or a
			// short piece of text still pass ModerateText's normal rules.
			if r := m.engine.ModerateText(payload); r.Decision != Allow {
				return r
			}
		}
	}

	return allow()
}

// VoiceModerator moderates a voice-message attachment via
// transcribe-then-text-moderate. Same fail-closed behavior as
// ImageModerator.
type VoiceModerator struct {
	engine *Engine
	stt    STTProvider
}

func NewVoiceModerator(engine *Engine, stt STTProvider) *VoiceModerator {
	return &VoiceModerator{engine: engine, stt: stt}
}

func (m *VoiceModerator) Moderate(ctx context.Context, audioBytes []byte) Result {
	if m.stt == nil {
		return block(BlockSuspiciousContent, CategoryNone, "", "no speech-to-text provider configured")
	}
	text, err := m.stt.Transcribe(ctx, audioBytes)
	if err != nil {
		return block(BlockSuspiciousContent, CategoryNone, "", "stt provider error")
	}
	return m.engine.ModerateText(text)
}
