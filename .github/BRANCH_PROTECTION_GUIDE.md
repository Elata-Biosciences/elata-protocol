# Branch Protection Setup Guide

This guide explains how to configure GitHub branch protection rules to ensure code quality and prevent breaking changes.

## Why Branch Protection?

✅ **Prevent broken code** from being merged to main  
✅ **Require passing tests** before merge  
✅ **Enforce code review** standards  
✅ **Maintain clean history** with required status checks  

## Recommended Configuration

### For `main` Branch (Production)

1. **Go to Repository Settings**
   - Navigate to: `Settings` → `Branches` → `Add branch protection rule`
   - Branch name pattern: `main`

2. **Require Status Checks**
   - ✅ **Check:** "Require status checks to pass before merging"
   - ✅ **Check:** "Require branches to be up to date before merging"
   
   **Select these required checks:**
   - ✅ `Foundry Tests` (from ci.yml)
   - ✅ `Code Quality` (from ci.yml)
   - ✅ `Foundry project` (from test.yml)
   - ⚠️ **DO NOT require:** `Test Coverage` (it's allowed to fail)

3. **Require Pull Request Reviews**
   - ✅ **Check:** "Require a pull request before merging"
   - **Required approvals:** `1` (or more for stricter review)
   - ✅ **Check:** "Dismiss stale pull request approvals when new commits are pushed"
   - ✅ **Check:** "Require review from Code Owners" (optional, if you have CODEOWNERS)

4. **Additional Protections**
   - ✅ **Check:** "Require conversation resolution before merging"
   - ✅ **Check:** "Require linear history" (optional, for cleaner git log)
   - ✅ **Check:** "Do not allow bypassing the above settings" (even for admins)
   - ⚠️ **Uncheck:** "Allow force pushes" (DANGEROUS!)
   - ⚠️ **Uncheck:** "Allow deletions" (DANGEROUS!)

5. **Merge Requirements**
   - ✅ **Check:** "Require deployments to succeed before merging" (if you have deployment workflows)
   - ✅ **Check:** "Lock branch" (optional, for extra protection)

### For `develop` Branch (Integration)

Less strict than main:
- ✅ Require status checks (same as main)
- ✅ Require 1 approver (or allow self-review)
- ✅ Require conversation resolution
- ⚠️ Allow force pushes if needed for rebasing

## Visual Guide

```
┌─────────────────────────────────────────────────────────┐
│  Branch Protection Rule: main                           │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ✅ Require a pull request before merging               │
│     └─ Required approvals: 1                            │
│     └─ Dismiss stale approvals: ✅                       │
│                                                         │
│  ✅ Require status checks to pass before merging        │
│     └─ Require branches to be up to date: ✅            │
│     └─ Status checks required:                          │
│        • Foundry Tests          ← BLOCKS if failing     │
│        • Code Quality           ← BLOCKS if failing     │
│        • Foundry project        ← BLOCKS if failing     │
│        ✗ Test Coverage          ← Does NOT block        │
│                                                         │
│  ✅ Require conversation resolution                     │
│                                                         │
│  ⚠️ Do not allow bypassing (enforce for admins)         │
│  ⚠️ Do not allow force pushes                           │
│  ⚠️ Do not allow deletions                              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

## How It Works

### ✅ When Tests Pass
```
Developer → Creates PR → CI runs:
  ✅ Foundry Tests: PASS
  ✅ Code Quality: PASS  
  ✅ Foundry project: PASS
  ⚠️ Test Coverage: FAIL (non-blocking)

Result: ✅ "All checks have passed" → Merge button enabled
```

### ❌ When Tests Fail
```
Developer → Creates PR → CI runs:
  ❌ Foundry Tests: FAIL (e.g., 421/422 tests passing)
  ✅ Code Quality: PASS
  ✅ Foundry project: PASS
  ⚠️ Test Coverage: FAIL (non-blocking)

Result: ❌ "Required checks failing" → Merge button BLOCKED 🚫
```

## Setting It Up (Step-by-Step)

### Option 1: Via GitHub Web UI

1. Go to: https://github.com/Elata-Biosciences/elata-protocol/settings/branches
2. Click **"Add rule"** or **"Edit"** if `main` rule exists
3. Enter `main` as branch name pattern
4. Configure settings as shown above
5. Click **"Create"** or **"Save changes"**

### Option 2: Via GitHub CLI (if you have it)

```bash
# Install GitHub CLI: https://cli.github.com/

# Protect main branch
gh api repos/Elata-Biosciences/elata-protocol/branches/main/protection \
  -X PUT \
  -H "Accept: application/vnd.github+json" \
  --input - <<EOF
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "Foundry Tests",
      "Code Quality",
      "Foundry project"
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "dismiss_stale_reviews": true
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_conversation_resolution": true
}
EOF
```

## Testing the Protection

After setting up, test it:

1. **Create a test branch:**
   ```bash
   git checkout -b test-branch-protection
   ```

2. **Break a test intentionally:**
   ```solidity
   // In any test file, change an assertion:
   assertEq(1, 2); // This will fail
   ```

3. **Push and create PR:**
   ```bash
   git add -A
   git commit -m "test: intentionally break test"
   git push -u origin test-branch-protection
   ```

4. **Check GitHub:**
   - ❌ Status checks should fail
   - 🚫 Merge button should be BLOCKED
   - ✅ Protection is working!

5. **Clean up:**
   - Close the test PR
   - Delete the test branch

## What Gets Blocked vs What Doesn't

### ✅ BLOCKS Merging (Required):
- `Foundry Tests` job failing → Blocks ✅
- `Code Quality` job failing → Blocks ✅
- `Foundry project` job failing → Blocks ✅
- Code not up to date with base → Blocks ✅
- No approving review → Blocks ✅

### ⚠️ DOES NOT Block (Optional):
- `Test Coverage` job failing → Allowed ✅ (known limitation)
- Unresolved conversations → Can be configured either way

## Advanced: CODEOWNERS File

For extra protection, create a `CODEOWNERS` file:

```bash
# .github/CODEOWNERS

# Default owners for everything
* @wkyleg

# Core protocol contracts require extra review
/src/token/ @wkyleg @core-team
/src/staking/ @wkyleg @core-team
/src/governance/ @wkyleg @core-team

# Tests can be reviewed by anyone
/test/ @wkyleg

# CI/CD changes require admin review
/.github/ @wkyleg
```

Then in branch protection:
- ✅ Check "Require review from Code Owners"

## Monitoring & Alerts

Set up notifications for failed checks:

1. **Repository → Settings → Notifications**
2. Configure alerts for:
   - Failed workflows
   - Required checks failing
   - Force push attempts (should never happen with protection)

## Emergency Override

If you absolutely need to merge despite failing checks (emergencies only):

1. **Temporarily disable protection:**
   - Settings → Branches → Edit rule
   - Uncheck "Do not allow bypassing"
   - Merge the emergency fix
   - **IMMEDIATELY re-enable protection**

2. **Better approach:**
   - Fix the issue on a hotfix branch
   - Ensure tests pass
   - Merge normally

## Verification Checklist

After setup, verify:
- [ ] Create test PR with failing test → Merge blocked
- [ ] Create test PR with passing tests → Merge allowed  
- [ ] Try force push to main → Should be rejected
- [ ] Coverage fails but tests pass → Merge allowed
- [ ] Check notifications are working

## Current Workflow Jobs

Based on your setup:

**ci.yml (triggers on push & PR):**
- ✅ `Foundry Tests` - **REQUIRED** (blocks if fails)
- ✅ `Code Quality` - **REQUIRED** (blocks if fails)
- ⚠️ `Test Coverage` - **OPTIONAL** (non-blocking)

**test.yml (triggers on all pushes):**
- ✅ `Foundry project` - **REQUIRED** (blocks if fails)

## Recommended Settings Summary

```yaml
Branch: main
├─ Require PR before merging: YES
├─ Required approvals: 1+
├─ Dismiss stale reviews: YES
├─ Require status checks:
│  ├─ Foundry Tests (ci.yml) ✅ REQUIRED
│  ├─ Code Quality (ci.yml) ✅ REQUIRED  
│  ├─ Foundry project (test.yml) ✅ REQUIRED
│  └─ Test Coverage (ci.yml) ⚠️ OPTIONAL
├─ Require conversation resolution: YES
├─ Require up-to-date branches: YES
├─ Enforce for admins: YES
├─ Allow force pushes: NO ⛔
└─ Allow deletions: NO ⛔
```

## Benefits

With proper branch protection:
- 🛡️ **422 tests must pass** before any code reaches main
- 🔍 **Code formatting enforced** automatically
- 👥 **Peer review required** for all changes
- 📊 **Coverage fails gracefully** without blocking progress
- 🚀 **Quality maintained** while allowing rapid development

## Next Steps

1. Go to: https://github.com/Elata-Biosciences/elata-protocol/settings/branches
2. Configure protection rules as described above
3. Test with a dummy PR
4. Document your team's review process
5. Communicate rules to all contributors

---

**Remember:** The goal is to make it **hard to break main** while keeping development **fast and efficient**. Branch protection + pre-commit hooks = 🎯 perfect balance!

