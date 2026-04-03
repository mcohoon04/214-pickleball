# iOS App Distribution Research (Private Group < 50 Users)

## Scope
Distribution options for a small, private iOS user group.

## Primary Sources
- Xcode Help: Distribution methods
  - https://help.apple.com/xcode/mac/current/en.lproj/dev31de635e5.html
- Xcode Help: Distribute using TestFlight
  - https://help.apple.com/xcode/mac/current/en.lproj/dev2539d985f.html
- Xcode Help: Distribute to registered devices (Ad Hoc/Development)
  - https://help.apple.com/xcode/mac/current/en.lproj/dev7ccaf4d3c.html
- Apple Developer Help: Invite external testers
  - https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/
- Apple Developer Enterprise Program
  - https://developer.apple.com/programs/enterprise/
- Apple Developer Help: Create ad hoc provisioning profile
  - https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/

## 1) Options Summary

## TestFlight (App Store Connect method)
From Xcode distribution methods:
- "Distributes your app through TestFlight or the App Store"

From Xcode TestFlight guide:
- Archive -> Validate/Upload -> Invite testers in App Store Connect.
- External testers require Beta App Review.

From App Store Connect Help page:
- External testing supports up to **10,000 external testers per app**.

## Ad Hoc distribution
From Xcode distribution methods and registered-devices guide:
- Uses ad hoc provisioning profile.
- Requires device UDID registration in developer account.
- Device registrations are limited per product family/year.

From Apple ad hoc profile guide:
- Requires App ID + distribution certificate + registered devices.
- Build is exported as IPA and installed manually/Configurator/Xcode.

## Apple Developer Enterprise Program
From Apple Enterprise Program page:
- For proprietary, internal-use apps for employees.
- Eligibility includes organizations with **100+ employees**.
- Intended only when App Store/TestFlight/Apple Business Manager/Ad Hoc are insufficient.

## 2) Recommendation for This Project

Given:
- iOS-only
- < 50 users
- friends/private group

Recommended path: **TestFlight external testing**.

Why:
- Lowest operational overhead (no UDID collection).
- Simple update path (users get new builds through TestFlight).
- No enterprise eligibility burden.
- Scales far beyond target group size.

## 3) TestFlight Steps (Practical)

1. In Xcode, archive app.
2. Validate and upload archive to App Store Connect.
3. In App Store Connect, fill required beta metadata/test notes.
4. Create tester groups:
   - Internal group (required before external group per Apple guidance).
   - External group for private users.
5. Submit build for TestFlight App Review (external testing).
6. Invite testers by email or public link.
7. Users install TestFlight app and accept invite.

### Notes from Apple docs
- External builds are reviewed by Apple (first build usually full review).
- You can submit up to six builds for TestFlight App Review in 24 hours.
- Public links can be capped (1..10,000) and filtered by device/OS criteria.

## 4) When to Use Ad Hoc Instead
Use Ad Hoc only if:
- You cannot use App Store Connect/TestFlight, and
- You can manage UDID collection + profile regeneration, and
- You accept manual install/update friction.

## 5) When Enterprise Is Valid
Use Enterprise only if all are true:
- Organization is eligible (100+ employees, internal-use only),
- App is strictly in-house employee distribution,
- Existing public/custom/TestFlight distribution options are inadequate.

For this pickleball app use case, Enterprise is not appropriate.
