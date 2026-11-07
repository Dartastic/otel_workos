// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_workos/otel_workos.dart';

/// Traces WorkOS calls with OpenTelemetry.
///
/// `otel_workos` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each WorkOS call in
/// [tracedWorkos]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'workos-example');

  // Wraps a WorkOS API call in a CLIENT span.
  final workosId = await tracedWorkos<String>(
    operation: 'audit_logs.create_event',
    module: 'sso',
    invoke: () async {
      // Make the WorkOS call here, then report what it returned.
      const id = 'workos_8f3a2c';
      return const WorkosCallResult(
          value: id,
          result: WorkosResult(
              requestId: 'request_8f3a2c',
              organizationId: 'organization_id',
              userId: 'user_8f3a2c',
              connectionType: 'OktaSAML',
              directoryProvider: 'example',
              eventCount: 3,
              statusCode: 201));
    },
  );
  OTelLog.info('tracedWorkos audit_logs.create_event returned $workosId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutWorkosInstrumentationAsync.
  await runWithoutWorkosInstrumentationAsync(
    () => tracedWorkos<String>(
      operation: 'audit_logs.create_event',
      module: 'sso',
      invoke: () async {
        const id = 'workos_8f3a2c';
        return const WorkosCallResult(
            value: id,
            result: WorkosResult(
                requestId: 'request_8f3a2c',
                organizationId: 'organization_id',
                userId: 'user_8f3a2c',
                connectionType: 'OktaSAML',
                directoryProvider: 'example',
                eventCount: 3,
                statusCode: 201));
      },
    ),
  );

  await OTel.shutdown();
}
