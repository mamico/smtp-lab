"""Point the Plone MailHost at the smtp-lab proxy.

Run via `make mail-plain|mail-starttls|mail-ssl` (SMTP_QUEUE=1 enables the queue).
"""
import os

import transaction
from plone.registry.interfaces import IRegistry
from Testing.makerequest import makerequest
from zope.component import getUtility
from zope.component.hooks import setSite

mode = os.environ.get("SMTP_MODE", "plain")
queue = os.environ.get("SMTP_QUEUE", "0") == "1"
app = makerequest(app)  # noqa: F821 - injected by zconsole
site = app["Plone"]
setSite(site)

mh = site.MailHost
mh.manage_makeChanges(
    title="smtp-lab",
    smtp_host="toxiproxy",
    smtp_port=4650 if mode == "ssl" else 2525,
    smtp_uid="",
    smtp_pwd="",
    smtp_queue=queue,
    smtp_queue_directory="/data/mailqueue",
    force_tls=(mode == "starttls"),
    implicit_tls=(mode == "ssl"),
)
# Products.CMFPlone patches SMTPMailer to take host/port/credentials from the
# registry, so set them there; TLS flags still come from the MailHost object.
registry = getUtility(IRegistry)
registry["plone.smtp_host"] = mh.smtp_host
registry["plone.smtp_port"] = mh.smtp_port
registry["plone.smtp_userid"] = None
registry["plone.smtp_pass"] = None
site.manage_changeProperties(email_from_address="lab@example.com", email_from_name="Lab")
transaction.commit()
print("MailHost: %s:%s mode=%s queue=%s" % (mh.smtp_host, mh.smtp_port, mode, queue))
