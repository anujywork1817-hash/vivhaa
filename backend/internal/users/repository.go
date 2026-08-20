package users

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("not found")

type User struct {
	ID            string    `json:"id"`
	Phone         *string   `json:"phone"`
	Email         *string   `json:"email"`
	PhoneVerified bool      `json:"phone_verified"`
	EmailVerified bool      `json:"email_verified"`
	Status        string    `json:"status"`
	Role          string    `json:"role"`
	CreatedAt     time.Time `json:"created_at"`
}

type Repository struct {
	db *pgxpool.Pool
}

func NewRepository(db *pgxpool.Pool) *Repository {
	return &Repository{db: db}
}

func (r *Repository) GetByID(ctx context.Context, id string) (User, error) {
	const q = `
		SELECT id, phone, email, phone_verified, email_verified, status, role, created_at
		FROM users WHERE id = $1 AND deleted_at IS NULL`
	var u User
	err := r.db.QueryRow(ctx, q, id).Scan(
		&u.ID, &u.Phone, &u.Email, &u.PhoneVerified, &u.EmailVerified, &u.Status, &u.Role, &u.CreatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return User{}, ErrNotFound
	}
	return u, err
}
