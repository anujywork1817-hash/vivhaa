import 'package:flutter/services.dart';

/// A plain Indian mobile number (no country code, no leading 0/+) is
/// always exactly 10 digits — shared by every phone-entry field in the
/// app so the "10, not fewer, not more" rule is defined in one place
/// rather than re-typed (and potentially re-typo'd) at each call site.
const indianMobileNumberLength = 10;

/// Input formatters for a bare 10-digit Indian mobile number field:
/// digits only, hard-capped at 10 characters — the user simply can't
/// type an 11th digit or a non-digit character, rather than being told
/// about it after the fact.
final indianMobileInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.digitsOnly,
  LengthLimitingTextInputFormatter(indianMobileNumberLength),
];

/// The backend's `e164` validator (see backend/internal/auth/dto.go)
/// requires the full international form — this is where the fixed +91
/// country code gets attached, right before the number leaves the device.
String toIndianE164(String tenDigits) => '+91$tenDigits';
