{{/*
Expand the name of the chart.
*/}}
{{- define "unityexpress.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "unityexpress.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "unityexpress.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels (includes your project UUID)
*/}}
{{- define "unityexpress.labels" -}}
helm.sh/chart: {{ include "unityexpress.chart" . }}
{{ include "unityexpress.selectorLabels" . }}
{{- if .Values.appVersion }}
app.kubernetes.io/version: {{ .Values.appVersion | quote }}
{{- else if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
project-uuid: {{ .Values.projectUuid | quote }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "unityexpress.selectorLabels" -}}
app.kubernetes.io/name: {{ include "unityexpress.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "unityexpress.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "unityexpress.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
=================================================================
COMPONENT-SPECIFIC HELPERS
=================================================================
*/}}

{{/*
API component fullname
*/}}
{{- define "unityexpress.api.fullname" -}}
{{- printf "%s-api" (include "unityexpress.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
API component labels
*/}}
{{- define "unityexpress.api.labels" -}}
{{ include "unityexpress.labels" . }}
app: unityexpress-api
component: api
{{- end }}

{{/*
Web component fullname
*/}}
{{- define "unityexpress.web.fullname" -}}
{{- printf "%s-web" (include "unityexpress.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Web component labels
*/}}
{{- define "unityexpress.web.labels" -}}
{{ include "unityexpress.labels" . }}
app: unityexpress-web
component: web
{{- end }}

{{/*
Gateway component fullname
*/}}
{{- define "unityexpress.gateway.fullname" -}}
{{- printf "%s-gateway" (include "unityexpress.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Gateway component labels
*/}}
{{- define "unityexpress.gateway.labels" -}}
{{ include "unityexpress.labels" . }}
app: unityexpress-gateway
component: gateway
{{- end }}

{{/*
Kafka component fullname
*/}}
{{- define "unityexpress.kafka.fullname" -}}
{{- printf "%s-kafka" (include "unityexpress.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Kafka component labels
*/}}
{{- define "unityexpress.kafka.labels" -}}
{{ include "unityexpress.labels" . }}
app: unityexpress-kafka
component: kafka
{{- end }}

{{/*
MongoDB component fullname
*/}}
{{- define "unityexpress.mongo.fullname" -}}
{{- printf "%s-mongo" (include "unityexpress.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
MongoDB component labels
*/}}
{{- define "unityexpress.mongo.labels" -}}
{{ include "unityexpress.labels" . }}
app: unityexpress-mongo
component: database
{{- end }}

{{/*
=================================================================
CONFIGURATION HELPERS
=================================================================
*/}}

{{/*
MongoDB connection URI
*/}}
{{- define "unityexpress.mongoUri" -}}
{{- if .Values.mongo.external.enabled }}
{{- .Values.mongo.external.uri }}
{{- else }}
{{- printf "mongodb://%s:%d/%s" (include "unityexpress.mongo.fullname" .) (.Values.mongo.port | int) .Values.mongo.database }}
{{- end }}
{{- end }}

{{/*
Kafka bootstrap servers
*/}}
{{- define "unityexpress.kafkaBrokers" -}}
{{- if .Values.kafka.external.enabled }}
{{- .Values.kafka.external.brokers }}
{{- else }}
{{- printf "%s.%s.svc.cluster.local:%d" (include "unityexpress.kafka.fullname" .) .Release.Namespace (.Values.kafka.port | int) }}
{{- end }}
{{- end }}

{{/*
Generate image pull policy based on tag
*/}}
{{- define "unityexpress.imagePullPolicy" -}}
{{- if hasSuffix "local" .tag }}
{{- "Never" }}
{{- else if or (hasSuffix "latest" .tag) (hasSuffix "dev" .tag) }}
{{- "Always" }}
{{- else }}
{{- "IfNotPresent" }}
{{- end }}
{{- end }}

{{/*
=================================================================
VALIDATION HELPERS
=================================================================
*/}}

{{/*
Validate required values
*/}}
{{- define "unityexpress.validateValues" -}}
{{- if and (not .Values.mongo.external.enabled) (not .Values.mongo.persistence.enabled) }}
{{- fail "MongoDB persistence must be enabled when using internal MongoDB" }}
{{- end }}
{{- if and .Values.kafka.external.enabled (not .Values.kafka.external.brokers) }}
{{- fail "kafka.external.brokers is required when kafka.external.enabled is true" }}
{{- end }}
{{- end }}

{{/*
=================================================================
ANNOTATION HELPERS
=================================================================
*/}}

{{/*
Config checksum annotation for triggering pod restarts
*/}}
{{- define "unityexpress.configChecksum" -}}
checksum/config: {{ include (print $.Template.BasePath "/kafka-secret.yaml") . | sha256sum }}
app-version: {{ .Values.appVersion | quote }}
deployed-at: {{ now | date "2006-01-02T15:04:05Z07:00" | quote }}
{{- end }}

{{/*
Common annotations
*/}}
{{- define "unityexpress.annotations" -}}
{{- if .Values.commonAnnotations }}
{{- toYaml .Values.commonAnnotations }}
{{- end }}
{{- end }}

{{/*
=================================================================
RESOURCE HELPERS
=================================================================
*/}}

{{/*
Return the appropriate API resources
*/}}
{{- define "unityexpress.api.resources" -}}
{{- if .Values.api.resources }}
resources:
{{- toYaml .Values.api.resources | nindent 2 }}
{{- else }}
resources:
  requests:
    memory: "256Mi"
    cpu: "100m"
  limits:
    memory: "512Mi"
    cpu: "500m"
{{- end }}
{{- end }}

{{/*
Return the appropriate web resources
*/}}
{{- define "unityexpress.web.resources" -}}
{{- if .Values.web.resources }}
resources:
{{- toYaml .Values.web.resources | nindent 2 }}
{{- else }}
resources:
  requests:
    memory: "128Mi"
    cpu: "50m"
  limits:
    memory: "256Mi"
    cpu: "200m"
{{- end }}
{{- end }}

{{/*
=================================================================
HEALTH CHECK HELPERS
=================================================================
*/}}

{{/*
API health check probes
*/}}
{{- define "unityexpress.api.probes" -}}
livenessProbe:
  httpGet:
    path: /health
    port: {{ .Values.api.port }}
  initialDelaySeconds: 60
  periodSeconds: 15
  timeoutSeconds: 5
  failureThreshold: 3
readinessProbe:
  httpGet:
    path: /ready
    port: {{ .Values.api.port }}
  initialDelaySeconds: 30
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3
{{- end }}

{{/*
Web health check probes
*/}}
{{- define "unityexpress.web.probes" -}}
livenessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 30
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /
    port: 80
  initialDelaySeconds: 10
  periodSeconds: 5
{{- end }}