// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_workos/otel_workos.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_workos-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('SSO profile records connection_type + org', () async {
    await tracedWorkos<String>(
      module: 'sso',
      operation: 'profile.get',
      invoke: () async => const WorkosCallResult(
        value: 'ok',
        result: WorkosResult(
          requestId: 'req-1',
          organizationId: 'org_01',
          userId: 'user_01',
          connectionType: 'OktaSAML',
          statusCode: 200,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName('workos sso.profile.get')!);
    expect(a['rpc.system'], 'workos');
    expect(a['workos.module'], 'sso');
    expect(a['workos.sso.connection_type'], 'OktaSAML');
    expect(a['workos.organization.id'], 'org_01');
  });

  test('Directory Sync list records provider + event count', () async {
    await tracedWorkos<String>(
      module: 'directory_sync',
      operation: 'users.list',
      invoke: () async => const WorkosCallResult(
        value: 'ok',
        result: WorkosResult(
          directoryProvider: 'azure scim v2.0',
          eventCount: 250,
        ),
      ),
    );
    final a = attrsOf(spans.findSpanByName(
      'workos directory_sync.users.list',
    )!);
    expect(a['workos.directory_sync.provider'], 'azure scim v2.0');
    expect(a['workos.event_count'], 250);
  });

  test('4xx maps to span error', () async {
    await tracedWorkos<String>(
      module: 'authkit',
      operation: 'authenticate',
      invoke: () async => const WorkosCallResult(
        value: 'ok',
        result: WorkosResult(statusCode: 401),
      ),
    );
    expect(
      spans.findSpanByName('workos authkit.authenticate')!.status,
      SpanStatusCode.Error,
    );
  });

  test('suppression skips spans', () async {
    await runWithoutWorkosInstrumentationAsync(() async {
      await tracedWorkos<String>(
        module: 'sso',
        operation: 'authorize',
        invoke: () async => const WorkosCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('workos '), isEmpty);
  });
}
