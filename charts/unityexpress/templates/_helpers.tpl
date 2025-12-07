{{- define "unityexpress.labels" -}}
app.kubernetes.io/name: unityexpress
app.kubernetes.io/instance: unityexpress
project-uuid: {{ .Values.projectUuid | quote }}
{{- end }}
