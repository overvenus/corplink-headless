build:
	docker build -t overvenus/corplink:latest .

macos-up:
	./scripts/macos/corplink-vm.sh up --company-code "$(COMPANY_CODE)"

macos-logs:
	./scripts/macos/corplink-vm.sh logs -f

macos-status:
	./scripts/macos/corplink-vm.sh status

macos-down:
	./scripts/macos/corplink-vm.sh down

macos-shell:
	./scripts/macos/corplink-vm.sh shell

macos-destroy:
	./scripts/macos/corplink-vm.sh destroy
