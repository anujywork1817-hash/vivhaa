package profiles

// CalculateCompletion returns 0-100 based on how many of the fields that
// matter for match quality are filled in, plus whether at least one photo
// has been uploaded.
func CalculateCompletion(p Profile, photoCount int) int {
	total := 0
	filled := 0

	check := func(isSet bool) {
		total++
		if isSet {
			filled++
		}
	}

	check(p.FullName != nil && *p.FullName != "")
	check(p.DateOfBirth != nil)
	check(p.Gender != nil && *p.Gender != "")
	check(p.HeightCM != nil)
	check(p.MaritalStatus != nil && *p.MaritalStatus != "")
	check(p.Religion != nil && *p.Religion != "")
	check(p.Community != nil && *p.Community != "")
	check(p.MotherTongue != nil && *p.MotherTongue != "")
	check(p.Education != nil && *p.Education != "")
	check(p.Occupation != nil && *p.Occupation != "")
	check(p.AnnualIncomeINR != nil)
	check(p.Country != nil && *p.Country != "")
	check(p.State != nil && *p.State != "")
	check(p.City != nil && *p.City != "")
	check(p.FamilyType != nil && *p.FamilyType != "")
	check(p.FamilyStatus != nil && *p.FamilyStatus != "")
	check(p.Diet != nil && *p.Diet != "")
	check(p.AboutMe != nil && *p.AboutMe != "")
	check(photoCount > 0)

	if total == 0 {
		return 0
	}
	return filled * 100 / total
}
