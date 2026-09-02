// Command seed populates the database with fake demo accounts — 25 male
// and 25 female by default — each with a complete profile and an uploaded
// placeholder photo. It talks to the already-running api service over
// plain HTTP (signup -> verify-otp -> create profile -> upload photo),
// the same path a real client takes, so every downstream side effect
// (Elasticsearch indexing, profile-code assignment, completion %) happens
// exactly as it would for a real signup.
//
// Run it against a docker-compose stack:
//
//	docker compose run --rm seed
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"io"
	"log"
	"math/rand"
	"mime/multipart"
	"net/http"
	"net/textproto"
	"os"
	"strconv"
	"time"
)

var baseURL = envOr("SEED_API_BASE_URL", "http://api:8080")

const seedPassword = "Passw0rd!123"

// seedAdminSecret, when set, must match the api service's own
// SEED_ADMIN_SECRET env var — sent as X-Seed-Secret on profile creation so
// the first demoCountPerGender accounts of each gender can be flagged
// is_demo=true (see internal/profiles' Handler.Create /
// seedSecretMatches). Left unset, every seeded account is just a normal
// (non-demo) profile.
var seedAdminSecret = envOr("SEED_ADMIN_SECRET", "")

// demoCountPerGender is how many of the FIRST accounts of each gender
// created this run get flagged is_demo=true — the fixed 10 male + 10
// female pool the free swipe-deck hook (GET /demo/swipe-deck) shows every
// new user. Independent of SEED_MALE_COUNT/SEED_FEMALE_COUNT: running
// with higher counts (a bigger pool of ordinary seeded members) still only
// marks the first 10 of each gender as demo.
const demoCountPerGender = 10

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func envIntOr(key string, fallback int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return fallback
}

var (
	maleFirstNames = []string{
		"Aarav", "Vivaan", "Aditya", "Vihaan", "Arjun", "Sai", "Reyansh", "Ayaan",
		"Krishna", "Ishaan", "Rohan", "Kabir", "Yash", "Dev", "Aryan", "Karan",
		"Manish", "Rahul", "Nikhil", "Siddharth", "Varun", "Akash", "Harsh", "Pranav", "Raj",
	}
	femaleFirstNames = []string{
		"Ananya", "Diya", "Ishita", "Kavya", "Myra", "Aadhya", "Saanvi", "Pari",
		"Riya", "Anika", "Priya", "Neha", "Pooja", "Sneha", "Divya", "Meera",
		"Sanya", "Tanvi", "Shreya", "Aditi", "Nisha", "Kritika", "Simran", "Aisha", "Radhika",
	}
	lastNames = []string{
		"Sharma", "Verma", "Gupta", "Patel", "Reddy", "Nair", "Iyer", "Menon",
		"Kapoor", "Chopra", "Malhotra", "Singh", "Kumar", "Rao", "Joshi", "Mehta",
		"Agarwal", "Bose", "Chatterjee", "Pillai", "Desai", "Shah", "Trivedi", "Bhat", "Naidu",
	}

	cities = []struct{ city, state string }{
		{"Mumbai", "Maharashtra"}, {"Delhi", "Delhi"}, {"Bengaluru", "Karnataka"},
		{"Pune", "Maharashtra"}, {"Hyderabad", "Telangana"}, {"Chennai", "Tamil Nadu"},
		{"Ahmedabad", "Gujarat"}, {"Kolkata", "West Bengal"}, {"Jaipur", "Rajasthan"},
		{"Lucknow", "Uttar Pradesh"}, {"Surat", "Gujarat"}, {"Indore", "Madhya Pradesh"},
		{"Nagpur", "Maharashtra"}, {"Chandigarh", "Chandigarh"}, {"Kochi", "Kerala"},
	}

	religions      = []string{"Hindu", "Muslim", "Christian", "Sikh", "Jain", "Buddhist"}
	communities    = []string{"Brahmin", "Rajput", "Kayastha", "Agarwal", "Nair", "Reddy", "Patel", "Iyer"}
	motherTongues  = []string{"Hindi", "Marathi", "Tamil", "Telugu", "Kannada", "Gujarati", "Bengali", "Punjabi", "Malayalam"}
	educations     = []string{"B.Tech", "M.Tech", "MBA", "B.Com", "CA", "MBBS", "B.Sc", "M.Sc", "LLB", "B.A"}
	occupations    = []string{"Software Engineer", "Doctor", "Teacher", "Chartered Accountant", "Business Owner", "Government Employee", "Bank Manager", "Architect", "Lawyer", "Marketing Manager"}
	diets          = []string{"vegetarian", "non_vegetarian", "eggetarian"}
	maritalStatus  = "never_married"
	aboutTemplates = []string{
		"Simple, family-oriented person looking for a like-minded life partner.",
		"Love travelling and trying new cuisines. Looking to settle down with the right person.",
		"Career-focused but family always comes first. Enjoy music and weekend hikes.",
		"Down to earth and easy going. Believe in honesty and mutual respect in a relationship.",
		"Enjoy reading, fitness and spending time with family. Looking for a genuine connection.",
	}
)

func pick[T any](items []T) T {
	return items[rand.Intn(len(items))]
}

type signupResp struct {
	Identifier string `json:"identifier"`
	DevOTP     string `json:"dev_otp"`
}

type authResp struct {
	AccessToken string `json:"access_token"`
}

type apiEnvelope[T any] struct {
	Success bool   `json:"success"`
	Data    T      `json:"data"`
	Message string `json:"message"`
}

func postJSON[T any](path string, body any, out *T, bearer string, extraHeaders map[string]string) error {
	buf, err := json.Marshal(body)
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, baseURL+path, bytes.NewReader(buf))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if bearer != "" {
		req.Header.Set("Authorization", "Bearer "+bearer)
	}
	for k, v := range extraHeaders {
		req.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	respBody, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}
	if resp.StatusCode >= 300 {
		return fmt.Errorf("%s -> %d: %s", path, resp.StatusCode, string(respBody))
	}
	var env apiEnvelope[T]
	if err := json.Unmarshal(respBody, &env); err != nil {
		return fmt.Errorf("%s: decode: %w (body=%s)", path, err, string(respBody))
	}
	*out = env.Data
	return nil
}

// placeholderPhoto renders a flat-colour square PNG, the colour derived
// from the name so every seeded account gets a distinct, stable avatar
// image without needing any network access or bundled asset. Used only
// as a fallback when a real face photo can't be fetched.
func placeholderPhoto(name string) []byte {
	var hash uint32
	for _, r := range name {
		hash = hash*31 + uint32(r)
	}
	c := color.RGBA{
		R: uint8(120 + hash%100),
		G: uint8(80 + (hash/100)%100),
		B: uint8(90 + (hash/10000)%100),
		A: 255,
	}
	const size = 480
	img := image.NewRGBA(image.Rect(0, 0, size, size))
	for y := 0; y < size; y++ {
		for x := 0; x < size; x++ {
			img.Set(x, y, c)
		}
	}
	var buf bytes.Buffer
	_ = png.Encode(&buf, img)
	return buf.Bytes()
}

type randomUserResp struct {
	Results []struct {
		Picture struct {
			Large string `json:"large"`
		} `json:"picture"`
	} `json:"results"`
}

// fetchFacePhoto pulls one real, gender-matched face photo from
// randomuser.me — a public test-data API made exactly for seeding demo
// accounts like this — so seeded profiles look like actual people instead
// of flat colour swatches. Falls back to placeholderPhoto if the service
// is unreachable (e.g. no outbound internet from the container).
func fetchFacePhoto(gender string) (data []byte, contentType string) {
	genderParam := "male"
	if gender == "female" {
		genderParam = "female"
	}
	// A wide seed range keeps repeats unlikely across 50 accounts while
	// still being deterministic-ish per run.
	seedVal := rand.Intn(100000)
	apiURL := fmt.Sprintf("https://randomuser.me/api/?gender=%s&seed=seed%d&inc=picture&noinfo", genderParam, seedVal)

	resp, err := http.Get(apiURL)
	if err != nil {
		return placeholderPhoto(genderParam + strconv.Itoa(seedVal)), "image/png"
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil || resp.StatusCode >= 300 {
		return placeholderPhoto(genderParam + strconv.Itoa(seedVal)), "image/png"
	}

	var parsed randomUserResp
	if err := json.Unmarshal(body, &parsed); err != nil || len(parsed.Results) == 0 {
		return placeholderPhoto(genderParam + strconv.Itoa(seedVal)), "image/png"
	}

	photoResp, err := http.Get(parsed.Results[0].Picture.Large)
	if err != nil {
		return placeholderPhoto(genderParam + strconv.Itoa(seedVal)), "image/png"
	}
	defer photoResp.Body.Close()
	photoBytes, err := io.ReadAll(photoResp.Body)
	if err != nil || photoResp.StatusCode >= 300 {
		return placeholderPhoto(genderParam + strconv.Itoa(seedVal)), "image/png"
	}

	return photoBytes, "image/jpeg"
}

func uploadPhoto(bearer, gender string) error {
	photo, contentType := fetchFacePhoto(gender)
	filename := "avatar.png"
	if contentType == "image/jpeg" {
		filename = "avatar.jpg"
	}

	var buf bytes.Buffer
	mw := multipart.NewWriter(&buf)
	// CreateFormFile defaults the part's Content-Type to
	// application/octet-stream, which the API rejects — it only accepts
	// jpeg/png/webp, so the part needs an explicit type matching the bytes.
	header := textproto.MIMEHeader{}
	header.Set("Content-Disposition", fmt.Sprintf(`form-data; name="photo"; filename="%s"`, filename))
	header.Set("Content-Type", contentType)
	part, err := mw.CreatePart(header)
	if err != nil {
		return err
	}
	if _, err := part.Write(photo); err != nil {
		return err
	}
	if err := mw.Close(); err != nil {
		return err
	}

	req, err := http.NewRequest(http.MethodPost, baseURL+"/profiles/me/photos", &buf)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+bearer)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode >= 300 {
		return fmt.Errorf("upload photo -> %d: %s", resp.StatusCode, string(body))
	}
	return nil
}

func randomDOB(minAge, maxAge int) string {
	age := minAge + rand.Intn(maxAge-minAge+1)
	dob := time.Now().AddDate(-age, -rand.Intn(12), -rand.Intn(28))
	return dob.Format("2006-01-02")
}

func createAccount(index int, gender string, isDemo bool) error {
	first := pick(maleFirstNames)
	if gender == "female" {
		first = pick(femaleFirstNames)
	}
	last := pick(lastNames)
	fullName := first + " " + last

	prefix := "70"
	if gender == "female" {
		prefix = "80"
	}
	phone := fmt.Sprintf("+91%s%08d", prefix, index)

	var signup signupResp
	if err := postJSON("/auth/signup", map[string]string{
		"phone":    phone,
		"password": seedPassword,
	}, &signup, "", nil); err != nil {
		return fmt.Errorf("signup: %w", err)
	}

	var auth authResp
	if err := postJSON("/auth/verify-otp", map[string]string{
		"identifier": phone,
		"purpose":    "signup",
		"code":       signup.DevOTP,
	}, &auth, "", nil); err != nil {
		return fmt.Errorf("verify-otp: %w", err)
	}

	place := pick(cities)
	height := 165 + rand.Intn(21)
	if gender == "female" {
		height = 150 + rand.Intn(23)
	}
	income := int64(400000 + rand.Intn(2600000))

	profileBody := map[string]any{
		"full_name":         fullName,
		"date_of_birth":     randomDOB(23, 35),
		"gender":            gender,
		"height_cm":         height,
		"marital_status":    maritalStatus,
		"religion":          pick(religions),
		"community":         pick(communities),
		"mother_tongue":     pick(motherTongues),
		"education":         pick(educations),
		"occupation":        pick(occupations),
		"annual_income_inr": income,
		"country":           "India",
		"state":             place.state,
		"city":              place.city,
		"diet":              pick(diets),
		"about_me":          pick(aboutTemplates),
		"visibility":        "public",
	}
	var demoHeaders map[string]string
	if isDemo {
		// is_demo is only ever honored by the API when this header matches
		// the api service's own SEED_ADMIN_SECRET — see
		// internal/profiles' seedSecretMatches. Without SEED_ADMIN_SECRET
		// set for this seed run, the field is silently ignored and the
		// account is created as a normal (non-demo) profile.
		profileBody["is_demo"] = true
		if seedAdminSecret != "" {
			demoHeaders = map[string]string{"X-Seed-Secret": seedAdminSecret}
		}
	}
	var profile map[string]any
	if err := postJSON("/profiles", profileBody, &profile, auth.AccessToken, demoHeaders); err != nil {
		return fmt.Errorf("create profile: %w", err)
	}

	if err := uploadPhoto(auth.AccessToken, gender); err != nil {
		return fmt.Errorf("upload photo: %w", err)
	}

	demoTag := ""
	if isDemo {
		demoTag = " [DEMO]"
	}
	log.Printf("seeded %-6s %-22s %s%s", gender, fullName, phone, demoTag)
	return nil
}

// waitForAPI polls /health until the api service answers or the deadline
// passes. The api container can still be finishing startup (DB migrate,
// ES connect, etc.) by the time this one-off container starts, since
// depends_on only waits for the container process to start, not for the
// HTTP server inside it to be ready.
func waitForAPI(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		resp, err := http.Get(baseURL + "/health")
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode < 300 {
				return nil
			}
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("api not ready after %s: %v", timeout, err)
		}
		time.Sleep(2 * time.Second)
	}
}

func main() {
	maleCount := envIntOr("SEED_MALE_COUNT", 25)
	femaleCount := envIntOr("SEED_FEMALE_COUNT", 25)

	log.Printf("waiting for %s to be ready...", baseURL)
	if err := waitForAPI(60 * time.Second); err != nil {
		log.Fatal(err)
	}

	log.Printf("seeding against %s (%d male, %d female)", baseURL, maleCount, femaleCount)
	if seedAdminSecret == "" {
		log.Printf("warning: SEED_ADMIN_SECRET not set — the first %d male + %d female accounts will NOT be flagged is_demo (the API silently ignores is_demo without a matching secret)", demoCountPerGender, demoCountPerGender)
	}

	var failures int
	for i := 1; i <= maleCount; i++ {
		if err := createAccount(i, "male", i <= demoCountPerGender); err != nil {
			log.Printf("male #%d failed: %v", i, err)
			failures++
		}
	}
	for i := 1; i <= femaleCount; i++ {
		if err := createAccount(i, "female", i <= demoCountPerGender); err != nil {
			log.Printf("female #%d failed: %v", i, err)
			failures++
		}
	}

	if failures > 0 {
		log.Fatalf("done with %d failure(s)", failures)
	}
	log.Printf("done — all accounts share the password %q", seedPassword)
}
