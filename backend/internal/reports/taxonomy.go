package reports

// taxonomy.go is the single source of truth for valid report reasons —
// checked in Submit rather than a giant `validate:"oneof=..."` tag, since
// each reason also needs a category (for the admin queue's grouping) and
// a priority (so a safety report can be surfaced ahead of routine spam
// reports instead of competing purely on created_at).

const (
	CategoryProfile = "profile"
	CategoryChat    = "chat"
	CategoryPhoto   = "photo"
	CategorySafety  = "safety"
	CategoryMoney   = "money"

	PriorityNormal = "normal"
	PriorityHigh   = "high"
)

type reasonMeta struct {
	Category string
	Priority string
	Label    string // humanized, for the admin queue — see moderation package
}

// reasonCatalog intentionally allows the same reason token to appear
// under more than one category's conceptual list (e.g. "harassment" is
// meaningful both as a profile report and a chat report) — the catalog
// only needs ONE entry per token since Category here just drives which
// group the admin queue buckets it into, not which UI surfaced it.
var reasonCatalog = map[string]reasonMeta{
	// Profile reports
	"fake_profile":               {CategoryProfile, PriorityNormal, "Fake / misleading profile"},
	"impersonation":              {CategoryProfile, PriorityNormal, "Impersonating someone"},
	"wrong_photos":               {CategoryProfile, PriorityNormal, "Wrong photos"},
	"someone_elses_photos":       {CategoryProfile, PriorityNormal, "Photos of someone else"},
	"incorrect_age":              {CategoryProfile, PriorityNormal, "Age is incorrect"},
	"incorrect_marital_status":   {CategoryProfile, PriorityNormal, "Marital status is incorrect"},
	"wrong_occupation_education": {CategoryProfile, PriorityNormal, "Wrong occupation / education"},
	"suspicious_profile":         {CategoryProfile, PriorityNormal, "Suspicious profile"},
	"commercial_profile":         {CategoryProfile, PriorityNormal, "Commercial / promotional profile"},
	"inappropriate_content":      {CategoryProfile, PriorityNormal, "Inappropriate content"},

	// Chat / message reports
	"sharing_phone_number":    {CategoryChat, PriorityNormal, "Sharing phone number"},
	"sharing_whatsapp_number": {CategoryChat, PriorityNormal, "Sharing WhatsApp number"},
	"sharing_email_address":   {CategoryChat, PriorityNormal, "Sharing email address"},
	"sharing_social_handle":   {CategoryChat, PriorityNormal, "Sharing social-media handle"},
	"asking_move_outside_app": {CategoryChat, PriorityNormal, "Asking to move conversation outside Vivah"},
	"abusive_language":        {CategoryChat, PriorityNormal, "Abusive language"},
	"sexual_messages":         {CategoryChat, PriorityHigh, "Sexual / inappropriate messages"},
	"suspicious_links":        {CategoryChat, PriorityNormal, "Suspicious links"},
	"spam":                    {CategoryChat, PriorityNormal, "Spam"},

	// Photo reports
	"nudity_explicit":       {CategoryPhoto, PriorityHigh, "Nudity / sexually explicit"},
	"inappropriate_photo":   {CategoryPhoto, PriorityNormal, "Inappropriate photo"},
	"fake_photo":            {CategoryPhoto, PriorityNormal, "Fake photo"},
	"celebrity_photo":       {CategoryPhoto, PriorityNormal, "Celebrity / someone else's photo"},
	"group_photo_confusion": {CategoryPhoto, PriorityNormal, "Group photo causing confusion"},
	"offensive_content":     {CategoryPhoto, PriorityNormal, "Offensive content"},
	"misleading_photo":      {CategoryPhoto, PriorityNormal, "Misleading photo"},
	"ai_generated_photo":    {CategoryPhoto, PriorityNormal, "AI-generated/deceptive photo"},

	// Serious safety reports — always high priority
	"financial_fraud":     {CategorySafety, PriorityHigh, "Financial fraud"},
	"extortion_blackmail": {CategorySafety, PriorityHigh, "Extortion / blackmail"},
	"threats":             {CategorySafety, PriorityHigh, "Threats"},
	"stalking":            {CategorySafety, PriorityHigh, "Stalking"},
	"identity_theft":      {CategorySafety, PriorityHigh, "Identity theft"},
	"underage_user":       {CategorySafety, PriorityHigh, "Underage user"},
	"sexual_exploitation": {CategorySafety, PriorityHigh, "Sexual exploitation"},
	"human_trafficking":   {CategorySafety, PriorityHigh, "Human trafficking concern"},
	"serious_harassment":  {CategorySafety, PriorityHigh, "Serious harassment"},

	// Money / fraud reports
	"asking_for_loan":             {CategoryMoney, PriorityHigh, "Asking for loan"},
	"asking_financial_help":       {CategoryMoney, PriorityHigh, "Asking for financial help"},
	"investment_scheme":           {CategoryMoney, PriorityHigh, "Investment scheme"},
	"upi_payment_request":         {CategoryMoney, PriorityHigh, "UPI/payment request"},
	"fake_emergency":              {CategoryMoney, PriorityHigh, "Fake emergency"},
	"loan_financial_scam":         {CategoryMoney, PriorityHigh, "Loan/financial scam"},
	"requesting_otp_pin_password": {CategoryMoney, PriorityHigh, "Requesting OTP/PIN/password"},
	"suspicious_bank_details":     {CategoryMoney, PriorityHigh, "Suspicious bank details"},

	// Shared across every category
	"asking_for_money": {CategoryProfile, PriorityNormal, "Asking for money"},
	"scam_fraud":       {CategoryProfile, PriorityHigh, "Scam / fraud"},
	"harassment":       {CategoryProfile, PriorityNormal, "Harassment"},

	// Free-text fallback — the "custom report" option. Details is
	// required when this is chosen (enforced in Service.Submit), since
	// "other" with no explanation gives an admin nothing to act on.
	"other": {CategoryProfile, PriorityNormal, "Other"},
}

// ReasonMeta looks up a reason's category/priority/label, ok=false for an
// unrecognized reason.
func ReasonMeta(reason string) (category, priority, label string, ok bool) {
	m, found := reasonCatalog[reason]
	if !found {
		return "", "", "", false
	}
	return m.Category, m.Priority, m.Label, true
}
