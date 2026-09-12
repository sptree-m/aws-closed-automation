# aws-closed-automation

Automation for building and proving a closed AWS Claude Code environment.

## Evidence automation

The repository now includes a deployment-evidence pipeline that:
- captures AWS resource state with AWS CLI,
- executes isolation tests from the Claude host through SSM,
- produces PASS/FAIL results,
- generates Markdown and HTML reports,
- creates SHA-256 hashes for tamper detection,
- optionally uploads evidence to an encrypted S3 bucket.

### Quick start

1. Copy the example configuration.

```bash
cp config/evidence.example.env .env
```

2. Fill in the actual resource IDs.

3. Run:

```bash
bash scripts/run_all.sh
```

Output is written under `evidence/<UTC timestamp>/`.

For automated execution, use the self-hosted GitHub Actions workflow in `.github/workflows/evidence-self-hosted.yml`.

See `docs/EVIDENCE_DESIGN.md` for the control model and production hardening items.

> Generated evidence must not be committed to this repository. It can contain internal AWS identifiers and private network information.
