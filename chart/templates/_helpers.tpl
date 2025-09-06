{{- define "greeter.name" -}}
{{- .Chart.Name -}}
{{- end }}

{{- define "greeter.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{- define "greeter.labels" -}}
app.kubernetes.io/name: {{ include "greeter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: Helm
{{- end }}

{{- define "greeter.selectorLabels" -}}
app.kubernetes.io/name: {{ include "greeter.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}