package queue

import (
	"context"
	"encoding/json"

	"matrimony-backend/pkg/kafka"
)

// Publisher offers typed publish methods over the raw Kafka producer, so
// callers can't accidentally publish the wrong event shape to a topic.
type Publisher struct {
	producer *kafka.Producer
}

func NewPublisher(producer *kafka.Producer) *Publisher {
	return &Publisher{producer: producer}
}

func (p *Publisher) PublishProfileUpdated(ctx context.Context, event ProfileUpdatedEvent) error {
	return p.publish(ctx, TopicProfileUpdated, event.ProfileID, event)
}

func (p *Publisher) PublishNotificationDispatch(ctx context.Context, event NotificationDispatchEvent) error {
	return p.publish(ctx, TopicNotificationDispatch, event.UserID, event)
}

func (p *Publisher) publish(ctx context.Context, topic, key string, event any) error {
	value, err := json.Marshal(event)
	if err != nil {
		return err
	}
	return p.producer.Publish(ctx, topic, key, value)
}
