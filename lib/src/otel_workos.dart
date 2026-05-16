// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_workos_suppression.dart';

const _tracerName = 'dartastic_otel_libs_workos';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class WorkosResult {
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

class WorkosCallResult<T> {
  const WorkosCallResult({required this.value, this.result});
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
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.requestId != null) {
        extras.add(OTel.attributeString(
          'workos.request.id',
          r.result!.requestId!,
        ));
      }
      if (r.result!.organizationId != null) {
        extras.add(OTel.attributeString(
          'workos.organization.id',
          r.result!.organizationId!,
        ));
      }
      if (r.result!.userId != null) {
        extras.add(OTel.attributeString('user.id', r.result!.userId!));
      }
      if (r.result!.connectionType != null) {
        extras.add(OTel.attributeString(
          'workos.sso.connection_type',
          r.result!.connectionType!,
        ));
      }
      if (r.result!.directoryProvider != null) {
        extras.add(OTel.attributeString(
          'workos.directory_sync.provider',
          r.result!.directoryProvider!,
        ));
      }
      if (r.result!.eventCount != null) {
        extras.add(OTel.attributeInt(
          'workos.event_count',
          r.result!.eventCount!,
        ));
      }
      if (r.result!.statusCode != null) {
        extras.add(OTel.attributeInt(
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
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
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
