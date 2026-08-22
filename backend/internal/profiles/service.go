package profiles

import (
	"context"
	"errors"
	"fmt"
	"time"

	"matrimony-backend/internal/queue"
	"matrimony-backend/internal/storage"
	"matrimony-backend/internal/subscriptions"
	"matrimony-backend/internal/users"
	"matrimony-backend/internal/visitors"
)

var (
	ErrAlreadyExists   = errors.New("profile already exists")
	ErrForbidden       = errors.New("profile is private")
	ErrTooManyPhotos   = errors.New("maximum of 6 photos allowed")
	ErrPhotoNotOwned   = errors.New("photo does not belong to this profile")
	ErrInvalidImage    = errors.New("invalid image")
	ErrPremiumRequired = errors.New("upgrade to premium to view contact details")
	ErrInvalidLocation = errors.New("latitude must be between -90 and 90, longitude between -180 and 180")
	ErrInvalidAge      = errors.New("date of birth must put the member between 18 and 100 years old")
)

const maxPhotosPerProfile = 6
const dateLayout = "2006-01-02"

// Age bounds for a member's own date of birth. The client calendar already
// restricts its range to these, but the API is the boundary that actually
// enforces it.
const (
	minSignupAge = 18
	maxSignupAge = 100
)

// ageOn returns how many whole years old someone born on dob is at on,
// counting a birthday as reached only once the day itself arrives.
func ageOn(dob, on time.Time) int {
	years := on.Year() - dob.Year()
	if on.Month() < dob.Month() ||
		(on.Month() == dob.Month() && on.Day() < dob.Day()) {
		years--
	}
	return years
}

// BlockChecker reports whether two users have a block relationship in
// either direction. Declared here rather than importing internal/blocked
// directly because blocked.Service already imports profiles — Go forbids
// the resulting import cycle. *blocked.Repository satisfies this
// interface structurally (same method signature), so main.go can wire it
// in without either package knowing about the other's types.
type BlockChecker interface {
	IsBlocked(ctx context.Context, userA, userB string) (bool, error)
}

type Service struct {
	repo         *Repository
	uploader     *storage.PhotoUploader
	visitorsSvc  *visitors.Service
	usersRepo    *users.Repository
	subsSvc      *subscriptions.Service
	publisher    *queue.Publisher
	blockChecker BlockChecker
}

func NewService(repo *Repository, uploader *storage.PhotoUploader, visitorsSvc *visitors.Service, usersRepo *users.Repository, subsSvc *subscriptions.Service, publisher *queue.Publisher, blockChecker BlockChecker) *Service {
	return &Service{repo: repo, uploader: uploader, visitorsSvc: visitorsSvc, usersRepo: usersRepo, subsSvc: subsSvc, publisher: publisher, blockChecker: blockChecker}
}

// checkNotBlocked returns ErrNotFound (not a "forbidden" error) when
// requestingUserID and targetUserID have blocked each other in either
// direction — a blocked profile should look like it doesn't exist rather
// than leaking that a block relationship exists to the person who's
// blocked.
func (s *Service) checkNotBlocked(ctx context.Context, requestingUserID, targetUserID string) error {
	if requestingUserID == targetUserID {
		return nil
	}
	blocked, err := s.blockChecker.IsBlocked(ctx, requestingUserID, targetUserID)
	if err != nil {
		return err
	}
	if blocked {
		return ErrNotFound
	}
	return nil
}

func (s *Service) publishUpdated(ctx context.Context, profileID, userID string) {
	_ = s.publisher.PublishProfileUpdated(ctx, queue.ProfileUpdatedEvent{ProfileID: profileID, UserID: userID})
}

func (s *Service) Create(ctx context.Context, userID string, in ProfileInput) (ProfileResponse, error) {
	if _, err := s.repo.GetByUserID(ctx, userID); err == nil {
		return ProfileResponse{}, ErrAlreadyExists
	} else if !errors.Is(err, ErrNotFound) {
		return ProfileResponse{}, err
	}

	p := Profile{Visibility: "public"}
	if err := applyInput(&p, in); err != nil {
		return ProfileResponse{}, err
	}

	created, err := s.repo.Create(ctx, userID, p)
	if err != nil {
		return ProfileResponse{}, err
	}

	s.publishUpdated(ctx, created.ID, userID)

	return s.toResponse(ctx, created)
}

func (s *Service) GetMine(ctx context.Context, userID string) (ProfileResponse, error) {
	p, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return ProfileResponse{}, err
	}
	return s.toResponse(ctx, p)
}

func (s *Service) Update(ctx context.Context, userID string, in ProfileInput) (ProfileResponse, error) {
	current, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return ProfileResponse{}, err
	}

	if err := applyInput(&current, in); err != nil {
		return ProfileResponse{}, err
	}

	updated, err := s.repo.Update(ctx, current)
	if err != nil {
		return ProfileResponse{}, err
	}

	s.publishUpdated(ctx, updated.ID, userID)

	return s.toResponse(ctx, updated)
}

// GetByID returns another user's profile, enforcing visibility: private
// profiles are only visible to their owner.
func (s *Service) GetByID(ctx context.Context, profileID, requestingUserID string) (ProfileResponse, error) {
	p, err := s.repo.GetByID(ctx, profileID)
	if err != nil {
		return ProfileResponse{}, err
	}

	if err := s.checkNotBlocked(ctx, requestingUserID, p.UserID); err != nil {
		return ProfileResponse{}, err
	}

	if p.Visibility == "private" && p.UserID != requestingUserID {
		return ProfileResponse{}, ErrForbidden
	}

	if err := s.visitorsSvc.RecordVisit(ctx, requestingUserID, p.UserID); err != nil {
		return ProfileResponse{}, err
	}

	return s.toResponse(ctx, p)
}

// GetByCode looks up a profile by its short user-facing code (e.g.
// "VV100042") — the same visibility/visitor-recording rules as GetByID.
func (s *Service) GetByCode(ctx context.Context, code, requestingUserID string) (ProfileResponse, error) {
	p, err := s.repo.GetByCode(ctx, code)
	if err != nil {
		return ProfileResponse{}, err
	}

	if err := s.checkNotBlocked(ctx, requestingUserID, p.UserID); err != nil {
		return ProfileResponse{}, err
	}

	if p.Visibility == "private" && p.UserID != requestingUserID {
		return ProfileResponse{}, ErrForbidden
	}

	if err := s.visitorsSvc.RecordVisit(ctx, requestingUserID, p.UserID); err != nil {
		return ProfileResponse{}, err
	}

	return s.toResponse(ctx, p)
}

// GetContactInfo returns the profile owner's phone/email, gated behind the
// requesting user's "view_contact" subscription feature.
func (s *Service) GetContactInfo(ctx context.Context, profileID, requestingUserID string) (ContactInfoResponse, error) {
	p, err := s.repo.GetByID(ctx, profileID)
	if err != nil {
		return ContactInfoResponse{}, err
	}

	// BUG-H08: GetByID/GetByCode already gate on block status; this direct
	// contact-info lookup didn't, so a blocked user could still pull the
	// owner's phone/email even though they couldn't view the profile
	// itself through the normal paths.
	if err := s.checkNotBlocked(ctx, requestingUserID, p.UserID); err != nil {
		return ContactInfoResponse{}, err
	}

	if p.Visibility == "private" && p.UserID != requestingUserID {
		return ContactInfoResponse{}, ErrForbidden
	}

	if p.UserID != requestingUserID {
		hasFeature, err := s.subsSvc.HasFeature(ctx, requestingUserID, "view_contact")
		if err != nil {
			return ContactInfoResponse{}, err
		}
		if !hasFeature {
			return ContactInfoResponse{}, ErrPremiumRequired
		}
	}

	owner, err := s.usersRepo.GetByID(ctx, p.UserID)
	if err != nil {
		return ContactInfoResponse{}, err
	}

	return ContactInfoResponse{Phone: owner.Phone, Email: owner.Email}, nil
}

// GetContactInfoRaw returns targetUserID's phone/email with none of
// GetContactInfo's gating (block check, visibility, premium feature) —
// callers must have their own basis for skipping those checks.
//
// The only caller is chat.Service.RespondContact, once the contact's
// owner has explicitly consented to share by accepting the request:
// that consent is what stands in for GetContactInfo's normal checks,
// not an oversight. What still must be premium-gated is whether the
// *requester* is shown the real value, which the caller decides at
// read time — see contactSharedPaywallBody in package chat.
func (s *Service) GetContactInfoRaw(ctx context.Context, targetUserID string) (ContactInfoResponse, error) {
	p, err := s.repo.GetByUserID(ctx, targetUserID)
	if err != nil {
		return ContactInfoResponse{}, err
	}
	owner, err := s.usersRepo.GetByID(ctx, p.UserID)
	if err != nil {
		return ContactInfoResponse{}, err
	}
	return ContactInfoResponse{Phone: owner.Phone, Email: owner.Email}, nil
}

// GetContactInfoByUserID is GetContactInfo keyed by the profile owner's
// user ID rather than profile ID — used by the chat contact-request
// accept flow, which only knows the two participants' user IDs.
func (s *Service) GetContactInfoByUserID(ctx context.Context, targetUserID, requestingUserID string) (ContactInfoResponse, error) {
	p, err := s.repo.GetByUserID(ctx, targetUserID)
	if err != nil {
		return ContactInfoResponse{}, err
	}
	return s.GetContactInfo(ctx, p.ID, requestingUserID)
}

// UpdateLocation records the caller's current GPS position for the
// "Near Me" feature. Bounds are checked here (not just the DB constraint)
// so a bad client sends back a normal validation error instead of a raw
// database failure.
func (s *Service) UpdateLocation(ctx context.Context, userID string, lat, lng float64) error {
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return ErrInvalidLocation
	}
	return s.repo.UpdateLocation(ctx, userID, lat, lng)
}

func (s *Service) UploadPhoto(ctx context.Context, userID string, data []byte, contentType string) (PhotoResponse, error) {
	profile, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return PhotoResponse{}, err
	}

	if err := storage.ValidateImage(int64(len(data)), contentType); err != nil {
		return PhotoResponse{}, fmt.Errorf("%w: %v", ErrInvalidImage, err)
	}

	// BUG-M05: the max-photos check and the "is this the first photo"
	// decision both used to read CountPhotos here, separately from the
	// insert that followed — two concurrent uploads could each read a
	// count that was true at read time but stale by the time either
	// insert committed (both under the limit, or both seeing zero
	// existing photos). CreatePhoto now does the count check, the
	// max-photos check, and the insert as one transaction locked on the
	// profile row, so this is the S3 upload only, kept outside that
	// transaction so a slow upload never holds the row lock.
	key, url, err := s.uploader.UploadProfilePhoto(ctx, userID, data, contentType)
	if err != nil {
		return PhotoResponse{}, err
	}

	photo, err := s.repo.CreatePhoto(ctx, profile.ID, key, url)
	if err != nil {
		return PhotoResponse{}, err
	}

	s.publishUpdated(ctx, profile.ID, userID)

	return PhotoResponse{ID: photo.ID, URL: photo.URL, IsPrimary: photo.IsPrimary}, nil
}

// SetPrimaryPhoto marks one of the caller's own photos as their profile
// picture.
func (s *Service) SetPrimaryPhoto(ctx context.Context, userID, photoID string) (PhotoResponse, error) {
	profile, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return PhotoResponse{}, err
	}

	photo, err := s.repo.GetPhoto(ctx, photoID)
	if err != nil {
		return PhotoResponse{}, err
	}
	if photo.ProfileID != profile.ID {
		return PhotoResponse{}, ErrPhotoNotOwned
	}

	if err := s.repo.SetPrimaryPhoto(ctx, profile.ID, photoID); err != nil {
		return PhotoResponse{}, err
	}

	s.publishUpdated(ctx, profile.ID, userID)

	return PhotoResponse{ID: photo.ID, URL: photo.URL, IsPrimary: true}, nil
}

func (s *Service) DeletePhoto(ctx context.Context, userID, photoID string) error {
	profile, err := s.repo.GetByUserID(ctx, userID)
	if err != nil {
		return err
	}

	photo, err := s.repo.GetPhoto(ctx, photoID)
	if err != nil {
		return err
	}
	if photo.ProfileID != profile.ID {
		return ErrPhotoNotOwned
	}

	if err := s.uploader.Delete(ctx, photo.ObjectKey); err != nil {
		return err
	}
	if err := s.repo.DeletePhoto(ctx, photoID); err != nil {
		return err
	}

	// Deleting the profile picture would otherwise leave the profile with
	// no primary at all, so promote the next remaining photo (ListPhotos
	// is ordered primary-first, then by sort order/age) to keep the
	// "exactly one primary" invariant SetPrimaryPhoto relies on.
	if photo.IsPrimary {
		remaining, err := s.repo.ListPhotos(ctx, profile.ID)
		if err != nil {
			return err
		}
		if len(remaining) > 0 {
			if err := s.repo.SetPrimaryPhoto(ctx, profile.ID, remaining[0].ID); err != nil {
				return err
			}
		}
	}

	s.publishUpdated(ctx, profile.ID, userID)

	return nil
}

func (s *Service) toResponse(ctx context.Context, p Profile) (ProfileResponse, error) {
	photos, err := s.repo.ListPhotos(ctx, p.ID)
	if err != nil {
		return ProfileResponse{}, err
	}

	photoResponses := make([]PhotoResponse, 0, len(photos))
	for _, ph := range photos {
		photoResponses = append(photoResponses, PhotoResponse{ID: ph.ID, URL: ph.URL, IsPrimary: ph.IsPrimary})
	}

	var dobStr *string
	if p.DateOfBirth != nil {
		s := p.DateOfBirth.Format(dateLayout)
		dobStr = &s
	}

	return ProfileResponse{
		ID:                p.ID,
		UserID:            p.UserID,
		FullName:          p.FullName,
		DateOfBirth:       dobStr,
		Gender:            p.Gender,
		HeightCM:          p.HeightCM,
		MaritalStatus:     p.MaritalStatus,
		Religion:          p.Religion,
		Community:         p.Community,
		MotherTongue:      p.MotherTongue,
		Education:         p.Education,
		Occupation:        p.Occupation,
		AnnualIncomeINR:   p.AnnualIncomeINR,
		Country:           p.Country,
		State:             p.State,
		City:              p.City,
		FamilyType:        p.FamilyType,
		FamilyStatus:      p.FamilyStatus,
		FatherOccupation:  p.FatherOccupation,
		MotherOccupation:  p.MotherOccupation,
		SiblingsCount:     p.SiblingsCount,
		Diet:              p.Diet,
		Smoking:           p.Smoking,
		Drinking:          p.Drinking,
		AboutMe:           p.AboutMe,
		ProfileFor:        p.ProfileFor,
		SubCommunity:      p.SubCommunity,
		CasteNoBar:        p.CasteNoBar,
		College:           p.College,
		WorkWith:          p.WorkWith,
		CompanyName:       p.CompanyName,
		MatchmakingOptOut: p.MatchmakingOptOut,
		FamilyValues:      p.FamilyValues,
		LivesWithFamily:   p.LivesWithFamily,
		Hobbies:           p.Hobbies,
		SelfieVerified:    p.SelfieVerified,
		Manglik:           p.Manglik,
		Rashi:             p.Rashi,
		Nakshatra:         p.Nakshatra,
		BirthTime:         p.BirthTime,
		BirthPlace:        p.BirthPlace,
		WeightKG:          p.WeightKG,
		BodyType:          p.BodyType,
		Complexion:        p.Complexion,
		HasDisability:     p.HasDisability,
		Visibility:        p.Visibility,
		ProfileCode:       p.ProfileCode,
		CompletionPercent: CalculateCompletion(p, len(photos)),
		Photos:            photoResponses,
		CreatedAt:         p.CreatedAt.Format(time.RFC3339),
	}, nil
}

// applyInput overlays non-nil fields from in onto p.
func applyInput(p *Profile, in ProfileInput) error {
	if in.FullName != nil {
		p.FullName = in.FullName
	}
	if in.DateOfBirth != nil {
		t, err := time.Parse(dateLayout, *in.DateOfBirth)
		if err != nil {
			return err
		}
		if age := ageOn(t, time.Now().UTC()); age < minSignupAge || age > maxSignupAge {
			return ErrInvalidAge
		}
		p.DateOfBirth = &t
	}
	if in.Gender != nil {
		p.Gender = in.Gender
	}
	if in.HeightCM != nil {
		p.HeightCM = in.HeightCM
	}
	if in.MaritalStatus != nil {
		p.MaritalStatus = in.MaritalStatus
	}
	if in.Religion != nil {
		p.Religion = in.Religion
	}
	if in.Community != nil {
		p.Community = in.Community
	}
	if in.MotherTongue != nil {
		p.MotherTongue = in.MotherTongue
	}
	if in.Education != nil {
		p.Education = in.Education
	}
	if in.Occupation != nil {
		p.Occupation = in.Occupation
	}
	if in.AnnualIncomeINR != nil {
		p.AnnualIncomeINR = in.AnnualIncomeINR
	}
	if in.Country != nil {
		p.Country = in.Country
	}
	if in.State != nil {
		p.State = in.State
	}
	if in.City != nil {
		p.City = in.City
	}
	if in.FamilyType != nil {
		p.FamilyType = in.FamilyType
	}
	if in.FamilyStatus != nil {
		p.FamilyStatus = in.FamilyStatus
	}
	if in.FatherOccupation != nil {
		p.FatherOccupation = in.FatherOccupation
	}
	if in.MotherOccupation != nil {
		p.MotherOccupation = in.MotherOccupation
	}
	if in.SiblingsCount != nil {
		p.SiblingsCount = in.SiblingsCount
	}
	if in.Diet != nil {
		p.Diet = in.Diet
	}
	if in.Smoking != nil {
		p.Smoking = in.Smoking
	}
	if in.Drinking != nil {
		p.Drinking = in.Drinking
	}
	if in.AboutMe != nil {
		p.AboutMe = in.AboutMe
	}
	if in.ProfileFor != nil {
		p.ProfileFor = in.ProfileFor
	}
	if in.SubCommunity != nil {
		p.SubCommunity = in.SubCommunity
	}
	if in.CasteNoBar != nil {
		p.CasteNoBar = in.CasteNoBar
	}
	if in.College != nil {
		p.College = in.College
	}
	if in.WorkWith != nil {
		p.WorkWith = in.WorkWith
	}
	if in.CompanyName != nil {
		p.CompanyName = in.CompanyName
	}
	if in.MatchmakingOptOut != nil {
		p.MatchmakingOptOut = *in.MatchmakingOptOut
	}
	if in.FamilyValues != nil {
		p.FamilyValues = in.FamilyValues
	}
	if in.LivesWithFamily != nil {
		p.LivesWithFamily = in.LivesWithFamily
	}
	if in.Hobbies != nil {
		p.Hobbies = in.Hobbies
	}
	// SelfieVerified is intentionally not settable via ProfileInput — see
	// BUG-C05: it must only ever be flipped by admin verification review
	// (verification.Service.review), never by the user themselves.
	if in.Manglik != nil {
		p.Manglik = in.Manglik
	}
	if in.Rashi != nil {
		p.Rashi = in.Rashi
	}
	if in.Nakshatra != nil {
		p.Nakshatra = in.Nakshatra
	}
	if in.BirthTime != nil {
		p.BirthTime = in.BirthTime
	}
	if in.BirthPlace != nil {
		p.BirthPlace = in.BirthPlace
	}
	if in.WeightKG != nil {
		p.WeightKG = in.WeightKG
	}
	if in.BodyType != nil {
		p.BodyType = in.BodyType
	}
	if in.Complexion != nil {
		p.Complexion = in.Complexion
	}
	if in.HasDisability != nil {
		p.HasDisability = in.HasDisability
	}
	if in.Visibility != nil {
		p.Visibility = *in.Visibility
	}
	return nil
}
