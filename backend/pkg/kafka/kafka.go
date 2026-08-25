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
	writer  *kafka.Writer
	brokers []string
}

func NewProducer(brokers []string) *Producer {
	return &Producer{
		brokers: brokers,
		writer: &kafka.Writer{
			Addr:                   kafka.TCP(brokers...),
			Balancer:               &kafka.LeastBytes{},
			AllowAutoTopicCreation: true,
			BatchTimeout:           50 * time.Millisecond,
		},
	}
}

// Ping dials the first configured broker to confirm it's reachable. Used by
// the readiness check so a network-level misconfiguration (wrong host, a
// missing security-group rule) is caught by a health probe instead of only
// surfacing on the first real publish — see the 2026-08-24 incident where
// Kafka/Elasticsearch ports were never opened on the supporting-services
// security group, and the resulting failure was invisible until a real
// request exercised the path.
func (p *Producer) Ping(ctx context.Context) error {
	if len(p.brokers) == 0 {
		return nil
	}
	conn, err := kafka.DefaultDialer.DialContext(ctx, "tcp", p.brokers[0])
	if err != nil {
		return err
	}
	return conn.Close()
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
