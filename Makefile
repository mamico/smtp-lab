.DEFAULT_GOAL := help

SMTP  = docker compose -f smtp-chaos/compose.yaml
PLONE = docker compose -f plone/compose.yaml
TOXI  = $(SMTP) exec -T toxiproxy /toxiproxy-cli

PROXY ?= smtp
QUEUE ?= 0

.PHONY: help up down smtp-up plone-up logs mail-plain mail-starttls mail-ssl _mail send \
        latency timeout-down reset-peer limit-data reset-toxics toxics

help: ## Show this help
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo "Vars: PROXY=smtp|smtps (default smtp)  QUEUE=0|1  MS=<ms>  BYTES=<n>"

up: smtp-up plone-up ## Start SMTP bench + Plone
down: ## Stop everything
	-$(PLONE) down
	$(SMTP) down
smtp-up: ## Start Mailpit + Toxiproxy (+ TLS terminator)
	$(SMTP) up -d --wait
plone-up: ## Start Plone (ZEO + client) with editable zope.sendmail
	$(PLONE) up -d
logs: ## Follow Plone logs
	$(PLONE) logs -f plone

mail-plain: ## Configure MailHost: plain SMTP via proxy :2525
	@$(MAKE) --no-print-directory _mail MODE=plain
mail-starttls: ## Configure MailHost: STARTTLS (force_tls) via proxy :2525
	@$(MAKE) --no-print-directory _mail MODE=starttls
mail-ssl: ## Configure MailHost: implicit SSL via proxy :4650
	@$(MAKE) --no-print-directory _mail MODE=ssl
_mail:
	@$(PLONE) exec -T -e SMTP_MODE=$(MODE) -e SMTP_QUEUE=$(QUEUE) plone /app/docker-entrypoint.sh run /scripts/configure_mail.py 2>&1 | grep -E "^(MailHost|OK|FAILED|Traceback)|Error"
send: ## Send one test mail through Plone, print result + timing
	@$(PLONE) exec -T plone /app/docker-entrypoint.sh run /scripts/send_test.py 2>&1 | grep -E "^(MailHost|OK|FAILED|Traceback)|Error"

latency: ## Add latency toxic to PROXY (MS=5000)
	$(TOXI) toxic add -n t_latency -t latency -a latency=$(or $(MS),5000) $(PROXY)
timeout-down: ## Accept connection then stall forever (socket timeout test)
	$(TOXI) toxic add -n t_timeout -t timeout -a timeout=0 $(PROXY)
reset-peer: ## Send TCP RST (after MS ms, default immediately)
	$(TOXI) toxic add -n t_reset -t reset_peer -a timeout=$(or $(MS),0) $(PROXY)
limit-data: ## Cut connection after BYTES bytes (default 200)
	$(TOXI) toxic add -n t_limit -t limit_data -a bytes=$(or $(BYTES),200) $(PROXY)
reset-toxics: ## Remove all toxics from PROXY
	@for t in t_latency t_timeout t_reset t_limit; do $(TOXI) toxic remove -n $$t $(PROXY) >/dev/null 2>&1; done; true
	@echo "toxics cleared on $(PROXY)"
toxics: ## List proxies and toxics
	$(TOXI) list
	$(TOXI) inspect $(PROXY)
