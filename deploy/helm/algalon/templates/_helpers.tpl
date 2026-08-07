{{/*
Chart name, used as the app.kubernetes.io/name label.
Call with the root context: {{ include "algalon.name" . }}
*/}}
{{- define "algalon.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name, used as the base for resource names.
Release-name based; the chart name is not repeated when the release name
already contains it. Truncated at 63 chars (DNS label limit).
Call with the root context: {{ include "algalon.fullname" . }}
*/}}
{{- define "algalon.fullname" -}}
{{- $name := .Chart.Name -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Name of the Secret holding the Slack webhook URLs for Alertmanager.
Either the operator brings their own Secret (existingSecret) or the chart
renders one from both URLs. Neither configured is a hard error: Alertmanager
reads the webhooks as files and would start with a permanently broken
notifier, so fail at render time instead of shipping a silent outage.
Call with the root context: {{ include "algalon.alertmanagerSecretName" . }}
*/}}
{{- define "algalon.alertmanagerSecretName" -}}
{{- $slack := .Values.alertmanager.slack -}}
{{- if $slack.existingSecret -}}
{{- $slack.existingSecret -}}
{{- else if and $slack.criticalUrl $slack.warningUrl -}}
{{- printf "%s-alertmanager-slack" (include "algalon.fullname" .) -}}
{{- else -}}
{{- fail "alertmanager.slack is not configured: set alertmanager.slack.existingSecret to an existing Secret with keys slack_webhook_critical/slack_webhook_warning, or set BOTH alertmanager.slack.criticalUrl and alertmanager.slack.warningUrl so the chart can create one." -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels for a single component.
Call with a dict carrying the root context and the component name:
{{ include "algalon.selectorLabels" (dict "ctx" $ "component" "vmagent") }}
*/}}
{{- define "algalon.selectorLabels" -}}
app.kubernetes.io/name: {{ include "algalon.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end -}}

{{/*
Full metadata labels for a single component (selector labels + provenance).
Call with a dict carrying the root context and the component name:
{{ include "algalon.labels" (dict "ctx" $ "component" "vmagent") | nindent 4 }}
*/}}
{{- define "algalon.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .ctx.Chart.Name .ctx.Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "algalon.selectorLabels" . }}
app.kubernetes.io/version: {{ .ctx.Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
{{- end -}}
