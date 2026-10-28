import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fil.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil')
  ];

  /// No description provided for @selectLanguage.
  ///
  /// In en, this message translates to:
  /// **'Select Language'**
  String get selectLanguage;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @languageSet.
  ///
  /// In en, this message translates to:
  /// **'Language set to {language}'**
  String languageSet(Object language);

  /// No description provided for @protectingOurOceanTitle.
  ///
  /// In en, this message translates to:
  /// **'Protecting Our Ocean'**
  String get protectingOurOceanTitle;

  /// No description provided for @protectingOurOceanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sustainable fishing for future generations'**
  String get protectingOurOceanSubtitle;

  /// No description provided for @illegalFishingLawsTitle.
  ///
  /// In en, this message translates to:
  /// **'Illegal Fishing Laws'**
  String get illegalFishingLawsTitle;

  /// No description provided for @illegalFishingLawsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Learn the laws protecting our marine resources'**
  String get illegalFishingLawsSubtitle;

  /// No description provided for @whyMarineBiodiversityMattersTitle.
  ///
  /// In en, this message translates to:
  /// **'Why Marine Biodiversity Matters'**
  String get whyMarineBiodiversityMattersTitle;

  /// No description provided for @whyMarineBiodiversityMattersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Biodiversity keeps our oceans healthy and balanced'**
  String get whyMarineBiodiversityMattersSubtitle;

  /// No description provided for @educationalInfographicsTitle.
  ///
  /// In en, this message translates to:
  /// **'Educational Infographics'**
  String get educationalInfographicsTitle;

  /// No description provided for @educationalInfographicsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visual learning on marine protection'**
  String get educationalInfographicsSubtitle;

  /// No description provided for @sustainableFishingForTheFutureTitle.
  ///
  /// In en, this message translates to:
  /// **'Sustainable Fishing for the Future'**
  String get sustainableFishingForTheFutureTitle;

  /// No description provided for @sustainableFishingForTheFutureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Learn the importance of responsible fishing.'**
  String get sustainableFishingForTheFutureSubtitle;

  /// No description provided for @understandingTheLawsToProtectMarineLifeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Understanding the laws to protect marine life.'**
  String get understandingTheLawsToProtectMarineLifeSubtitle;

  /// No description provided for @exploreHowBiodiversitySustainsTheOceanSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Explore how biodiversity sustains the ocean.'**
  String get exploreHowBiodiversitySustainsTheOceanSubtitle;

  /// No description provided for @visualInsightsIntoMarineConservationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Visual insights into marine conservation.'**
  String get visualInsightsIntoMarineConservationSubtitle;

  /// No description provided for @termsAndConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsAndConditions;

  /// No description provided for @introduction.
  ///
  /// In en, this message translates to:
  /// **'1. Introduction'**
  String get introduction;

  /// No description provided for @introductionText.
  ///
  /// In en, this message translates to:
  /// **'By using this application, you agree to follow these Terms and Conditions. Please read them carefully.'**
  String get introductionText;

  /// No description provided for @userResponsibilities.
  ///
  /// In en, this message translates to:
  /// **'2. User Responsibilities'**
  String get userResponsibilities;

  /// No description provided for @accurateInformation.
  ///
  /// In en, this message translates to:
  /// **'You must provide accurate information when creating an account.'**
  String get accurateInformation;

  /// No description provided for @accountConfidentiality.
  ///
  /// In en, this message translates to:
  /// **'You are responsible for maintaining the confidentiality of your account.'**
  String get accountConfidentiality;

  /// No description provided for @restrictions.
  ///
  /// In en, this message translates to:
  /// **'3. Restrictions'**
  String get restrictions;

  /// No description provided for @noIllegalActivities.
  ///
  /// In en, this message translates to:
  /// **'Do not use the app for illegal activities.'**
  String get noIllegalActivities;

  /// No description provided for @noHacking.
  ///
  /// In en, this message translates to:
  /// **'Do not attempt to hack, exploit, or disrupt services.'**
  String get noHacking;

  /// No description provided for @dataPrivacy.
  ///
  /// In en, this message translates to:
  /// **'4. Data Privacy'**
  String get dataPrivacy;

  /// No description provided for @privacyText.
  ///
  /// In en, this message translates to:
  /// **'We respect your privacy. Any personal information you provide will be handled according to our Privacy Policy.'**
  String get privacyText;

  /// No description provided for @limitationOfLiability.
  ///
  /// In en, this message translates to:
  /// **'5. Limitation of Liability'**
  String get limitationOfLiability;

  /// No description provided for @liabilityText.
  ///
  /// In en, this message translates to:
  /// **'We are not liable for any damages resulting from the use of this application.'**
  String get liabilityText;

  /// No description provided for @changesToTerms.
  ///
  /// In en, this message translates to:
  /// **'6. Changes to Terms'**
  String get changesToTerms;

  /// No description provided for @changesText.
  ///
  /// In en, this message translates to:
  /// **'We may update these Terms at any time. Continued use of the app means you accept the new Terms.'**
  String get changesText;

  /// No description provided for @agreeToTerms.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms and Conditions'**
  String get agreeToTerms;

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @acceptedTerms.
  ///
  /// In en, this message translates to:
  /// **'✅ Accepted Terms & Conditions'**
  String get acceptedTerms;

  /// No description provided for @emailOrMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Email or Mobile Number'**
  String get emailOrMobileNumber;

  /// No description provided for @enterYourEmailOrNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your email or number'**
  String get enterYourEmailOrNumber;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @enterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get enterYourPassword;

  /// No description provided for @rememberPassword.
  ///
  /// In en, this message translates to:
  /// **'Remember Password'**
  String get rememberPassword;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log In'**
  String get logIn;

  /// No description provided for @dontHaveAnAccountSignup.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get dontHaveAnAccountSignup;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @todaysForecast.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Forecast'**
  String get todaysForecast;

  /// No description provided for @safeToFish.
  ///
  /// In en, this message translates to:
  /// **'Safe to Fish'**
  String get safeToFish;

  /// No description provided for @reportIllegalActivities.
  ///
  /// In en, this message translates to:
  /// **'Report Illegal Activities'**
  String get reportIllegalActivities;

  /// No description provided for @marineLife.
  ///
  /// In en, this message translates to:
  /// **'Fish Production Data'**
  String get marineLife;

  /// No description provided for @marineSighting.
  ///
  /// In en, this message translates to:
  /// **'Marine Sighting'**
  String get marineSighting;

  /// No description provided for @educationalResources.
  ///
  /// In en, this message translates to:
  /// **'Educational Resources'**
  String get educationalResources;

  /// No description provided for @educationalSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Educational Resources'**
  String get educationalSectionTitle;

  /// No description provided for @seeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get seeMore;

  /// No description provided for @seeMoreButton.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get seeMoreButton;

  /// No description provided for @sustainableFishingLawsButton.
  ///
  /// In en, this message translates to:
  /// **'Sustainable Fishing Laws'**
  String get sustainableFishingLawsButton;

  /// No description provided for @whyMarineBiodiversityMattersButton.
  ///
  /// In en, this message translates to:
  /// **'Why Marine Biodiversity Matters'**
  String get whyMarineBiodiversityMattersButton;

  /// No description provided for @illegalFishingLawsButton.
  ///
  /// In en, this message translates to:
  /// **'Illegal Fishing Laws'**
  String get illegalFishingLawsButton;

  /// No description provided for @videoInfographicsSection.
  ///
  /// In en, this message translates to:
  /// **'Video & Infographics'**
  String get videoInfographicsSection;

  /// No description provided for @watchOnYouTube.
  ///
  /// In en, this message translates to:
  /// **'Watch on YouTube'**
  String get watchOnYouTube;

  /// No description provided for @educationalSectionPageTitle.
  ///
  /// In en, this message translates to:
  /// **'Educational Section'**
  String get educationalSectionPageTitle;

  /// No description provided for @categoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get categoryLabel;

  /// No description provided for @youtubeCom.
  ///
  /// In en, this message translates to:
  /// **'YouTube.com'**
  String get youtubeCom;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit Profile'**
  String get editProfile;

  /// No description provided for @failedToLoadUserData.
  ///
  /// In en, this message translates to:
  /// **'Failed to load user data'**
  String get failedToLoadUserData;

  /// No description provided for @accountManagement.
  ///
  /// In en, this message translates to:
  /// **'Account Management'**
  String get accountManagement;

  /// No description provided for @recentReports.
  ///
  /// In en, this message translates to:
  /// **'Recent Reports'**
  String get recentReports;

  /// No description provided for @yourRecentIllegalFishingReports.
  ///
  /// In en, this message translates to:
  /// **'Your recent illegal fishing reports'**
  String get yourRecentIllegalFishingReports;

  /// No description provided for @educationalMaterials.
  ///
  /// In en, this message translates to:
  /// **'Educational Materials'**
  String get educationalMaterials;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logOut;

  /// No description provided for @continueCreatingYourAccount.
  ///
  /// In en, this message translates to:
  /// **'Continue Creating Your Account'**
  String get continueCreatingYourAccount;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @orContinueWith.
  ///
  /// In en, this message translates to:
  /// **'or continue with'**
  String get orContinueWith;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// No description provided for @alreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get alreadyHaveAnAccount;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Login'**
  String get login;

  /// No description provided for @pleaseCompleteAllRequiredFields.
  ///
  /// In en, this message translates to:
  /// **'Please complete all required fields'**
  String get pleaseCompleteAllRequiredFields;

  /// No description provided for @youMustBeAtLeast18YearsOldToRegister.
  ///
  /// In en, this message translates to:
  /// **'You must be at least 12 years old to register'**
  String get youMustBeAtLeast18YearsOldToRegister;

  /// No description provided for @personalInformation.
  ///
  /// In en, this message translates to:
  /// **'Personal Information'**
  String get personalInformation;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @birthdate.
  ///
  /// In en, this message translates to:
  /// **'Birthdate'**
  String get birthdate;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @fisherman.
  ///
  /// In en, this message translates to:
  /// **'Fisherman'**
  String get fisherman;

  /// No description provided for @resident.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get resident;

  /// No description provided for @gender.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get gender;

  /// No description provided for @female.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get female;

  /// No description provided for @male.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get male;

  /// No description provided for @region.
  ///
  /// In en, this message translates to:
  /// **'Region'**
  String get region;

  /// No description provided for @province.
  ///
  /// In en, this message translates to:
  /// **'Province'**
  String get province;

  /// No description provided for @municipalityCity.
  ///
  /// In en, this message translates to:
  /// **'Municipality/City'**
  String get municipalityCity;

  /// No description provided for @barangay.
  ///
  /// In en, this message translates to:
  /// **'Barangay'**
  String get barangay;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @signup.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signup;

  /// No description provided for @accountDeletedSuccessfullyItWillBePermanentlyRemovedAfter30Days.
  ///
  /// In en, this message translates to:
  /// **'Account deleted successfully. It will be permanently removed after 30 days.'**
  String get accountDeletedSuccessfullyItWillBePermanentlyRemovedAfter30Days;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @yesDelete.
  ///
  /// In en, this message translates to:
  /// **'Yes, Delete'**
  String get yesDelete;

  /// No description provided for @errorDeletingAccount.
  ///
  /// In en, this message translates to:
  /// **'Error deleting account'**
  String get errorDeletingAccount;

  /// No description provided for @incorrectPasswordPleaseTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password. Please try again.'**
  String get incorrectPasswordPleaseTryAgain;

  /// No description provided for @forSecurityPleaseLogInAgainBeforeDeletingYourAccount.
  ///
  /// In en, this message translates to:
  /// **'For security, please log in again before deleting your account.'**
  String get forSecurityPleaseLogInAgainBeforeDeletingYourAccount;

  /// No description provided for @pleaseConfirmYourPasswordToProceedWithAccountDeletionNoteYourAccountWillBePermanentlyDeletedAfter30Days.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password to proceed with account deletion. Note: Your account will be permanently deleted after 30 days.'**
  String get pleaseConfirmYourPasswordToProceedWithAccountDeletionNoteYourAccountWillBePermanentlyDeletedAfter30Days;

  /// No description provided for @areYouSureYouWantToDeleteYourAccountThisActionCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete your account? This action cannot be undone.'**
  String get areYouSureYouWantToDeleteYourAccountThisActionCannotBeUndone;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error'**
  String get unexpectedError;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @enterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter Password'**
  String get enterPassword;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @changeUsername.
  ///
  /// In en, this message translates to:
  /// **'Change Username'**
  String get changeUsername;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @pleaseEnterYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password'**
  String get pleaseEnterYourPassword;

  /// No description provided for @noUserIsCurrentlySignedIn.
  ///
  /// In en, this message translates to:
  /// **'No user is currently signed in'**
  String get noUserIsCurrentlySignedIn;

  /// No description provided for @userDoesNotHaveAnEmailOnRecord.
  ///
  /// In en, this message translates to:
  /// **'User does not have an email on record'**
  String get userDoesNotHaveAnEmailOnRecord;

  /// No description provided for @passwordUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully'**
  String get passwordUpdatedSuccessfully;

  /// No description provided for @errorChangingPassword.
  ///
  /// In en, this message translates to:
  /// **'Error changing password'**
  String get errorChangingPassword;

  /// No description provided for @currentPasswordIsIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get currentPasswordIsIncorrect;

  /// No description provided for @passwordShouldBeAtLeast6Characters.
  ///
  /// In en, this message translates to:
  /// **'Password should be at least 6 characters'**
  String get passwordShouldBeAtLeast6Characters;

  /// No description provided for @pleaseLogInAgainBeforeChangingYourPasswordForSecurityReasons.
  ///
  /// In en, this message translates to:
  /// **'Please log in again before changing your password for security reasons'**
  String get pleaseLogInAgainBeforeChangingYourPasswordForSecurityReasons;

  /// No description provided for @currentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current Password'**
  String get currentPassword;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New Password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm New Password'**
  String get confirmNewPassword;

  /// No description provided for @pleaseConfirmYourNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your new password'**
  String get pleaseConfirmYourNewPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'Update Password'**
  String get updatePassword;

  /// No description provided for @pleaseEnter.
  ///
  /// In en, this message translates to:
  /// **'Please enter'**
  String get pleaseEnter;

  /// No description provided for @passwordMustBeAtLeast6Characters.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get passwordMustBeAtLeast6Characters;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @changeUsernameTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Username'**
  String get changeUsernameTitle;

  /// No description provided for @currentUsername.
  ///
  /// In en, this message translates to:
  /// **'Current Username'**
  String get currentUsername;

  /// No description provided for @enterPasswordForVerification.
  ///
  /// In en, this message translates to:
  /// **'Enter Password for Verification'**
  String get enterPasswordForVerification;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @passwordVerified.
  ///
  /// In en, this message translates to:
  /// **'Password Verified'**
  String get passwordVerified;

  /// No description provided for @incorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect Password'**
  String get incorrectPassword;

  /// No description provided for @usernameUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Username Updated Successfully'**
  String get usernameUpdatedSuccessfully;

  /// No description provided for @errorUpdatingFirestore.
  ///
  /// In en, this message translates to:
  /// **'Error Updating Firestore'**
  String get errorUpdatingFirestore;

  /// No description provided for @emailUpdatedAVerificationEmailHasBeenSentToYourNewAddressPleaseVerifyIt.
  ///
  /// In en, this message translates to:
  /// **'Email Updated. A verification email has been sent to your new address. Please verify it.'**
  String get emailUpdatedAVerificationEmailHasBeenSentToYourNewAddressPleaseVerifyIt;

  /// No description provided for @pleaseVerifyYourPasswordAgainBeforeChangingEmail.
  ///
  /// In en, this message translates to:
  /// **'Please verify your password again before changing email.'**
  String get pleaseVerifyYourPasswordAgainBeforeChangingEmail;

  /// No description provided for @failedToUpdateEmail.
  ///
  /// In en, this message translates to:
  /// **'Failed to Update Email'**
  String get failedToUpdateEmail;

  /// No description provided for @verificationFailed.
  ///
  /// In en, this message translates to:
  /// **'Verification Failed'**
  String get verificationFailed;

  /// No description provided for @phoneNumberVerifiedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Phone Number Verified Successfully'**
  String get phoneNumberVerifiedSuccessfully;

  /// No description provided for @invalidOTP.
  ///
  /// In en, this message translates to:
  /// **'Invalid OTP'**
  String get invalidOTP;

  /// No description provided for @enterOTP.
  ///
  /// In en, this message translates to:
  /// **'Enter OTP'**
  String get enterOTP;

  /// No description provided for @sixDigitCode.
  ///
  /// In en, this message translates to:
  /// **'Six Digit Code'**
  String get sixDigitCode;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @newEmailOrMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'New Email or Mobile Number'**
  String get newEmailOrMobileNumber;

  /// No description provided for @enterNewEmailOrMobileNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter New Email or Mobile Number'**
  String get enterNewEmailOrMobileNumber;

  /// No description provided for @pleaseEnterSomething.
  ///
  /// In en, this message translates to:
  /// **'Please Enter Something'**
  String get pleaseEnterSomething;

  /// No description provided for @enterAValidEmailOrPhilippineNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a Valid Email or Philippine Number'**
  String get enterAValidEmailOrPhilippineNumber;

  /// No description provided for @verifyUpdate.
  ///
  /// In en, this message translates to:
  /// **'Verify Update'**
  String get verifyUpdate;

  /// No description provided for @enterFirstName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your first name'**
  String get enterFirstName;

  /// No description provided for @enterLastName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your last name'**
  String get enterLastName;

  /// No description provided for @userRole.
  ///
  /// In en, this message translates to:
  /// **'Resident'**
  String get userRole;

  /// No description provided for @profileUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Profile updated successfully'**
  String get profileUpdatedSuccessfully;

  /// No description provided for @errorPrefix.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get errorPrefix;

  /// No description provided for @changeEmail.
  ///
  /// In en, this message translates to:
  /// **'Change Email'**
  String get changeEmail;

  /// No description provided for @currentEmail.
  ///
  /// In en, this message translates to:
  /// **'Current Email'**
  String get currentEmail;

  /// No description provided for @newEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'New Email Address'**
  String get newEmailAddress;

  /// No description provided for @enterNewEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter New Email Address'**
  String get enterNewEmailAddress;

  /// No description provided for @pleaseEnterAnEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter an email address'**
  String get pleaseEnterAnEmailAddress;

  /// No description provided for @pleaseEnterAValidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get pleaseEnterAValidEmailAddress;

  /// No description provided for @updateEmail.
  ///
  /// In en, this message translates to:
  /// **'Update Email'**
  String get updateEmail;

  /// No description provided for @offlineLearningMaterialsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tips and Guide'**
  String get offlineLearningMaterialsTitle;

  /// No description provided for @offlineLearningMaterialsIntro.
  ///
  /// In en, this message translates to:
  /// **'Learn about safe fishing, marine protection, and proper reporting even when you\'re offline.'**
  String get offlineLearningMaterialsIntro;

  /// No description provided for @offlineLearningSustainableTitle.
  ///
  /// In en, this message translates to:
  /// **'Sustainable Fishing Guide'**
  String get offlineLearningSustainableTitle;

  /// No description provided for @offlineLearningSustainableContent.
  ///
  /// In en, this message translates to:
  /// **'Remember:\n- Use legal fishing gear only.\n- Avoid dynamite or cyanide fishing.\n- Do not catch small or young fish.\n- Follow BFAR fishing seasons and rules.\n\nWhy it matters:\nIt protects marine life and ensures long-term livelihood for fishermen.'**
  String get offlineLearningSustainableContent;

  /// No description provided for @offlineLearningBiodiversityTitle.
  ///
  /// In en, this message translates to:
  /// **'Marine Biodiversity Basics'**
  String get offlineLearningBiodiversityTitle;

  /// No description provided for @offlineLearningBiodiversityContent.
  ///
  /// In en, this message translates to:
  /// **'Examples:\nFish, coral, seagrass, and sea turtles.\n\nWhy it matters:\n- Coral reefs protect our shores from waves.\n- They serve as nurseries for fish.\n- They support fishing communities and tourism.'**
  String get offlineLearningBiodiversityContent;

  /// No description provided for @offlineLearningIllegalTitle.
  ///
  /// In en, this message translates to:
  /// **'Illegal Fishing Awareness'**
  String get offlineLearningIllegalTitle;

  /// No description provided for @offlineLearningIllegalContent.
  ///
  /// In en, this message translates to:
  /// **'Examples:\n- Using dynamite or poison.\n- Fishing in protected marine zones.\n- Using fine-mesh nets that catch small fish.\n\nHow to report:\nOpen the app > tap Report > select Illegal Fishing > add details and a photo.'**
  String get offlineLearningIllegalContent;

  /// No description provided for @offlineLearningConservationTitle.
  ///
  /// In en, this message translates to:
  /// **'Marine Conservation Tips'**
  String get offlineLearningConservationTitle;

  /// No description provided for @offlineLearningConservationContent.
  ///
  /// In en, this message translates to:
  /// **'Simple ways to protect the ocean:\n- Do not throw trash into the sea.\n- Avoid single-use plastics.\n- Join coastal cleanup events.\n- Report any pollution or damage you see.\n\nRemember:\nSmall actions make a big difference for the ocean.'**
  String get offlineLearningConservationContent;

  /// No description provided for @adminDashboardTitle.
  ///
  /// In en, this message translates to:
  /// **'DASHBOARD'**
  String get adminDashboardTitle;

  /// No description provided for @adminEducationalTitle.
  ///
  /// In en, this message translates to:
  /// **'EDUCATIONAL'**
  String get adminEducationalTitle;

  /// No description provided for @adminNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get adminNotificationsTitle;

  /// No description provided for @adminAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get adminAccountTitle;

  /// No description provided for @adminRoleTitle.
  ///
  /// In en, this message translates to:
  /// **'SeaGuard Administrator'**
  String get adminRoleTitle;

  /// No description provided for @adminAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage system preferences, profile details, language settings, and secure access from one place.'**
  String get adminAccountSubtitle;

  /// No description provided for @adminTodaysForecast.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Forecast'**
  String get adminTodaysForecast;

  /// No description provided for @adminSeeMore.
  ///
  /// In en, this message translates to:
  /// **'See More'**
  String get adminSeeMore;

  /// No description provided for @adminIllegalActivitiesReports.
  ///
  /// In en, this message translates to:
  /// **'Illegal Activities Reports'**
  String get adminIllegalActivitiesReports;

  /// No description provided for @adminReportEmergency.
  ///
  /// In en, this message translates to:
  /// **'Report Emergency'**
  String get adminReportEmergency;

  /// No description provided for @adminShareLocationCta.
  ///
  /// In en, this message translates to:
  /// **'Share Location\n(Your current location will be sent to PCG)'**
  String get adminShareLocationCta;

  /// No description provided for @adminMarkAllRead.
  ///
  /// In en, this message translates to:
  /// **'Mark all as read'**
  String get adminMarkAllRead;

  /// No description provided for @adminClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get adminClearAll;

  /// No description provided for @adminRecentUpdates.
  ///
  /// In en, this message translates to:
  /// **'Recent Updates'**
  String get adminRecentUpdates;

  /// No description provided for @adminNoTitle.
  ///
  /// In en, this message translates to:
  /// **'No Title'**
  String get adminNoTitle;

  /// No description provided for @adminNoMessage.
  ///
  /// In en, this message translates to:
  /// **'No Message'**
  String get adminNoMessage;

  /// No description provided for @adminProfileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get adminProfileTitle;

  /// No description provided for @adminQuickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get adminQuickActions;

  /// No description provided for @adminSystemActivity.
  ///
  /// In en, this message translates to:
  /// **'System Activity'**
  String get adminSystemActivity;

  /// No description provided for @adminSystemActivitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review recent admin events, monitoring logs, and platform actions.'**
  String get adminSystemActivitySubtitle;

  /// No description provided for @adminLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get adminLanguage;

  /// No description provided for @adminLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the language used across the admin dashboard.'**
  String get adminLanguageSubtitle;

  /// No description provided for @adminTermsConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms and Conditions'**
  String get adminTermsConditions;

  /// No description provided for @adminTermsConditionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read the policies, responsibilities, and legal terms for the platform.'**
  String get adminTermsConditionsSubtitle;

  /// No description provided for @adminEditProfileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Update administrator details and manage assigned PCG information.'**
  String get adminEditProfileSubtitle;

  /// No description provided for @adminLoggingOut.
  ///
  /// In en, this message translates to:
  /// **'Logging out...'**
  String get adminLoggingOut;

  /// No description provided for @adminLogOut.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get adminLogOut;

  /// No description provided for @adminSignOutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sign out of this device to end the current admin session securely.'**
  String get adminSignOutSubtitle;

  /// No description provided for @adminConfirmLogout.
  ///
  /// In en, this message translates to:
  /// **'Confirm Logout'**
  String get adminConfirmLogout;

  /// No description provided for @adminConfirmLogoutMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to log out?'**
  String get adminConfirmLogoutMessage;

  /// No description provided for @adminCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get adminCancel;

  /// No description provided for @adminLogout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get adminLogout;

  /// No description provided for @adminPcgAlert.
  ///
  /// In en, this message translates to:
  /// **'PCG Alert'**
  String get adminPcgAlert;

  /// No description provided for @adminStaticWeatherAlertTitle.
  ///
  /// In en, this message translates to:
  /// **'PCG Alert: Weather'**
  String get adminStaticWeatherAlertTitle;

  /// No description provided for @adminStaticWeatherAlertMessage.
  ///
  /// In en, this message translates to:
  /// **'Gale warning in Lingayen Gulf. Secure vessels and postpone departures.'**
  String get adminStaticWeatherAlertMessage;

  /// No description provided for @adminStaticIllegalSubmittedTitle.
  ///
  /// In en, this message translates to:
  /// **'Illegal Report Submitted'**
  String get adminStaticIllegalSubmittedTitle;

  /// No description provided for @adminStaticIllegalSubmittedMessage.
  ///
  /// In en, this message translates to:
  /// **'User reported suspected dynamite fishing near Bonuan waters.'**
  String get adminStaticIllegalSubmittedMessage;

  /// No description provided for @adminStaticReviewNeededTitle.
  ///
  /// In en, this message translates to:
  /// **'PCG Review Needed'**
  String get adminStaticReviewNeededTitle;

  /// No description provided for @adminStaticReviewNeededMessage.
  ///
  /// In en, this message translates to:
  /// **'PCG web portal marked a report as approved. Review and respond.'**
  String get adminStaticReviewNeededMessage;

  String get adminPcgWebAdminAccess;

  String adminPcgStationScope(Object station);

  String get adminPcgPersonalAccountAccess;

  String get adminPcgManagementTitle;

  String get adminPcgManagementSubtitleWebAdmin;

  String get adminPcgManagementSubtitleAssigned;

  String get adminPcgFailedToLoadAccounts;

  String get adminPcgNoAccountsFound;

  String get adminPcgManagedAccountSingular;

  String get adminPcgManagedAccountPlural;

  String get adminPcgUserFallback;

  String get adminPcgStationLabel;

  String get adminPcgPcgStationLabel;

  String get adminPcgMyAccount;

  String get adminPcgManagedStatus;

  String get adminPcgAssignmentDetails;

  String get adminPcgEditInfo;

  String get adminPcgDelete;

  String get adminPcgDeleteAccountQuestion;

  String get adminPcgDeleteAccountMessage;

  String get adminPcgAccountRemoved;

  String get adminPcgDeleteFailedPrefix;

  String get adminPcgPleaseWait;

  String get adminPcgPasswordChangeDescription;

  String get adminPcgPasswordSafetyHint;

  String get adminPcgSignedInUserMismatch;

  String get adminPcgPasswordUpdateFailedPrefix;

  String get adminPcgNoEmailForPasswordReset;

  String adminPcgPasswordResetSent(Object email);

  String get adminPcgResetFailedPrefix;

  String get adminPcgEditAccountTitle;

  String get adminPcgEditSheetSubtitle;

  String get adminPcgAccountIdentity;

  String get adminPcgAccountIdentitySubtitle;

  String get adminPcgFullName;

  String get adminPcgEnterValidEmail;

  String get adminPcgContactNumber;

  String get adminPcgContactConfirmationHint;

  String get adminPcgLocationAssignment;

  String get adminPcgLocationAssignmentSubtitle;

  String get adminPcgSavingChanges;

  String get adminPcgNothingToUpdate;

  String get adminPcgPhotoUploadFailedPrefix;

  String get adminPcgProfilePhotoUpdated;

  String get adminPcgDetailsSavedButPhotoNotUpdatedPrefix;

  String get adminPcgPhotoNotUpdatedPrefix;

  String get adminPcgAccountDetailsUpdated;

  String get adminPcgEmailAndContactUpdatedConfirmBoth;

  String get adminPcgEmailUpdatedConfirm;

  String get adminPcgContactUpdatedConfirm;

  String get adminPcgUpdateFailedPrefix;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['en', 'fil'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en': return AppLocalizationsEn();
    case 'fil': return AppLocalizationsFil();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
