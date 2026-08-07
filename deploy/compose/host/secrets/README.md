# Alertmanager secrets

Put one Slack incoming-webhook URL per file (file content = the bare URL):

    slack_webhook_critical
    slack_webhook_warning

Both may contain the same URL if you use a single channel. Files here are
gitignored — never commit webhook URLs.
