# VoiceMapper

Local-only iOS voice-training app. See `docs/PLAN.md`, `docs/WIREFRAMES.md`, and `CLAUDE.md` for the build sessions.

## Run it on your iPhone (first time)
1. On your Mac, install **Xcode 16 or newer** from the Mac App Store.
2. Download this repo (green **Code** button on GitHub → *Download ZIP*, or `git clone`).
3. Double-click `VoiceMapper.xcodeproj` to open it in Xcode.
4. In Xcode: click **VoiceMapper** at the top of the left sidebar → **Signing & Capabilities** → **Team** → *Add an Account…* and sign in with your Apple ID, then pick your name as the Team.
   - If it says the bundle identifier is taken, change `com.thrivestorm2.VoiceMapper` to something unique, e.g. add your initials.
5. Plug in your iPhone with a cable and tap **Trust** on the phone.
6. On the iPhone: **Settings → Privacy & Security → Developer Mode → On** (it restarts).
7. In Xcode's top bar, pick your iPhone as the run destination and press **▶ Run**.
8. First run only: on the iPhone go to **Settings → General → VPN & Device Management**, tap your Apple ID, and tap **Trust**. Then open VoiceMapper.

With a free Apple ID, the app keeps working for 7 days; press Run again to renew it.
