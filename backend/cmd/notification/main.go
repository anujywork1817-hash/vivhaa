// cmd/notification is the dedicated notification dispatcher: it consumes
// notification.dispatch events, persists the in-app notification, and
// attempts external delivery (push today; email/sms are easy to add the
// same way once real provider credentials exist).
package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"matrimony-backend/configs"
	"matrimony-backend/internal/devices"
	"matrimony-backend/internal/notifications"
	"matrimony-backend/internal/queue"
	"matrimony-backend/pkg/database"
	"matrimony-backend/pkg/firebase"
	"matrimony-backend/pkg/kafka"
	"matrimony-backend/pkg/logger"
)

func main() {
	cfg, err := configs.Load()
	if err != nil {
		fmt.Fprintln(os.Stderr, "fatal: invalid configuration:", err)
		os.Exit(1)
	}

	log := logger.New(cfg.Env)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	dbPool, err := database.NewPool(ctx, cfg.DB)
	if err != nil {
		log.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	defer dbPool.Close()

	notifRepo := notifications.NewRepository(dbPool)
	notifService := notifications.NewService(notifRepo)

	// Real FCM when credentials are configured, otherwise log the push so
	// the dispatch pipeline stays exercisable locally without a Firebase
	// project. A misconfigured key is surfaced loudly rather than silently
	// downgrading — that would look identical to working push until
	// someone noticed no notifications ever arrived.
	var pushSender firebase.Sender = firebase.NewConsoleSender(log)
	if cfg.FCM.Configured() {
		devicesRepo := devices.NewRepository(dbPool)
		sender, err := firebase.NewFCMSender(
			ctx, cfg.FCM.CredentialsJSON, cfg.FCM.CredentialsFile, cfg.FCM.ProjectID, devicesRepo, log)
		if err != nil {
			log.Error("FCM credentials were provided but could not be used", "error", err)
			os.Exit(1)
		}
		pushSender = sender
		log.Info("push notifications enabled via FCM")
	} else {
		log.Warn("FCM_CREDENTIALS_JSON/FILE not set — pushes will only be logged, not delivered")
	}

	handler := func(ctx context.Context, _, value []byte) error {
		var event queue.NotificationDispatchEvent
		if err := json.Unmarshal(value, &event); err != nil {
			return err
		}

		if event.PushOnly {
			return pushSender.SendData(ctx, event.UserID, event.PushData)
		}

		if err := notifService.Create(ctx, event.UserID, event.Type, event.Title, &event.Body, event.Data); err != nil {
			return err
		}

		return pushSender.Send(ctx, event.UserID, event.Title, event.Body)
	}

	log.Info("notification dispatcher started", "topic", queue.TopicNotificationDispatch)
	kafka.Consume(ctx, cfg.Kafka.Brokers, queue.TopicNotificationDispatch, "notification-dispatcher", handler, log)
}
