// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Imposter: Word Bluff';

  @override
  String get settings => 'Settings';

  @override
  String get profile => 'Profile';

  @override
  String get gameName => 'Who\'s the imposter?';

  @override
  String get homeTagline => 'Everyone knows the word. Except one.';

  @override
  String get onlineGame => 'Online game';

  @override
  String get oneDeviceGame => 'One-device game';

  @override
  String get howToPlay => 'How to play?';

  @override
  String get resumeGameTitle => 'Continue the game?';

  @override
  String resumeGameDetails(Object round, Object playersLength) {
    return 'Round $round saved on this device · $playersLength players';
  }

  @override
  String get resumeGame => 'Continue game';

  @override
  String get deleteGame => 'Delete game';

  @override
  String get legalDate => 'September 26, 2026';

  @override
  String get legalGateTitle => 'Before we start';

  @override
  String get legalConsent =>
      'I have read and agree to the Terms of Use and confirm that I have read the Privacy Policy.';

  @override
  String get saving => 'Saving...';

  @override
  String get acceptAndContinue => 'Accept and continue';

  @override
  String get legalGateHeadline => 'Fair play starts with clear rules';

  @override
  String get legalGateBody =>
      'In this game you write nicknames and hints that other players can see. We filter inappropriate content and let you report and hide players.';

  @override
  String get termsTitle => 'Terms of Use';

  @override
  String get termsSubtitle => 'Game rules, forbidden content and reports';

  @override
  String get privacyTitle => 'Privacy Policy';

  @override
  String get privacySubtitle => 'What data is kept, where and for how long';

  @override
  String legalDocsVersion(Object legalVersion, Object legalDate) {
    return 'Documents version $legalVersion · $legalDate';
  }

  @override
  String termsIntro(Object legalVersion, Object legalDate) {
    return 'Version $legalVersion · Effective $legalDate\n\nUse of \"Imposter: Word Bluff\" is subject to the following terms. The game is intended for ages 13 and up. If you are 13 or older but not old enough to agree to these terms where you live, use the game only with the permission and supervision of a parent or guardian.';
  }

  @override
  String get terms1Title => '1. The service';

  @override
  String get terms1 =>
      '\"Imposter: Word Bluff\" is an online social game operated by Imposter IL (imposteril36@gmail.com). No account is needed. You choose a nickname and an avatar and receive a temporary guest ID for playing.';

  @override
  String get terms2Title => '2. Conduct and content';

  @override
  String get terms2 =>
      'Nicknames and hints must not contain sexually explicit content, threats, hate speech, humiliation or harassment, illegal content, impersonation of another person, another person\'s personal details, or content meant to hurt players. Do not try to bypass the content filters or misuse the server, the rooms, reporting or the game.';

  @override
  String get terms3Title => '3. Player content';

  @override
  String get terms3 =>
      'Nicknames and hints you write are shown to other players in the game. You are responsible for the content you send. The game may refuse or hide content, or suspend access, if the rules are broken. Players can report content and hide a reported player\'s content on their device. Reports are reviewed within 24 hours, and content that breaks the rules is added to the filter.';

  @override
  String get terms4Title => '4. Games, results and statistics';

  @override
  String get terms4 =>
      'A game may end because of a disconnection, a fault or maintenance. Wins and losses are stored on the device only and are not an account, a ranking or an asset that can be restored after deleting the app or switching devices.';

  @override
  String get terms5Title => '5. Purchases, subscriptions and ads';

  @override
  String get terms5 =>
      'Three categories are free. The other categories can be unlocked by buying a single category forever, with a monthly Premium subscription or with lifetime Premium. Premium unlocks every category, including ones added later, and removes ads; buying a single category does not remove ads. Payment, billing, renewal and refunds go through the App Store or Google Play, under their terms and at the price the store shows in your account\'s currency. The monthly subscription renews automatically every month until cancelled. You can cancel it at any time in the store\'s subscription settings, at least 24 hours before the renewal date, and access remains until the end of the paid period. A purchase refunded or cancelled in the store stops unlocking what it unlocked. Purchases belong to the store account, not the device, and can be restored on any device with the same account using \"Restore purchases\". Players without Premium see third-party ads on screens outside the game and after a finished game. On Apple devices, Apple\'s standard End User License Agreement (EULA) also applies. Nothing here limits your rights under applicable consumer protection law, including cancelling a transaction.';

  @override
  String get terms6Title => '6. Availability and changes';

  @override
  String get terms6 =>
      'The service is provided as is and subject to availability. The operator may fix bugs, change rules and content, restrict old versions or discontinue parts of the service. When a material change to the terms requires renewed consent, the app will show the new version before play continues.';

  @override
  String get terms7Title => '7. Intellectual property';

  @override
  String get terms7 =>
      'The name, design, code, illustrations and game content belong to their owners and are protected under applicable law. Do not copy, distribute, reverse engineer or use the game\'s assets beyond what the law or applicable licenses allow.';

  @override
  String get terms8Title => '8. Liability';

  @override
  String get terms8 =>
      'To the maximum extent permitted by law, there is no commitment that the service will be continuous or error-free. Nothing in these terms limits consumer rights that cannot be waived under applicable law.';

  @override
  String get terms9Title => '9. Privacy';

  @override
  String get terms9 =>
      'The Privacy Policy describes the data the service uses and how long it is kept, and is part of using the service.';

  @override
  String get terms10Title => '10. Changes to the terms';

  @override
  String get terms10 =>
      'A material change will get a new documents version. The app stores the accepted terms version on the device and may require renewed acceptance of a new version.';

  @override
  String get terms11Title => '11. Governing law and jurisdiction';

  @override
  String get terms11 =>
      'These terms are governed by the laws of the State of Israel, and the competent courts of the Tel Aviv-Jaffa district have exclusive jurisdiction. This does not limit your right to sue where you live when the law that applies to you grants you such a right.';

  @override
  String get terms12Title => '12. Contact';

  @override
  String get terms12 =>
      'Imposter IL · imposteril36@gmail.com\nFor support, reporting offensive content and any question about these terms.';

  @override
  String privacyIntro(Object legalVersion, Object legalDate) {
    return 'Version $legalVersion · Effective $legalDate\n\nThis policy describes the data \"Imposter: Word Bluff\" uses to run games, save preferences and protect players.';
  }

  @override
  String get privacy1Title => '1. Who we are';

  @override
  String get privacy1 =>
      'The game \"Imposter: Word Bluff\" is operated by Imposter IL, and this policy applies to the app and to the server that runs it. For privacy inquiries: imposteril36@gmail.com.';

  @override
  String get privacy2Title => '2. Data stored on the device';

  @override
  String get privacy2 =>
      'The app stores on the device the temporary session and player IDs, your nickname and avatar, wins and losses, vibration and reaction settings, the accepted documents version and the list of player IDs you reported so their content stays hidden. Deleting the app or its data may delete this information. After a purchase, the categories and Premium you own and the subscription\'s expiry date are also stored so they stay unlocked offline, along with the ad settings received from the server and the time of the last full-screen ad.';

  @override
  String get privacy3Title => '3. Data sent to the server';

  @override
  String get privacy3 =>
      'To run games, the server receives a player and session ID, nickname, avatar, IP address for security and rate limiting, room and game membership, chosen categories, hints, reactions, votes, guesses and reports. No real name, phone number or email address is needed to play. To unlock purchased categories online, the app sends the server the proof of purchase the store provides — an Apple signed transaction or a Google purchase token, which include the product ID, the transaction ID and its dates. The server verifies it with Apple or Google. We do not receive your payment details.';

  @override
  String get privacy4Title => '4. How the data is used';

  @override
  String get privacy4 =>
      'The data is used to run matchmaking and rooms, sync the game in real time, reconnect, enforce the game rules, prevent abuse, handle reports, and for security, troubleshooting and measuring server health. It is also used to verify purchases and enforce unlocked categories, and to show ads to players without Premium.';

  @override
  String get privacy5Title => '5. What other players see';

  @override
  String get privacy5 =>
      'Players in the same game can see your nickname and avatar, the hints you sent, your connection status and the game information needed for voting and results. The secret word is not sent to the imposter before the results stage.';

  @override
  String get privacy6Title => '6. Retention and deletion';

  @override
  String get privacy6 =>
      'Game and room state is kept in the server\'s memory, not in a permanent database. A disconnected session that is not in a room is deleted after up to 24 hours of inactivity, and an empty room closes after 30 minutes. A server restart erases the game state in memory. Operational logs may be kept for security and diagnostics and may include pseudonymous player IDs and report metadata. Purchase verification results are kept in server memory alongside the session only and are deleted with it. A report is logged together with the reported hint and nickname so it can be reviewed.';

  @override
  String get privacy7Title => '7. Third-party services';

  @override
  String get privacy7 =>
      'The server is hosted on Google Cloud Platform (Cloud Run, us-central1 region), and Google processes the technical data needed to route traffic and keep operational logs, as a processor on our behalf and subject to security and privacy commitments equal to or better than those described here. Payments are made through Apple\'s App Store and Google Play, under their privacy policies. Players without Premium see ads from Google AdMob. AdMob may collect device identifiers and the advertising ID, IP address, ad interaction data, and diagnostic and performance data, to show and measure ads and prevent fraud, under Google\'s advertising policy (policies.google.com/technologies/ads). Where the law requires it, including the European Union and the United Kingdom, your consent is requested before personalized advertising; on iPhone the advertising ID is not used without your permission. To find and fix problems, when the app crashes or hits an error it sends a report to Google\'s Firebase Crashlytics: the error details and where it happened in the code, the device model, operating system, app version and a random Crashlytics installation ID. The report does not include nicknames, hints or the advertising ID, and it is kept for up to 90 days. We do not sell personal data, and there is no third-party analytics SDK.';

  @override
  String get privacy8Title => '8. Children and personal details';

  @override
  String get privacy8 =>
      'The game does not ask for a real name or contact details. Do not write personal information about yourself or others in a nickname or hint. The game is intended for ages 13 and up and is not directed at children. We do not knowingly collect data from children under 13, and if we learn of it we will delete the related data. Ads are limited to content rated for a general audience.';

  @override
  String get privacy9Title => '9. Choice and control';

  @override
  String get privacy9 =>
      'You can change your nickname and avatar, turn off vibration or reactions, report a player and clear the list of hidden players. Deleting the app\'s data removes the local information. Since there is no permanent account, there is no way to restore local data. You can also change your ad privacy preferences in Settings where the law requires it, decline tracking permission on iPhone, or reset the advertising ID in the device settings. Premium removes all ads.';

  @override
  String get privacy10Title => '10. Your rights';

  @override
  String get privacy10 =>
      'Under Israel\'s Protection of Privacy Law, 5741-1981, and its Amendment 13, and where the GDPR applies, you have the right to access the data kept about you, ask to correct it, delete it, restrict or object to its processing, and receive it in an accessible format. Since there is no account, the player or session ID shown in the Settings screen is needed to find data related to you. To make a request, write to imposteril36@gmail.com; we will reply within 30 days. Most data is deleted automatically anyway — game state when the game ends, sessions after 24 hours and logs after 30 days.';

  @override
  String get privacy11Title => '11. Security';

  @override
  String get privacy11 =>
      'Traffic in release builds is meant to travel over an encrypted connection. The server applies rate limits, message size limits and content filtering to reduce abuse. No system can guarantee absolute security.';

  @override
  String get privacy12Title => '12. Changes to the policy';

  @override
  String get privacy12 =>
      'A material change to the policy will get a new version. When renewed consent is required, the app will show the new version before play continues.';

  @override
  String get privacy13Title => '13. Contact';

  @override
  String get privacy13 =>
      'Imposter IL · imposteril36@gmail.com\nFor privacy inquiries, requests to exercise your rights and reporting offensive content. We aim to reply within 30 days.';

  @override
  String legalPublicCopy(Object value) {
    return 'Public copy: $value';
  }

  @override
  String get errNotRoomHost => 'Only the room host can do this.';

  @override
  String get errNotEnoughPlayers => 'You need at least 4 players to start.';

  @override
  String get errContentUnavailable =>
      'Can\'t start a game right now. Try again in a moment.';

  @override
  String get errRoomInGame => 'A game is already running in this room.';

  @override
  String get errWrongPhase => 'This stage is already over.';

  @override
  String get errNotYourTurn => 'It\'s not your turn.';

  @override
  String get errHintEmpty => 'Write a hint before sending.';

  @override
  String get errHintNotOneWord => 'You can only send one word.';

  @override
  String get errHintTooLong => 'A hint can be up to 25 characters.';

  @override
  String get errHintInappropriate =>
      'That hint isn\'t appropriate. Try another word.';

  @override
  String get errHintContainsSecret =>
      'The hint contains the secret word. Choose another word.';

  @override
  String get errHintDuplicate =>
      'That hint was already used in this game. Choose another word.';

  @override
  String get errSelfVote => 'You can\'t vote for yourself.';

  @override
  String get errInvalidVoteTarget => 'You can\'t vote for this player.';

  @override
  String get errNetwork =>
      'No connection to the server. Check your connection and try again.';

  @override
  String get errCategoryLockedRoom =>
      'One of the categories is no longer unlocked. A category unlocked by watching an ad is open for one game only. You can renew Premium, restore purchases or create a new room.';

  @override
  String get errGeneric => 'Something went wrong. Try again in a moment.';

  @override
  String get leaveGameTitle => 'Leave the game?';

  @override
  String get leaveGameBody =>
      'Leaving in the middle of a game counts as a loss.';

  @override
  String get leave => 'Leave';

  @override
  String get stillCantConnect => 'Still can\'t connect. Try again in a moment.';

  @override
  String get kickedByHost => 'The room host removed you from the room.';

  @override
  String get reconnecting => 'Reconnecting...';

  @override
  String get connectionLostOnTurn =>
      'Connection lost during your turn. We\'ll try to bring you back into the game for 30 seconds.';

  @override
  String get connectionLost =>
      'Connection lost. We\'ll try to bring you back into the game for 30 seconds.';

  @override
  String get disconnectFinalWarning =>
      'If you don\'t come back within 30 seconds, this will count as disconnection 3 of 3 and you\'ll be removed from the game.';

  @override
  String disconnectWarning(Object disconnectNumber) {
    return 'If you don\'t come back within 30 seconds, this will count as disconnection $disconnectNumber of 3.';
  }

  @override
  String get turnTimerRunning => ' Your turn timer keeps running.';

  @override
  String get leaveGameButton => 'Leave game';

  @override
  String disconnectCount(Object disconnectNumber) {
    return 'Disconnection $disconnectNumber of 3';
  }

  @override
  String get groupReady => 'The group is ready!';

  @override
  String get gameStartingSoon => 'The game starts in a moment.';

  @override
  String get enoughPlayers => 'Enough players!';

  @override
  String get waitingForMore =>
      'Waiting a few seconds for more players, then we start.';

  @override
  String get oneMorePlayer => 'One more player to start';

  @override
  String get stillSearching =>
      'Still looking for players in the categories you chose.';

  @override
  String morePlayersNeeded(Object missing) {
    return '$missing more players to start';
  }

  @override
  String get searchingPlayers => 'Looking for players';

  @override
  String get buildingGroup => 'Putting a group together';

  @override
  String get cancelSearch => 'Cancel search';

  @override
  String get yourGroup => 'Your group';

  @override
  String countOfMax(Object count, Object maxPlayers) {
    return '$count of $maxPlayers';
  }

  @override
  String get dontLeavePage => 'Please don\'t leave this page.';

  @override
  String get you => 'You';

  @override
  String get searchingPlayer => 'Looking for a player...';

  @override
  String get noMatchTitle => 'No game found in the categories you chose';

  @override
  String get noMatchBody =>
      'You can try again with the same categories, or choose different ones.';

  @override
  String get tryAgain => 'Try again';

  @override
  String get chooseOtherCategories => 'Choose other categories';

  @override
  String get privateRoom => 'Private room';

  @override
  String roomOf(Object hostNickname) {
    return '$hostNickname\'s room';
  }

  @override
  String get startGame => 'Start game';

  @override
  String get onlyHostCanStart => 'Only the room host can start';

  @override
  String get roomCode => 'Room code';

  @override
  String get shareCode => 'Share code';

  @override
  String shareInvite(Object code, Object value) {
    return 'Come play \"Imposter: Word Bluff\" with me\nRoom code: $code\n$value';
  }

  @override
  String get copyCode => 'Copy code';

  @override
  String get codeCopied => 'Room code copied';

  @override
  String get hostDisconnected =>
      'The room host disconnected. Waiting for them to come back.';

  @override
  String get waitingForNewHost =>
      'Waiting for another player to connect and take over the room.';

  @override
  String get hostTransferredToYou =>
      'The room host didn\'t come back in time. You\'re the host now.';

  @override
  String hostTransferredTo(Object hostNickname) {
    return '$hostNickname is the host now.';
  }

  @override
  String playersOfMax(Object playersLength, Object maxPlayers) {
    return '$playersLength of $maxPlayers players';
  }

  @override
  String get needFourPlayers => 'You need at least 4 players to start';

  @override
  String get roomHost => 'Room host';

  @override
  String get disconnected => 'Disconnected';

  @override
  String removePlayer(Object pNickname) {
    return 'Remove $pNickname';
  }

  @override
  String categoriesList(Object categoryNames) {
    return 'Categories: $categoryNames';
  }

  @override
  String secondsPerHint(Object hintSeconds) {
    return '$hintSeconds seconds per hint';
  }

  @override
  String get settingsLockedSinceJoin =>
      'Settings are locked since players joined';

  @override
  String get waitingForOthers => 'Waiting for the other players';

  @override
  String get gotIt => 'Got it';

  @override
  String get youAreImpostor => 'You\'re the imposter';

  @override
  String get youAreCitizen => 'You\'re a citizen';

  @override
  String get impostorDoesntKnow =>
      'The imposter doesn\'t know the secret word. Keep it secret.';

  @override
  String get impostorTip1 =>
      'Listen to the others\' hints and try to blend in.';

  @override
  String get impostorTip2 =>
      'If you\'re caught, you get one chance to guess the word and win.';

  @override
  String get citizenTip1 =>
      'On your turn, write a one-word hint that fits the secret word.';

  @override
  String get citizenTip2 =>
      'A hint that\'s too obvious helps the imposter. A hint that\'s too vague raises suspicion.';

  @override
  String get nextRoundContinues => 'On to the next round';

  @override
  String continuingToRound(Object value) {
    return 'On to round $value';
  }

  @override
  String get tieAgain => 'Another tie';

  @override
  String get votesSplitAgain => 'Once again the votes were split evenly';

  @override
  String get noOneEliminatedNextRound =>
      'No one was eliminated. On to another round of hints.';

  @override
  String get oneVote => '1 vote';

  @override
  String nVotes(Object n) {
    return '$n votes';
  }

  @override
  String get loading => 'Loading…';

  @override
  String wasCitizen(Object outNickname) {
    return '$outNickname was a citizen';
  }

  @override
  String get decideImpostor => 'Time to decide who the imposter is';

  @override
  String get youEliminatedSpectator => 'You\'re out · spectating';

  @override
  String get eliminatedSpectator => 'Out · spectating';

  @override
  String get leftGame => 'Left the game';

  @override
  String get disconnectedWaiting => 'Disconnected · waiting 30 seconds';

  @override
  String get writingHint => 'Writing a hint';

  @override
  String get waitingTurn => 'Waiting for their turn';

  @override
  String get oneHint => '1 hint';

  @override
  String nHints(Object said) {
    return '$said hints';
  }

  @override
  String get noHintSent => 'No hint sent';

  @override
  String get hidden => 'Hidden';

  @override
  String get category => 'Category';

  @override
  String roundTurnOf(Object round, Object turn, Object playingLength) {
    return 'Round $round · Turn $turn of $playingLength';
  }

  @override
  String get roundHints => 'Hints this round';

  @override
  String playerWriting(Object currentNickname) {
    return '$currentNickname is writing now. You can keep reacting below.';
  }

  @override
  String playerMe(Object playerNickname) {
    return '$playerNickname · me';
  }

  @override
  String get yourHintOneWord => 'Your hint · one word';

  @override
  String get yourHint => 'Your hint';

  @override
  String hintNotSent(Object error) {
    return '$error The hint wasn\'t sent.';
  }

  @override
  String get sendHint => 'Send hint';

  @override
  String get send => 'Send';

  @override
  String get showMyWord => 'Show my word';

  @override
  String get myWord => 'My word';

  @override
  String get close => 'Close';

  @override
  String categoryIs(Object category) {
    return 'Category: $category';
  }

  @override
  String roundN(Object first) {
    return 'Round $first';
  }

  @override
  String roundsRange(Object first, Object last) {
    return 'Rounds $first–$last';
  }

  @override
  String hintsOf(Object playerNickname) {
    return '$playerNickname\'s hints';
  }

  @override
  String get noHintsYet => 'No hints yet.';

  @override
  String get reportHint => 'Report hint';

  @override
  String playerDisconnectedTurn(Object nickname) {
    return '$nickname disconnected. Waiting up to 30 seconds — then their turn will be skipped.';
  }

  @override
  String get reactions => 'Reactions';

  @override
  String get swipeForReactions => 'Swipe sideways for more reactions ↔';

  @override
  String get revote => 'Revote';

  @override
  String get voteReceived => 'Vote received';

  @override
  String get confirmVote => 'Confirm vote';

  @override
  String get choosePlayer =>
      'Choose one player. You can change your choice until time runs out.';

  @override
  String get tieRevoteExplain =>
      'It was a tie. Vote again only between the players with the most votes. Another tie — no one is eliminated and the game moves on to another round.';

  @override
  String get cantVoteSelf => 'You can\'t vote for yourself';

  @override
  String get oneVotePrevious => '1 vote in the previous round';

  @override
  String nVotesPrevious(Object votes) {
    return '$votes votes in the previous round';
  }

  @override
  String get youWereCaught => 'You were caught';

  @override
  String get sendGuess => 'Send guess';

  @override
  String get stillCanWin => 'You can still win';

  @override
  String get impostorGuessing =>
      'The imposter was caught and is now trying to guess the word.';

  @override
  String get guessWinsExplain =>
      'Guessing the secret word correctly wins you the game. You have one try.';

  @override
  String get othersHints => 'The other players\' hints';

  @override
  String get whatsTheWord => 'What\'s the word?';

  @override
  String get guessHidden => 'Your guess isn\'t shown to players while you type';

  @override
  String get guessFailExplain =>
      'If time runs out or the guess is wrong, the citizens win.';

  @override
  String get reasonCitizenVoted =>
      'The vote picked a citizen, and the imposter stays in the game.';

  @override
  String get reasonParity =>
      'One citizen and the imposter are left, and at this point the imposter wins right away.';

  @override
  String get reasonGuessed =>
      'The imposter was caught but managed to guess the word.';

  @override
  String get reasonWrongGuess =>
      'The imposter was caught and failed to guess the word.';

  @override
  String get reasonGuessTimeout =>
      'The imposter was caught, but ran out of time to guess.';

  @override
  String get reasonImpostorLeft => 'The imposter left the game.';

  @override
  String get reasonNotEnoughPlayers =>
      'Fewer than three players were left, so the game was stopped.';

  @override
  String get reasonAbandoned =>
      'Two voting rounds passed without a single vote, so the game was cancelled. It doesn\'t count for anyone — not as a win or a loss.';

  @override
  String get gameCancelled => 'The game was cancelled';

  @override
  String get citizensWon => 'The citizens won!';

  @override
  String get impostorWon => 'The imposter won!';

  @override
  String get gameStopped => 'The game was stopped';

  @override
  String get impostorWas => 'The imposter was';

  @override
  String get winRecorded => 'You got a win';

  @override
  String get lossRecorded => 'You got a loss';

  @override
  String get abstained => 'Abstained';

  @override
  String get youLeftGame => 'You left the game';

  @override
  String get removedThirdDisconnect =>
      'You disconnected three times in this game, so the other players continue without you.';

  @override
  String get backToHome => 'Back to home';

  @override
  String get reportHintTitle => 'Report this hint?';

  @override
  String reportHintBody(Object nickname) {
    return 'The hint will be sent for review and handled within 24 hours. You won\'t see any more hints from $nickname on this device.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get report => 'Report';

  @override
  String get reportThanks =>
      'Thanks, the report was received and will be handled. This player\'s hints will be hidden on your device.';

  @override
  String reportNotSent(Object value) {
    return 'These hints will be hidden, but the report wasn\'t sent. $value';
  }

  @override
  String get whoAreYou => 'Who are you in the game?';

  @override
  String get onboardingSubtitle =>
      'Choose a nickname and an avatar and start. No sign-up.';

  @override
  String get continueLabel => 'Continue';

  @override
  String get connecting => 'Connecting...';

  @override
  String get editDetails => 'Edit details';

  @override
  String get save => 'Save';

  @override
  String get nicknameRule =>
      'Choose a nickname of 2–18 characters, including accents and emoji.';

  @override
  String get nicknameBlocked =>
      'That nickname isn\'t suitable for the game. Choose another one.';

  @override
  String get yourNickname => 'Your nickname';

  @override
  String get nicknameExample => 'For example: Alex';

  @override
  String nicknameLength(Object maxNicknameLength) {
    return '2–$maxNicknameLength characters';
  }

  @override
  String get chooseAvatar => 'Choose an avatar';

  @override
  String avatarN(Object value) {
    return 'Character $value';
  }

  @override
  String get errAlreadyInActivity =>
      'You\'ve already joined another game or room.';

  @override
  String get errCategoryLocked =>
      'One of the categories is locked. You can restore purchases from the category\'s unlock window.';

  @override
  String get canPickSeveral => 'You can pick several categories';

  @override
  String get all => 'All';

  @override
  String get chooseCategories => 'Choose categories';

  @override
  String get searchingGame => 'Finding a game...';

  @override
  String get searchGame => 'Find a game';

  @override
  String get loadingCategories => 'Loading categories...';

  @override
  String get allCategories => 'All categories';

  @override
  String get allOpenCategories => 'All unlocked categories';

  @override
  String get premium => 'Premium';

  @override
  String lockedTapToOpen(Object name) {
    return '$name — locked, tap to unlock';
  }

  @override
  String get purchasedTag => '✓ Purchased';

  @override
  String get playWithFriends => 'Play with friends';

  @override
  String get createRoom => 'Create room';

  @override
  String get createRoomSubtitle =>
      'Choose settings, get a code and share it with friends.';

  @override
  String get joinRoom => 'Join room';

  @override
  String get joinRoomSubtitle => 'Got a six-digit code? Enter it and join.';

  @override
  String get playersRange4to8 => 'The game is for 4 to 8 players';

  @override
  String get creatingRoom => 'Creating room...';

  @override
  String get settingsLockNotice =>
      'Once the room is created, the settings can\'t be changed.';

  @override
  String get maxPlayers => 'Max players';

  @override
  String get timePerHint => 'Time per hint';

  @override
  String nSeconds(Object value) {
    return '$value seconds';
  }

  @override
  String get categories => 'Categories';

  @override
  String get loadingCategoriesShort => 'Loading categories...';

  @override
  String get settingsLockAfterJoin =>
      'Once another player joins, the settings can\'t be changed.';

  @override
  String get roomCodeSixDigits => 'The room code must be six digits';

  @override
  String get roomNotFound =>
      'The room wasn\'t found or isn\'t available. Check the code with whoever opened the room.';

  @override
  String get roomFull => 'The room is full or the game has already started.';

  @override
  String get alreadyInOtherGame => 'You\'ve already joined another game.';

  @override
  String get join => 'Join';

  @override
  String get enterRoomCode => 'Enter the six-digit room code you received.';

  @override
  String get delete => 'Delete';

  @override
  String get myProfile => 'My profile';

  @override
  String get editNicknameAvatar => 'Edit nickname and avatar';

  @override
  String get wins => 'Wins';

  @override
  String get losses => 'Losses';

  @override
  String get sounds => 'Sounds';

  @override
  String get comingSoon => 'Coming soon';

  @override
  String get vibration => 'Vibration';

  @override
  String get showReactions => 'Show reactions';

  @override
  String get language => 'Language';

  @override
  String get languageName => 'English';

  @override
  String versionN(Object legalVersion) {
    return 'Version $legalVersion';
  }

  @override
  String get manageSubscription => 'Manage subscription';

  @override
  String get premiumMonthly => 'Monthly Premium';

  @override
  String get adPrivacy => 'Ad privacy preferences';

  @override
  String get appVersion => 'Imposter: Word Bluff · Version 1.0';

  @override
  String get contact => 'Contact';

  @override
  String get reportedPlayers => 'Players you reported';

  @override
  String hiddenPlayersCount(Object mutedLength) {
    return 'Hidden players: $mutedLength';
  }

  @override
  String get clear => 'Clear';

  @override
  String get purchasesRestored => 'Purchases restored.';

  @override
  String get noPurchasesFound =>
      'No previous purchases were found on this store account.';

  @override
  String get restoreFailed =>
      'Restore didn\'t finish. Check your internet connection and try again.';

  @override
  String get restoringPurchases => 'Restoring purchases…';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get howStep1 =>
      'Everyone gets the same secret word — except the imposter, who only sees the category.';

  @override
  String get howStep2 =>
      'On their turn, each player writes a one-word hint. Each turn has 60 seconds.';

  @override
  String get howStep4 =>
      'You can react to hints with emoji and ready-made messages.';

  @override
  String get howStep5 =>
      'At the end of the round, everyone votes on who the imposter is. You have 20 seconds to vote.';

  @override
  String get howStep6 =>
      'If the imposter is caught, they have 60 seconds to guess the word and win anyway.';

  @override
  String get updateNeeded => 'Update needed';

  @override
  String get newVersion => 'There\'s a new version of the game';

  @override
  String get versionUnsupported =>
      'The version you have installed is no longer supported.\nUpdate the app in the store to keep playing.';

  @override
  String get somethingWrong => 'Something went wrong';

  @override
  String get serverFaultStopped =>
      'The game stopped because of a server connection problem. It\'s not your fault.';

  @override
  String get serverUnavailable =>
      'The server isn\'t available right now. Try again in a moment.';

  @override
  String get noLossRecorded => 'No loss was recorded';

  @override
  String get localDeleteWarning =>
      'The current game will be deleted and can\'t be continued.';

  @override
  String get leaveAndDelete => 'Leave and delete';

  @override
  String iAmVote(Object currentName) {
    return 'I\'m $currentName — to vote';
  }

  @override
  String iAmShow(Object currentName) {
    return 'I\'m $currentName — show me';
  }

  @override
  String votedOf(Object done, Object activePlayersLength) {
    return '$done of $activePlayersLength voted';
  }

  @override
  String passDeviceTo(Object currentName) {
    return 'Pass the device to $currentName';
  }

  @override
  String get noOneElseLooking => 'No one else is looking at the screen.';

  @override
  String onlyPlayerLooking(Object currentName) {
    return 'Only $currentName is looking at the screen.';
  }

  @override
  String get gotItHide => 'Got it — hide';

  @override
  String get localImpostorTip =>
      'Listen to the hints, blend in and try to figure out the word.';

  @override
  String get localCitizenTip => 'On your turn, say a one-word hint out loud.';

  @override
  String get startRound1 => 'Start round 1';

  @override
  String startRoundN(Object round) {
    return 'Start round $round';
  }

  @override
  String get everyoneKnowsRoles => 'Everyone knows who they are';

  @override
  String get anotherRound => 'Another round';

  @override
  String get placeDevice => 'Put the device where everyone can see it.';

  @override
  String get impostorStillAmong =>
      'The imposter is still among you. The turn order was reshuffled.';

  @override
  String get turnOrderThisRound => 'Turn order this round';

  @override
  String get startsFirst => 'Goes first';

  @override
  String get spectator => 'Spectator';

  @override
  String get hintRuleLocal =>
      'A one-word hint, without repeating an earlier hint and without saying the word itself.';

  @override
  String roundCategory(Object round, Object category) {
    return 'Round $round · $category';
  }

  @override
  String get hintSaid => 'Hint said';

  @override
  String turnOf(Object speakerName) {
    return '$speakerName\'s turn';
  }

  @override
  String get sayHintAloud => 'Say a one-word hint out loud';

  @override
  String get turnOrder => 'Turn order';

  @override
  String get now => 'Now';

  @override
  String get nextUp => 'Next up';

  @override
  String get noHintSaid => 'No hint said';

  @override
  String get said => 'Said';

  @override
  String get waiting => 'Waiting';

  @override
  String get hintsSpokenAloud =>
      'Hints are said out loud — no typing and no hint board.';

  @override
  String get passDeviceVote =>
      'Pass the device between players. Don\'t reveal who you voted for.';

  @override
  String get tie => 'It\'s a tie';

  @override
  String tieCandidates(Object tieCandidatesLength, int tiedVotes) {
    String _temp0 = intl.Intl.pluralLogic(
      tiedVotes,
      locale: localeName,
      other: '$tiedVotes votes',
      one: '1 vote',
    );
    return '$tieCandidatesLength players tied at $_temp0 each';
  }

  @override
  String get startRevote => 'Start the revote';

  @override
  String get thenPassNext => 'Then pass the device to the next player';

  @override
  String youreCaught(Object impostorName, Object imposterName) {
    return '$imposterName, you\'ve been caught';
  }

  @override
  String get guessWinsLocal =>
      'Guessing the secret word correctly wins you the game. There\'s one try.';

  @override
  String onlyPlayerLookingNoDot(Object impostorName, Object imposterName) {
    return 'Only $imposterName is looking at the screen';
  }

  @override
  String get localReasonGuessed =>
      'The imposter was caught and guessed the word correctly.';

  @override
  String get localReasonMissed =>
      'The imposter was caught and didn\'t guess the word.';

  @override
  String get theImpostor => 'The imposter';

  @override
  String get howItEnded => 'How it ended';

  @override
  String get whoWasEliminated => 'Who was eliminated during the game';

  @override
  String get localNoStats =>
      'A one-device game doesn\'t change your profile statistics.';

  @override
  String playerRound(Object playerName, Object round) {
    return '$playerName · Round $round';
  }

  @override
  String get hiddenNextPlayer => 'Hidden — next player';

  @override
  String get voteSaved => 'Vote saved';

  @override
  String get choiceHidden =>
      'Your choice was hidden from the screen. No one will see who you voted for.';

  @override
  String votingAgainSecret(Object meName) {
    return '$meName is voting again · the choice stays secret';
  }

  @override
  String votingSecret(Object meName) {
    return '$meName is voting · the choice stays secret';
  }

  @override
  String get ifTieAgain =>
      'If it\'s a tie again — no one is eliminated and a new round of hints starts.';

  @override
  String get screenClearsNext =>
      'After you confirm, the screen clears before passing to the next player.';

  @override
  String playerN(Object seat) {
    return 'Player $seat';
  }

  @override
  String get everyPlayerNeedsName => 'Every player needs a name';

  @override
  String get namesMustDiffer => 'Every player needs a different name';

  @override
  String get continueToSettings => 'Continue to settings';

  @override
  String get whoIsPlaying => 'Who\'s playing?';

  @override
  String get oneDevicePassed =>
      'One device passed around. Hints are said out loud.';

  @override
  String get tapAvatarToChange =>
      'Tap an avatar to swap it for one that\'s not in use.';

  @override
  String get fewerPlayers => 'Fewer players';

  @override
  String nPlayers(Object count) {
    return '$count players';
  }

  @override
  String get morePlayers => 'More players';

  @override
  String get gameSettings => 'Game settings';

  @override
  String get start => 'Start';

  @override
  String get timeForEachHint => 'Time for each hint';

  @override
  String get noTimer => 'No timer';

  @override
  String get summary => 'Summary';

  @override
  String get players => 'Players';

  @override
  String get impostors => 'Imposters';

  @override
  String get oneImpostor => 'One imposter';

  @override
  String get voting => 'Voting';

  @override
  String get privateVoteOnDevice => 'Private vote on the device';

  @override
  String get onlineChoiceSubtitle =>
      'Two modes, same game. Join other players or open a room for friends.';

  @override
  String get quickGame => 'Quick game';

  @override
  String get quickGameSubtitle => 'Choose categories and join players online.';

  @override
  String get players4to8 => '4–8 players';

  @override
  String get privateRoomSubtitle =>
      'Create a room and send the code, or join an existing room.';

  @override
  String get youDecideStart => 'You decide when to start';

  @override
  String get adLabel => 'Ad';

  @override
  String adFailed(Object widgetName) {
    return 'We couldn\'t show an ad all the way through, so \"$widgetName\" wasn\'t unlocked. You can try again later or choose another option.';
  }

  @override
  String get purchasesUnavailableLater =>
      'Purchases aren\'t available right now. Please try again later.';

  @override
  String get pricesFailed =>
      'We couldn\'t load prices from the store. Check your internet connection and try again.';

  @override
  String get purchaseCancelled =>
      'The purchase was cancelled. You weren\'t charged.';

  @override
  String get purchaseFailed =>
      'The purchase didn\'t go through and you weren\'t charged. Check your internet connection and try again.';

  @override
  String purchasePending(Object widgetName) {
    return 'The purchase is awaiting approval. \"$widgetName\" will unlock as soon as the payment is approved.';
  }

  @override
  String restoredOther(Object widgetName) {
    return 'Purchases were restored, but \"$widgetName\" wasn\'t among them.';
  }

  @override
  String get purchasesUnavailableRestore =>
      'Purchases aren\'t available right now. You can restore previous purchases.';

  @override
  String categoryLockedTitle(Object widgetName) {
    return '\"$widgetName\" is locked';
  }

  @override
  String get chooseHowToUnlock => 'Choose how to unlock it';

  @override
  String get perMonth => 'per month';

  @override
  String get oneTimePayment => 'one-time payment';

  @override
  String get watchAd => 'Watch an ad';

  @override
  String adUnlocksNextGame(Object widgetName) {
    return 'Unlocks \"$widgetName\" for the next game only';
  }

  @override
  String watchAgainIn(Object value) {
    return 'You can watch again in $value';
  }

  @override
  String get free => 'Free';

  @override
  String get oneGame => 'one game';

  @override
  String durationHours(Object h) {
    return '$h h';
  }

  @override
  String durationMinutes(Object min) {
    return '$min min';
  }

  @override
  String get durationAnd => ' and';

  @override
  String get premiumLifetime => 'Lifetime Premium';

  @override
  String onlyCategory(Object widgetName) {
    return 'Only \"$widgetName\"';
  }

  @override
  String get premiumMonthlyDesc =>
      'All categories and Premium features, no ads — while the subscription is active';

  @override
  String get premiumLifetimeDesc =>
      'All categories, including ones added in the future, and Premium features. No ads, forever';

  @override
  String get categoryForeverDesc => 'Unlocked forever · ads stay';

  @override
  String get purchasesRestoredTitle => 'Purchases restored';

  @override
  String categoryOpenAgain(Object widgetName) {
    return '\"$widgetName\" is unlocked again on this device.';
  }

  @override
  String categoryOpenNextGame(Object widgetName) {
    return '\"$widgetName\" is unlocked for the next game';
  }

  @override
  String get thanksForWatching =>
      'Thanks for watching. After the next game the category locks again.';

  @override
  String get welcomePremium => 'Welcome to Premium';

  @override
  String get monthlyActive =>
      'The monthly subscription is active. You can manage or cancel it in the store\'s subscription settings.';

  @override
  String get lifetimeWithMonthly =>
      'Everything is unlocked forever — including categories added in the future. Your monthly subscription is still active; you can cancel it in the store\'s subscription settings.';

  @override
  String get lifetimeUnlocked =>
      'Everything is unlocked forever — including categories added in the future.';

  @override
  String categoryUnlocked(Object widgetName) {
    return '\"$widgetName\" is unlocked!';
  }

  @override
  String get categoryYoursForever =>
      'The category is yours forever. Ads keep showing.';

  @override
  String get allCategoriesOpen => 'All categories unlocked';

  @override
  String get premiumFeaturesActive => 'Premium features active';

  @override
  String get noBannersNoAds => 'No banners and no full-screen ads';

  @override
  String get startPlaying => 'Start playing';

  @override
  String chooseCategoryN(Object widgetName) {
    return 'Choose \"$widgetName\"';
  }

  @override
  String get loadingAd => 'Loading ad…';

  @override
  String adDisclosure(Object widgetName) {
    return '\"$widgetName\" unlocks after watching the whole ad, for the next game only. You can unlock a category this way once every four hours.';
  }

  @override
  String get loadingPrices => 'Loading prices…';

  @override
  String get connectingStore => 'Connecting to the store…';

  @override
  String get pricesInStoreCurrency =>
      'Prices are shown in your store account\'s currency.';

  @override
  String get continueInStore =>
      'Continue in the store\'s payment window. Don\'t close the app.';

  @override
  String subscriptionDisclosure(Object p) {
    return 'The subscription renews automatically at $p every month until cancelled. You can cancel at any time in the store\'s subscription settings, at least 24 hours before the renewal date.';
  }

  @override
  String categoryPurchaseDisclosure(Object p, Object widgetName) {
    return 'One payment of $p through the store. \"$widgetName\" stays unlocked forever; ads keep showing.';
  }

  @override
  String premiumPurchaseDisclosure(Object p) {
    return 'One payment of $p through the store. No subscription and no further charges.';
  }

  @override
  String get joinPremium => 'Join Premium';

  @override
  String buyPrice(Object p) {
    return 'Buy · $p';
  }

  @override
  String playerEliminated(Object eliminatedName) {
    return '$eliminatedName was eliminated';
  }

  @override
  String get role => 'The role';

  @override
  String get wordStaysSecret => 'The word stays secret — the game goes on.';

  @override
  String get stillInGame => 'Still in the game';

  @override
  String previousHint(Object nickname) {
    return 'Previous hint · $nickname';
  }

  @override
  String roundLabel(Object round) {
    return 'Round $round';
  }

  @override
  String get youWereEliminated => 'You were eliminated';

  @override
  String get spectatorExplain =>
      'You keep watching and reacting, without hints or votes. Your result is your team\'s result.';

  @override
  String get secretWord => 'The secret word';

  @override
  String get wordNotShown =>
      'The word isn\'t shown to you — only the category.';

  @override
  String get votingOpensAuto => 'The voting screen opens automatically';

  @override
  String get allHintsSent => 'All hints are in';

  @override
  String get toVoting => 'On to voting';

  @override
  String get wordWas => 'The word was';

  @override
  String get theGuess => 'The guess';

  @override
  String get rounds => 'Rounds';

  @override
  String get voteBreakdown => 'Vote breakdown';

  @override
  String get playAgain => 'Play again';

  @override
  String openFreeCount(Object count) {
    return '$count free';
  }

  @override
  String openCount(Object count) {
    return '$count unlocked';
  }

  @override
  String rewardRefused(Object name) {
    return 'You can unlock a category by watching an ad once every four hours, so \"$name\" wasn\'t unlocked.';
  }

  @override
  String watchAgainInSentence(Object time) {
    return ' You can watch again in $time.';
  }

  @override
  String get phoneLanguage => 'Phone language';

  @override
  String roomLanguageMismatch(Object language) {
    return 'This room\'s language is $language. To join, switch the language in Settings.';
  }

  @override
  String get guessTheWord => 'Guess the word';

  @override
  String get whoIsImpostor => 'Who\'s the imposter?';
}
