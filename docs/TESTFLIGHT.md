# Publishing to TestFlight

The **TestFlight** workflow (`.github/workflows/testflight.yml`) builds the client, signs it and uploads it to App Store
Connect. It is started by hand: **Actions > TestFlight > Run workflow**. Setup is done once, by whoever holds the Apple
Developer account.

**Use an App Store Connect API key, not the Apple ID.** An Apple ID needs a password and a two-factor code, neither
works in CI. The API key is made for it and can be revoked at any time.

## One-time setup (Apple)

1. **Bundle ID.** Pick one, e.g. `com.yourname.airframexr` (reverse-domain, unique to your team).
2. **App record.** App Store Connect > Apps > **+ New App**: platform **visionOS**, name *AirFrameXR*, your bundle ID,
   any SKU. The upload is refused until this exists.
3. **API key.** App Store Connect > Users and Access > Integrations > **App Store Connect API** > Team Keys > **+**,
   access **Admin** (Xcode needs it to create the distribution certificate and profile for you). Download the `.p8`
   file (only possible once) and note the **Key ID** and the **Issuer ID** shown above the table.
4. **Team ID.** developer.apple.com > Membership details: the 10-character Team ID.

## One-time setup (GitHub)

Only the **owner** of a repository can add secrets, and on a personal account a collaborator is never an owner. So the
person who holds the Apple account **forks this repository into their own account** and does everything below there
(the key then never leaves their account):

1. Open the repository page and click **Fork**, keep the default branch name.
2. In the fork, open the **Actions** tab and click **I understand my workflows, go ahead and enable them**.
3. In the fork, open **Settings > Secrets and variables > Actions** and add:

| Kind | Name | Value |
|---|---|---|
| Secret | `ASC_KEY_ID` | the Key ID |
| Secret | `ASC_ISSUER_ID` | the Issuer ID |
| Secret | `ASC_KEY_P8` | the whole `.p8` file, `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines included |
| Variable | `APPLE_TEAM_ID` | the Team ID |
| Variable | `BUNDLE_ID` | the bundle ID |

If a value is missing, the first step of the workflow says which one.

To get new changes later, use **Sync fork** on the fork's page.

## Each release

1. In the fork: **Actions > TestFlight > Run workflow.** Choose the version shown in TestFlight (default `0.1.0`). The build number is
   the run number, so it always goes up.
2. Wait for the run (about 20 to 30 minutes), then for App Store Connect to process the build (about 10 more).
3. App Store Connect > your app > **TestFlight**. Answer the export-compliance question the first time. Add testers:
   **internal** testers (people on your team, up to 100) get the build at once; **external** testers need a short
   Beta App Review first.

## Check the build first (optional, no secrets)

**Run workflow** with **Only check that the Release archive builds** ticked: it builds the same Release archive without
signing and uploads nothing. It confirms the project compiles in Release and prints the bundle ID, name and version.
(It passes on the current branch.)

## If something fails

- **Signing complains about `com.apple.developer.low-latency-streaming`** (or "profile doesn't include entitlement"):
  that capability is not available to your App ID. Run the workflow again with **Include the low-latency-streaming
  entitlement** unticked. The app works without it; the entitlement is for network prioritisation.
- **"No profiles for ... were found" or a certificate error:** the API key does not have the Admin role, or the team
  already has the maximum number of distribution certificates (delete an unused one in the developer portal).
- **The upload is refused as a duplicate:** a build with the same version and build number exists; run the workflow
  again (the run number increases).
- The `testflight-logs` artifact of the run has the full `xcodebuild` output.

## What the build contains

Metal-only client, the AirFrameXR icon, bundle ID and team from the variables above, and no ReplayKit extension (the
old eye-tracking extension was removed with the RealityKit renderer, so no app group is needed either).
The app is signed with the cloud-managed distribution certificate; no certificate or profile is stored in GitHub.
