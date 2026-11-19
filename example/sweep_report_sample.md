# flutter-uat sweep: com.example.rider

- paths: 41   BLANK 4   CRASH 1   OPEN 36
- distinct screen classes confirmed by the route log: 27  (OPEN with no class logged: 4)
- duration 725s

| path | verdict | class | labels | note | reproduces alone | |
|---|---|---|---|---|---|---|
| /dashboard/account | OPEN | RiderAccountScreen | 14 |  | - |  |
| /dashboard/home | OPEN | MaterialErrorScreen | 3 |  | - |  |
| /dashboard/rides | OPEN | RideScreen | 10 |  | - |  |
| /dashboard/wallet | OPEN | RiderWalletScreen | 12 |  | - |  |
| /rider/add-funds | OPEN | RiderAddFundsScreen | 13 |  | - |  |
| /rider/add-home | OPEN | AddHomeScreen | 4 |  | - |  |
| /rider/add-pay-method | OPEN | RiderAddPaymentMethodScreen | 4 |  | - |  |
| /rider/add-place | OPEN | MaterialErrorScreen | 3 |  | - |  |
| /rider/add-work | OPEN | AddWorkScreen | 3 |  | - |  |
| /rider/change-password-otp | OPEN | RiderChangePasswordOtpScreen | 3 |  | - |  |
| /rider/chat-us-screen | OPEN | ChatUsScreen | 6 |  | - |  |
| /rider/choose-contact | OPEN | ChooseContactScreen | 5 |  | - |  |
| /rider/complaint-form | OPEN | RiderComplaintFormScreen | 9 |  | - |  |
| /rider/dashboard-screen | OPEN | RiderDashboardScreen | 11 |  | - |  |
| /rider/edit-account-screen | OPEN | RiderEditAccountScreen | 6 |  | - |  |
| /rider/emergency-contact | OPEN | - | 7 |  | - |  |
| /rider/help-screen | OPEN | RiderHelpScreen | 7 |  | - |  |
| /rider/home-screen | OPEN | - | 6 |  | - |  |
| /rider/login-security-screen | OPEN | RiderLoginAndSecurityScreen | 6 |  | - |  |
| /rider/loyalty-rewards | OPEN | RiderLoyaltyRewardsScreen | 11 |  | - |  |
| /rider/manage-pay-methods | OPEN | RiderManagePayMethodScreen | 3 |  | - |  |
| /rider/manage-payment-cards | OPEN | ManageCardScreen | 6 |  | - |  |
| /rider/modify-ride | OPEN | RiderModifyRideScreen | 17 |  | - |  |
| /rider/name-this-place | BLANK | - | 0 |  | yes |  |
| /rider/notification-screen | BLANK | NotificationsScreen | 1 |  | yes |  |
| /rider/onboarding-screen | OPEN | RiderOnboardingScreen | 2 |  | - |  |
| /rider/otp-screen | OPEN | MaterialErrorScreen | 3 |  | - |  |
| /rider/otp-success-screen | OPEN | RiderOtpSuccessScreen | 5 |  | - |  |
| /rider/passkey-screen | OPEN | - | 7 |  | - |  |
| /rider/privacy-policy | OPEN | PrivacyPolicyScreen | 3 |  | - |  |
| /rider/ride-details | BLANK | RideDetailsScreen | 0 |  | yes |  |
| /rider/ride-screen | OPEN | RideScreen | 6 |  | - |  |
| /rider/rider-chat-screen | BLANK | RiderChatScreen | 1 |  | yes |  |
| /rider/saved-places | CRASH/ORDER-DEPENDENT | SavedPlacesScreen | 7 | java.lang.NullPointerException: Attempt to invoke virtual method 'boolean com.chatsdk.adapter.EMAChatCl | no (opens alone) |  |
| /rider/settings-screen | OPEN | - | 3 |  | - |  |
| /rider/sign-in | OPEN | RiderSignInScreen | 16 |  | - |  |
| /rider/sign-in-otp | OPEN | RiderSignInOtpScreen | 5 |  | - |  |
| /rider/sign-up | OPEN | RiderSignUpScreen | 14 |  | - |  |
| /rider/sign-up-otp | OPEN | RiderSignUpOtpScreen | 8 |  | - |  |
| /rider/splash-screen | OPEN | RiderOnboardingScreen | 2 |  | - |  |
| /rider/wallet-screen | OPEN | RiderWalletScreen | 8 |  | - |  |
