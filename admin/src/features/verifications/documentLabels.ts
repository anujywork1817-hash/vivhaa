const DOCUMENT_LABELS: Record<string, string> = {
  aadhaar: 'Aadhaar card',
  passport: 'Passport',
  driving_license: 'Driving license',
  voter_id: 'Voter ID',
  pan: 'PAN card',
  selfie: 'Verification selfie',
  personal_document: 'Personal document',
};

export function documentLabel(type: string): string {
  return DOCUMENT_LABELS[type] ?? type;
}
