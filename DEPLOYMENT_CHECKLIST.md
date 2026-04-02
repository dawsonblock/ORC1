════════════════════════════════════════════════════════════════════════════════
                    DEPLOYMENT CHECKLIST: SINGLE-HARD-PATH KERNEL
════════════════════════════════════════════════════════════════════════════════

PRE-DEPLOYMENT VERIFICATION
════════════════════════════════════════════════════════════════════════════════

□ Code Compilation
  □ swift build              # Should succeed
  □ swift build -c release   # Should succeed
  □ No deprecation warnings

□ Governance Tests
  □ swift test --filter Governance
    □ ExecutionBoundaryEnforcementTests (6 tests)
    □ CommitDurabilityTests (6 tests)
    □ TransitionalArtifactRemovalTests (7 tests)
  □ All 19 tests pass

□ Invariant Verification (Grep Checks)
  □ grep -r "case \.shell" Sources/OracleOS --include="*.swift"
    → MUST be 0 results
  □ grep -r "= Process()" Sources/OracleOS | grep -v DefaultProcessAdapter
    → MUST be 0 results in runtime
  □ grep -r "planner.plan(" Sources/OracleOS --include="*.swift"
    → MUST be RuntimeOrchestrator.swift only
  □ grep -r "PlannerFacade" Sources/OracleOS --include="*.swift"
    → MUST be 0 results (deleted)

□ Integration Tests
  □ swift test               # Full test suite
  □ All tests pass

□ Code Review Checklist
  □ All 9 new files reviewed
  □ All 8 modified files reviewed
  □ PlannerFacade deletion verified safe
  □ Commit message accurate
  □ Documentation complete

════════════════════════════════════════════════════════════════════════════════

DEPLOYMENT STEPS
════════════════════════════════════════════════════════════════════════════════

1. Create Feature Branch
   git checkout -b feat/single-hard-path-kernel

2. Stage Changes
   git add Sources/OracleOS/
   git add Tests/OracleOSTests/Governance/
   git add *.md *.txt
   git status  # Review what's staged

3. Commit (See COMMIT_MESSAGE.txt for full message)
   git commit -m "feat(runtime): complete single-hard-path kernel rebuild (all 7 phases)" \
              -m "" \
              -m "See COMPLETE_REBUILD_SUMMARY.md for comprehensive details." \
              -m "" \
              -m "Assisted-By: docker-agent"

4. Verify Commit
   git log --oneline -1  # Show commit
   git show --name-status  # Show files changed

5. Push Feature Branch
   git push origin feat/single-hard-path-kernel

6. Create Pull Request
   - Title: "Single-Hard-Path Kernel: All 7 Phases Complete"
   - Description: Copy from COMMIT_MESSAGE.txt
   - Link documentation: INDEX.md
   - Request reviewers

7. Code Review & CI
   □ CI builds successfully
   □ All tests pass
   □ Code review approved
   □ Two approvals (if required)

8. Merge (When Approved)
   git checkout main
   git pull origin main
   git merge --no-ff feat/single-hard-path-kernel
   git push origin main

9. Delete Feature Branch
   git push origin --delete feat/single-hard-path-kernel
   git branch -d feat/single-hard-path-kernel

════════════════════════════════════════════════════════════════════════════════

POST-DEPLOYMENT VERIFICATION
════════════════════════════════════════════════════════════════════════════════

□ On main branch
  □ Verify commit is in history: git log --oneline main | grep "single-hard-path"

□ Run Full Test Suite (Production Build)
  □ swift build -c release
  □ swift test -c release

□ Verify Integration With External Surfaces
  □ MCP tools still work
  □ CLI (oracle) still works
  □ Controller (OracleController) still works

□ Update Documentation
  □ Add link to COMPLETE_REBUILD_SUMMARY.md in main README
  □ Update architecture documentation
  □ Document new typed specs (BuildSpec, TestSpec, etc.)

□ Communicate Changes
  □ Team notification: "Single-hard-path kernel deployed"
  □ Summary: Intent → Planner → Executor → Commit (unified spine)
  □ Impact: No user-facing changes; internal architecture only

════════════════════════════════════════════════════════════════════════════════

ROLLBACK PLAN (If Issues)
════════════════════════════════════════════════════════════════════════════════

If critical issues discovered:

1. Revert Commit
   git revert <commit-hash>  # Creates new commit that undoes changes
   OR
   git reset --hard <parent-commit-hash>  # Hard reset to before deployment

2. Push Revert
   git push origin main

3. Investigate Issue
   - Check test failures
   - Check grep verification (invariants)
   - Check integration test results

4. Fix Issues
   - Correct problems
   - Re-test locally
   - Create new PR with fixes

════════════════════════════════════════════════════════════════════════════════

SUCCESS CRITERIA
════════════════════════════════════════════════════════════════════════════════

Deployment is successful when:

✅ All code compiles without warnings
✅ All governance tests pass (19/19)
✅ All grep invariant checks pass (4/4)
✅ No .shell remains in codebase
✅ No Process() outside DefaultProcessAdapter
✅ Only RuntimeOrchestrator calls planner
✅ All integration tests pass
✅ No user-facing regressions
✅ Documentation updated
✅ Team notified

════════════════════════════════════════════════════════════════════════════════

MAINTENANCE NOTES
════════════════════════════════════════════════════════════════════════════════

After Deployment:

1. Keep Governance Tests Active
   - Run 'swift test --filter Governance' in CI
   - Fail the build if any governance test fails

2. Monitor Invariants
   - Occasionally run grep checks
   - Alert if .shell, direct Process(), or alternate paths reappear

3. Document Code Changes
   - Mark any new execution paths with:
     // ⚠️ INVARIANT: This path must route through VerifiedExecutor
   
4. Future Phases (Optional)
   - Phase 5-7 governance can be enhanced
   - Add compile-time guards (shadow Process in critical modules)
   - Add distributed tracing
   - Add formal verification

════════════════════════════════════════════════════════════════════════════════

                    READY FOR DEPLOYMENT ✅
════════════════════════════════════════════════════════════════════════════════
