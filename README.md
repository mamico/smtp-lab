# smtp-lab

Reusable Docker Compose test bench for anything that sends mail over SMTP:

- **smtp-chaos/** – [Mailpit](https://mailpit.axllent.org/) (dev SMTP server + web UI)
  behind [Toxiproxy](https://github.com/Shopify/toxiproxy) to inject latency,
  stalls, resets and truncated connections. Offers plain, STARTTLS and implicit TLS.
- **plone/** – Plone 6.1 (ZEO + client) with a local `zope.sendmail` checkout
  installed editable from source, wired to the bench. Use it as a template for
  other stacks: just join the external `smtp-lab` network.

```
client ──> toxiproxy:2525 ──> mailpit:1025            (plain, STARTTLS offered)
client ──> toxiproxy:4650 ──> smtps:465 (TLS) ──> mailpit:1025   (implicit TLS)
```

The TLS certificate is self-signed (SAN: toxiproxy, smtps, mailpit, localhost),
generated on first start into the `certs` volume. `smtplib` does not verify it
by default in zope.sendmail, so no CA setup is needed.

## Quick start

```sh
make help          # list all targets
make up            # start SMTP bench + Plone (first start creates the site)
make mail-plain    # point Plone MailHost at the proxy (or mail-starttls / mail-ssl)
make send          # send one mail, prints OK/FAILED + elapsed time
```

- Mailpit UI: <http://localhost:8025>
- Plone: <http://localhost:8080> (Zope user `admin` / `admin`)
- Toxiproxy API: <http://localhost:8474>
- From the host: SMTP `localhost:2525`, SMTPS `localhost:4650`

## Testing errors and timeouts

Toxics apply to the proxy named by `PROXY` (`smtp` default, or `smtps`):

```sh
make timeout-down  # accept then stall: expect failure after the socket timeout
make send
make reset-toxics

make latency MS=3000      # slow server, still succeeds if below the timeout
make reset-peer           # TCP RST
make limit-data BYTES=200 # cut connection mid-conversation
make toxics               # show current toxics
PROXY=smtps make timeout-down   # same on the implicit-TLS path
```

For anything else use `toxiproxy-cli` directly:
`docker compose -f smtp-chaos/compose.yaml exec toxiproxy /toxiproxy-cli --help`.

Use `QUEUE=1 make mail-plain` to enable the MailHost queue (processed by
zope.sendmail's `QueueProcessorThread` inside the Plone client).

## Source checkouts

`src/` holds the packages installed editable in Plone (git-ignored; clone or
`git worktree add` whatever branches you want to test):

```sh
git clone -b <branch> https://github.com/zopefoundation/zope.sendmail src/zope.sendmail
git clone -b <branch> https://github.com/zopefoundation/Products.MailHost src/Products.MailHost
```

`plone/compose.yaml` bind-mounts them under `/app/src/` and the image
entrypoint runs `pip install --editable` on them (`DEVELOP`) on every start.
Override the paths via `ZOPE_SENDMAIL_SRC` / `MAILHOST_SRC` (see `.env.example`).
Host edits need a Plone restart: `docker compose -f plone/compose.yaml restart plone`.

## Notes

- Products.CMFPlone patches `SMTPMailer` to read host, port and credentials from
  the Plone registry (`plone.smtp_*`), ignoring the MailHost attributes.
  `scripts/configure_mail.py` sets both; TLS flags (`force_tls`,
  `implicit_tls`) still come from the MailHost object.
- Plone's registry/MailHost config lives in ZEO (`zeo-data` volume);
  `make down` keeps it. Remove with `docker volume rm plone-smtp-lab_zeo-data`.
- Each `make send` / `make mail-*` goes through the image entrypoint, which
  re-runs the editable install, so they take a few seconds.
- Reusing the SMTP bench elsewhere: start `smtp-chaos` and attach your service to
  the `smtp-lab` network (`external: true`), then use `toxiproxy:2525` / `:4650`.
