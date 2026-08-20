package ai

type ChatRequest struct {
	Message string `json:"message" validate:"required,min=1,max=2000"`
}

type MessageResponse struct {
	ID        string `json:"id"`
	Role      string `json:"role"`
	Content   string `json:"content"`
	CreatedAt string `json:"created_at"`
}

type IcebreakersResponse struct {
	Icebreakers []string `json:"icebreakers"`
}

type MatchBlurbResponse struct {
	Blurb string `json:"blurb"`
}
