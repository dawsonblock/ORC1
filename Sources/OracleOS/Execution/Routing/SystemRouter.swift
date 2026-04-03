// SystemRouter.swift — TOMBSTONE
//
// SystemRouter was removed in ORC1-main-5 because it was dead code:
//   - CommandType.system was the only type it accepted.
//   - Every payload case (.build, .test, .git, .file, .ui, .code) returned failureOutcome.
//   - No planner (MainPlanner, planSystemIntent, CommandAssembler) ever emitted CommandType.system.
//     planSystemIntent always produces CommandType.ui commands.
//   - CommandType.system has been removed from the CommandType enum.
//
// Intent domain IntentDomain.system (open/launch) correctly maps to CommandType.ui
// commands via planSystemIntent → UIAction("launchApp"/"openURL").
// There is no missing routing path — code was already correct; the taxonomy was the lie.
//
// This file is a tombstone. It can be deleted once the explanation is understood.
