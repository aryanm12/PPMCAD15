# Session 1: Terraform Fundamentals — Discussion Guide

## Discussion Topic 1: Infrastructure as Code vs. Manual vs. Scripts

### Opening Question
"What are the pain points of manually deploying infrastructure via AWS Console? How is that different from writing shell scripts to automate it?"

### Discussion Points

**Manual (AWS Console/CLI)**
- Easy for one-offs, but:
  - No reproducibility across regions/accounts
  - No version control or audit trail
  - Configuration drift: server state differs from "intended"
  - Hard to scale (deploy to 10 regions = 10x clicking)
  - Team collaboration is error-prone

**Shell Scripts (bash/Python)**
- Automates AWS CLI calls, but:
  - Not idempotent: running twice might fail or create duplicates
  - Hard to track state (did it run? did it succeed?)
  - No built-in diff/preview before execution
  - Not declarative: script says "do this," not "desired state is this"
  - Hard to revert or rollback

**Infrastructure as Code (Terraform)**
- Declarative: "I want this EC2 instance to exist"
- Idempotent: running twice is safe (no duplicates)
- State tracking: Terraform knows what exists
- Plan-before-apply: preview changes
- Reversible: destroy is clean
- Team-friendly: code review, Git history

### Real-World Scenario
"You have 100 EC2 instances across 3 AWS regions. AWS releases a new instance type that's cheaper. How do you upgrade all 100? Manually? Script? Terraform?"

**With Terraform:** Change instance_type in code, terraform plan to see impact, terraform apply once. Done.

---
