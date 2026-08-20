// Package kafka wraps segmentio/kafka-go for the app's async event bus:
// a small typed producer plus a consumer loop that dispatches each
// message to a handler function.
package kafka

import (
	"context"
	"log/slog"
	"time"

	"github.com/segmentio/kafka-go"
)

type Producer struct {
	writer *kafka.Writer
}

func NewProducer(brokers []string) *Producer {
	return &Producer{
		writer: &kafka.Writer{
			Addr:                   kafka.TCP(brokers...),
			Balancer:               &kafka.LeastBytes{},
			AllowAutoTopicCreation: true,
			BatchTimeout:           50 * time.Millisecond,
		},
	}
}

func (p *Producer) Publish(ctx context.Context, topic, key string, value []byte) error {
	return p.writer.WriteMessages(ctx, kafka.Message{
		Topic: topic,
		Key:   []byte(key),
		Value: value,
	})
}

func (p *Producer) Close() error {
	return p.writer.Close()
}

// Handler processes one consumed message. A returned error is logged but
// does not stop the consume loop or retry the message — callers that need
// stronger delivery guarantees should make their handler idempotent and
// side-effect-safe to re-run.
type Handler func(ctx context.Context, key, value []byte) error

// Consume blocks, reading from topic under groupID and invoking handler
// for each message, until ctx is cancelled.
func Consume(ctx context.Context, brokers []string, topic, groupID string, handler Handler, log *slog.Logger) {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers: brokers,
		Topic:   topic,
		GroupID: groupID,
	})
	defer reader.Close()

	log.Info("kafka consumer started", "topic", topic, "group", groupID)

	for {
		msg, err := reader.ReadMessage(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			log.Error("kafka read error", "topic", topic, "error", err)
			continue
		}

		if err := handler(ctx, msg.Key, msg.Value); err != nil {
			log.Error("kafka handler error", "topic", topic, "error", err)
		}
	}
}
