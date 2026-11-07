// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry_api/dartastic_opentelemetry_api.dart';

import 'otel_workos_suppression.dart';

const _tracerName = 'dartastic_otel_libs_workos';

APITracer _tracer() => OTelAPI.tracerProvider().getTracer(_tracerName);

class WorkosResult {
  /// Creates a result.
  const WorkosResult({
    this.requestId,
    this.organizationId,
    this.userId,
    this.connectionType,
    this.directoryProvider,
    this.eventCount,
    this.statusCode,
  });

  /// `X-Request-Id` header on the response.
  final String? requestId;

  /// `organization_id` — primary multi-tenant slicing dimension.
  final String? organizationId;
  final String? userId;

  /// SSO connection type — `OktaSAML`, `AzureSAML`, `GoogleOAuth`,
  /// `GenericOIDC`, etc. Surfaces upstream IdP from a single dim.
  final String? connectionType;

  /// Directory Sync provider — `okta scim v2.0`, `azure scim v2.0`,
  /// `gsuite directory`, etc. Distinct from connectionType because
  /// SSO and Directory Sync can use different upstreams.
  final String? directoryProvider;

  /// Number of audit log / events returned in a batch fetch.
  final int? eventCount;
  final int? statusCode;
}

/// What a traced call returned: the value for the caller plus fields
/// recorded on the span.
class WorkosCallResult<T> {
  /// Creates a call result.
  const WorkosCallResult({required this.value, this.result});

  /// The value returned to the caller.
  final T value;
  final WorkosResult? result;
}

/// Wraps a WorkOS API call in a CLIENT span. [operation] is the wire
/// op like `sso.authentication.authorize`, `sso.profile.get`,
/// `directory_sync.users.list`, `audit_logs.create_event`, etc.
///
/// [module] is the WorkOS product family — `sso`, `directory_sync`,
/// `authkit`, `audit_logs`, `admin_portal`, `webhooks`, `events`,
/// `mfa`, `passwordless`, `organizations`. Slicing dim distinct from
/// operation so usage-per-product is queryable.
Future<T> tracedWorkos<T>({
  required String operation,
  required String module,
  required Future<WorkosCallResult<T>> Function() invoke,
}) async {
  if (workosInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'rpc.system': 'workos',
    'rpc.method': operation,
    'workos.module': module,
  };

  final span = _tracer().startSpan(
    'workos $module.$operation',
    kind: SpanKind.client,
    attributes: OTelAPI.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.requestId != null) {
        extras.add(OTelAPI.attributeString(
          'workos.request.id',
          r.result!.requestId!,
        ));
      }
      if (r.result!.organizationId != null) {
        extras.add(OTelAPI.attributeString(
          'workos.organization.id',
          r.result!.organizationId!,
        ));
      }
      if (r.result!.userId != null) {
        extras.add(OTelAPI.attributeString('user.id', r.result!.userId!));
      }
      if (r.result!.connectionType != null) {
        extras.add(OTelAPI.attributeString(
          'workos.sso.connection_type',
          r.result!.connectionType!,
        ));
      }
      if (r.result!.directoryProvider != null) {
        extras.add(OTelAPI.attributeString(
          'workos.directory_sync.provider',
          r.result!.directoryProvider!,
        ));
      }
      if (r.result!.eventCount != null) {
        extras.add(OTelAPI.attributeInt(
          'workos.event_count',
          r.result!.eventCount!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTelAPI.attributeInt(
          'http.response.status_code',
          r.result!.statusCode!,
        ));
        if (r.result!.statusCode! >= 400) {
          span.setStatus(
            SpanStatusCode.Error,
            'WorkOS status ${r.result!.statusCode}',
          );
        }
      }
      if (extras.isNotEmpty) span.addAttributes(OTelAPI.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTelAPI.attributes([
      OTelAPI.attributeString(
        ErrorAttributes.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
