.PHONY: opnsense-validate opnsense-test opnsense-plan

opnsense-validate:
	python3 scripts/verify-voice-pe.py validate

opnsense-test:
	python3 -m unittest discover -s tests -p 'test_opnsense_nat_plan.py' -v

opnsense-plan: opnsense-validate
	python3 scripts/opnsense-nat-plan.py plan
