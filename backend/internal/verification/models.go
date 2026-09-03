package verification

import "time"

type Verification struct {
	ID           string
	UserID       string
	// FullName is only populated by ListByStatus (the admin review queue),
	// via a LEFT JOIN against profiles — nil for every other query path
	// (Create/GetLatestByUserID/GetByID/ListByUserID), which don't need it
	// and use the plain `columns` scan. Nullable because a submitter may
	// not have finished onboarding a profile yet.
	FullName     *string
	DocumentType string
	DocumentKey  string
	// DocumentURL is legacy/unused going forward — old rows may still
	// carry a stale public URL from before BUG-C06's fix; new rows leave
	// it NULL. The API always mints a fresh signed URL from DocumentKey
	// instead of reading this field (see Service.toResponse).
	DocumentURL *string
	Status      string
	ReviewedBy  *string
	ReviewNotes *string
	CreatedAt   time.Time
	ReviewedAt  *time.Time
}
