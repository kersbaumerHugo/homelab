.PHONY: opnsense-validate opnsense-test opnsense-plan opnsense-backup-check opnsense-backup

opnsense-validate:
	python3 scripts/verify-voice-pe.py validate

opnsense-test:
	python3 -m unittest discover -s tests -p 'test_opnsense*.py' -v

opnsense-plan: opnsense-validate
	python3 scripts/opnsense-nat-plan.py plan

# Read-only API access check. Does not persist the downloaded configuration.
opnsense-backup-check:
	python3 scripts/opnsense-config-backup.py check

# Require an age public recipient (AGE_RECIPIENT) in the environment.
# Encrypted artifacts are stored outside this Git repository.
opnsense-backup:
	python3 scripts/opnsense-config-backup.py save
