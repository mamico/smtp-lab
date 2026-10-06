"""Send one test mail through the Plone MailHost; print result and timing."""
import time

import transaction
from Testing.makerequest import makerequest
from zope.component.hooks import setSite

app = makerequest(app)  # noqa: F821 - injected by zconsole
setSite(app["Plone"])
t = time.time()
try:
    app["Plone"].MailHost.send(
        "hello from smtp-lab", "dest@example.com", "lab@example.com", "smtp-lab test"
    )
    transaction.commit()
    print("OK after %.2fs" % (time.time() - t))
except Exception as e:
    import traceback
    traceback.print_exc()
    print("FAILED after %.2fs: %r" % (time.time() - t, e))
