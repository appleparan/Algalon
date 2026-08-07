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
