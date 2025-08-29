{{- define "gpt-helm.name" -}}
gpt-helm
{{- end -}}

{{- define "gpt-helm.fullname" -}}
{{ .Release.Name }}-gpt-helm
{{- end -}}
