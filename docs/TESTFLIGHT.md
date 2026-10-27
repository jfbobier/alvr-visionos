# Publishing to TestFlight

The **TestFlight** workflow (`.github/workflows/testflight.yml`) builds the client, signs it and uploads it to App Store
Connect. It is started by hand: **Actions > TestFlight > Run workflow**. Setup is done once, by whoever holds the Apple
Developer account.

**In short:** (1) in the Apple websites, make the app and an API key; (2) fork the project on GitHub and paste five
values; (3) press **Run workflow**. Each part below is a step-by-step with where to click.
Original project: https://github.com/jfbobier/alvr-visionos

**Use an App Store Connect API key, not the Apple ID.** An Apple ID needs a password and a two-factor code, neither
works in CI. The API key is made for it and can be revoked at any time.

## One-time setup (Apple)

Do this in a web browser, signed in with the Apple ID of the developer account. It takes about 15 minutes. Menu names
can shift a little between Apple updates; the words in **bold** are what to look for. You will end with five values
(the checklist at the end of this part).

**Before you start:** the account must be an active **Apple Developer Program** membership (99 USD a year). Open
https://developer.apple.com/account and accept any agreement banner at the top ("Review Agreement"). Without that,
nothing below works. The person doing this must be the **Account Holder** or an **Admin**.

### 1. Choose and register the bundle ID

The bundle ID is the app's unique name, like a web address backwards. Example: `com.yourname.airframexr` (use your own
name or handle; letters, digits, dots and hyphens only). Pick it once; it cannot be changed later.

1. https://developer.apple.com/account > **Certificates, Identifiers & Profiles** > **Identifiers** > the blue **+**.
2. Choose **App IDs**, **Continue**, then **App**, **Continue**.
3. **Description**: `AirFrameXR`. **Bundle ID**: choose **Explicit** and type your bundle ID.
4. Leave the capabilities as they are, **Continue**, **Register**.

(The next step only offers bundle IDs that are registered, which is why this comes first.)

### 2. Create the app in App Store Connect

1. https://appstoreconnect.apple.com > **Apps** > the **+** (top left) > **New App**.
2. **Platforms**: tick **visionOS**. **Name**: `AirFrameXR` (it must be unique on the whole App Store; if Apple says it is
   taken, use `AirFrameXR Client`: the name is only shown to testers and can be changed later). **Primary Language**:
   English. **Bundle ID**: pick the one from step 1. **SKU**: any text you like, e.g. `airframexr-client` (never shown).
   **User Access**: Full Access.
3. **Create**. You can leave every other page of the app empty: TestFlight does not need a description or screenshots.

### 3. Create the API key (this is what lets GitHub upload for you)

1. App Store Connect > **Users and Access** > the **Integrations** tab > **App Store Connect API** on the left.
   (The first time, an **Account Holder** has to click **Request Access** and accept the terms.)
2. Open **Team Keys** and click the **+** (or **Generate API Key**).
3. **Name**: `GitHub TestFlight`. **Access**: **Admin**. Click **Generate**.
4. In the table, click **Download API Key** next to your new key. **You can download it only once.** You get a file
   named `AuthKey_XXXXXXXXXX.p8`; the ten characters in its name are the **Key ID** (also shown in the table).
5. At the top of the same page, copy the **Issuer ID** (a long code like `69a6de80-...`).
6. Keep the `.p8` file somewhere safe (a password manager is ideal). Anyone who has it and the two IDs can upload builds
   to this team, so never post it. If it leaks: the same page lets you **Revoke** the key at any time.

### 4. Find the Team ID

https://developer.apple.com/account > **Membership details** > **Team ID** (10 characters, letters and digits).

### Checklist: the five values for the next part

| You need | Where you got it |
|---|---|
| Key ID | the file name `AuthKey_<this>.p8`, or the key table (step 3) |
| Issuer ID | top of the App Store Connect API page (step 3) |
| the `.p8` file | the download in step 3 (open it with a text editor and copy everything) |
| Team ID | Membership details (step 4) |
| Bundle ID | the one you registered (step 1) |

### After the first upload: add testers

The first upload takes 10 to 20 minutes to be "processed"; you get an email. Then in App Store Connect > your app >
**TestFlight**:

- The build shows a yellow **Manage** / "Missing Compliance" warning: click it and answer the encryption question once
  (the app only uses the standard encryption of the operating system's network stack).
- **Internal testers** (fast, no review): people you add under **Users and Access** (they need an Apple ID and are given
  a role there, e.g. **Developer**). Then in TestFlight, **Internal Testing** > **+** > a group > add them. They
  install the **TestFlight** app on the Vision Pro and the build appears.
- **External testers** (a Discord group, for example; they need only an email address or a link and no developer
  account): **External Testing** > **+** > a group > **Enable Public Link** to share one link. The first build of a
  version goes through a short **Beta App Review** (usually under a day).

## One-time setup (GitHub)

GitHub keeps the secrets, so you need your **own copy** of this project on your GitHub account: a **fork**. (Only the
owner of a repository can store secrets in it, and the secrets must stay yours anyway.) Nothing here needs any
programming: it is clicking and pasting. `<you>` below is your GitHub user name.

### A. Make your copy (fork)

1. Sign in to https://github.com (create a free account if you have none).
2. Open **https://github.com/jfbobier/alvr-visionos**.
3. At the top right of the page, click **Fork** (the button with the little branching icon).
4. On the next page leave everything as it is, make sure **Owner** is your own user name, and click the green
   **Create fork**. After a few seconds you are on `https://github.com/<you>/alvr-visionos`: that is your copy.
   Everything below happens there, not on the original.

### B. Switch on the automatic builds in your copy

GitHub turns them off in new forks.

1. In your copy, click the **Actions** tab (top menu, next to Pull requests).
2. Click the green **I understand my workflows, go ahead and enable them**.

### C. Enter the five values

Open **https://github.com/`<you>`/alvr-visionos/settings/secrets/actions** (or: your copy > **Settings** (top menu,
far right) > on the left **Secrets and variables** > **Actions**). Use the values from the checklist above.

Secrets (the **Secrets** tab, button **New repository secret**; click it once per secret, then **Add secret**):

| Name (type it exactly) | Value |
|---|---|
| `ASC_KEY_ID` | the Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `ASC_KEY_P8` | open the `.p8` file with Notepad or TextEdit, select everything (Ctrl+A / Cmd+A), copy, paste. It must include the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines |

Variables (the **Variables** tab next to Secrets, button **New repository variable**, then **Add variable**):

| Name (type it exactly) | Value |
|---|---|
| `APPLE_TEAM_ID` | the Team ID |
| `BUNDLE_ID` | the bundle ID |

Names are case sensitive. If one is wrong or missing, the first step of the build stops and tells you which.

### D. Try it without Apple first (optional, 30 seconds of clicking)

1. Your copy > **Actions** tab > on the left, click **TestFlight**.
2. Click **Run workflow** (a grey button on the right), tick **Only check that the Release archive builds**, and click
   the green **Run workflow**.
3. Refresh the page after a few seconds: a new line appears. Click it. After about 10 to 15 minutes a green tick means
   the app builds. (A red cross: send the page's link to whoever helps you.)

### E. Upload to TestFlight

Same place: **Actions** > **TestFlight** > **Run workflow**, this time leave the check box **unticked**, optionally
change the version number, and click the green **Run workflow**. Direct link:
**https://github.com/`<you>`/alvr-visionos/actions/workflows/testflight.yml**. A green tick after about 20 to 30
minutes means the build is at Apple; the email "has completed processing" follows.

### Getting newer versions of the app later

On your copy's main page there is a **Sync fork** button (under the green Code button, above the file list): click it,
then **Update branch**. Then run the workflow again (step E).

## Each release

1. In your copy: **Actions > TestFlight > Run workflow** (step E). Choose the version shown in TestFlight (default `0.1.0`). The build number is
   the run number, so it always goes up.
2. Wait for the run (about 20 to 30 minutes), then for App Store Connect to process the build (about 10 more).
3. App Store Connect > your app > **TestFlight** (see "After the first upload" above for compliance and testers).

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

## Optional, for developers: upload from a Mac with Xcode instead

You do not need this: the workflow above is the supported way. It is only an alternative if you are comfortable with
Xcode and the command line; Xcode signs with the Apple ID you are signed in with and shows every error in place.
You need Xcode 27 and a one-time Rust setup:

1. `brew install rustup cbindgen`, then `rustup-init -y` and `rustup target add aarch64-apple-ios`.
2. `git clone --recursive https://github.com/jfbobier/alvr-visionos` and `cd alvr-visionos`.
3. `sh build_and_repack.sh` (builds the client core and the xcframework; the same steps as the workflow).
4. `open ALVRClient.xcodeproj`. In the **ALVRClient** target > **Signing & Capabilities**: your Team, your bundle ID
   (the app record from step 2 above must exist). Remove **Low Latency Streaming** there if Xcode says your account
   cannot have it.
5. Destination **Any visionOS Device**, then **Product > Archive**, then **Distribute App > App Store Connect >
   Upload**.

Both ways produce the same app.
