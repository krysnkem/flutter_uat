# flutter-uat walk report

- typed input: ON (fill.allow=mock)
- taps: 22 (limit 60), depth limit 3, distinct screens: 13, unreadable dumps: 0
- host load at start/end: 7.65 / 5.66 (above ~8 timings and ANRs are not app findings)
- ANR dialogs dismissed with Wait: 0
- refused (unsafe): none

## Screens (signature = first non-clickable labels)
- ``  unlabeled controls: 2, merged nodes: 0
    - unlabeled: 124 241 1 <ImageView>
    - unlabeled: 975 241 1 <ImageView>
- `# minutes|# o'clock|PM|Set pickup time|Times are estimated based on p|Today`  unlabeled controls: 2, merged nodes: 0
    - unlabeled: 124 241 1 <ImageView>
    - unlabeled: 975 241 1 <ImageView>
- `Where to?`  unlabeled controls: 3, merged nodes: 0
    - unlabeled: 110 255 1 <Button>
    - unlabeled: 578 502 1 <EditText>
    - unlabeled: 578 651 1 <EditText>
- `My Rides`  unlabeled controls: 0, merged nodes: 4
    - merged: 540 530 y368-692 MERGED? Executive COMPLETED ₦6,600 Eko Hotel & Suites, Adetokunbo Ademola Street, V
    - merged: 540 937 y775-1099 MERGED? KabuKabu COMPLETED ₦4,650 Herbert Macaulay Way, Sabo, Yaba, Lagos November
- `Current balance|My Wallet|November #, #|Transaction History|₦#,#.#`  unlabeled controls: 0, merged nodes: 0
- `#|Loyalty & Rewards|Points Earning History|Reward Points|Ride to Eko Hotel & Suites, Ad|Ri`  unlabeled controls: 1, merged nodes: 0
    - unlabeled: 77 222 1 <Button>
- `Redeem Points|You are about to convert #pts `  unlabeled controls: 0, merged nodes: 0
- `#:# PM|Completed|Date & Time|Payment For|Ride payment - Executive|Status`  unlabeled controls: 0, merged nodes: 0
- `#:# PM|Completed|Date & Time|Payment For|Status|Wallet funding - Card`  unlabeled controls: 0, merged nodes: 0
- `Account Settings|Preferences|Support & Legal|Tolu Adebayo`  unlabeled controls: 1, merged nodes: 0
    - unlabeled: 653 238 1 <ImageView>
- `Email|Full Name|Personal Info|Phone Number|Tap on fields to edit your inf|tolu.adebayo@exa`  unlabeled controls: 1, merged nodes: 0
    - unlabeled: 77 222 1 <Button>
- `Change Password|Current Password|Include at least one number|Include at least one uppercas`  unlabeled controls: 1, merged nodes: 0
    - unlabeled: 77 222 1 <Button>
- `Settings`  unlabeled controls: 1, merged nodes: 0
    - unlabeled: 77 222 1 <Button>

## Transitions
- screen ``: 7 tappable, 0 already tapped
- 'Now' -> # minutes|# o'clock|PM|Set pickup time|Times are e  (depth 0)
- 'Pickup Now' -> Where to?  (depth 1)
- fill: field 1 (text) <- test  [Where to?]
- fill: field 2 (text) <- test  []
- 'Next' -> Where to?  (depth 1)
- lost (landed on a tab root that is not the parent; not pressing back); recovering
- recovered (relaunch)
- tab: Rides
- screen `My Rides`: 0 tappable, 0 already tapped
- tab: Wallet
- screen `Current balance|My Wallet|Nove`: 4 tappable, 0 already tapped
- 'Loyalty & Rewards' -> #|Loyalty & Rewards|Points Earning History|Reward   (depth 0)
- 'Convert points' -> Redeem Points|You are about to convert #pts   (depth 1)
- 'Cancel' returned to the parent screen
- 'Ride payment - Executive 02:26' -> #:# PM|Completed|Date & Time|Payment For|Ride paym  (depth 0)
- 'Close' returned to the parent screen
- 'Wallet funding - Card 01:26 PM' -> #:# PM|Completed|Date & Time|Payment For|Status|Wa  (depth 0)
- 'Close' returned to the parent screen
- tab: Account
- screen `Account Settings|Preferences|S`: 6 tappable, 0 already tapped
- 'Personal Info' -> Email|Full Name|Personal Info|Phone Number|Tap on   (depth 0)
- fill: field 1 (name) <- Test User  [Tolu Adebayo]
- fill: field 2 (phone) <- 8012345678  [2348010000000]
- 'Save Changes' returned to the parent screen
- 'Login & Security' -> Change Password|Current Password|Include at least   (depth 0)
- fill: field 1 (password) <- ***  [Current Password]
- fill: field 2 (password) <- ***  [New Password]
- fill: field 3 (text) <- test  []
- 'Settings' -> Settings  (depth 0)

## Log errors
- none

## Coverage (heuristic lower bound)
```
package: com.example.rider   walks recorded: 31 label sets   route log: 9 screens reported by the app
screens routed: 76   reached: 9   not reached: 45   unmatchable: 22
(reached / (routed - unmatchable) = 16%)
(note: 2 of 9 reached screens come from label guesses only, not the route log; they may be false positives. --show-hints lists them)
```
