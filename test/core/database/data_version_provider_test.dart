import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liflow_app/core/database/repository_providers.dart';

void main() {
  test('domain versions notify only the affected data domain', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    var recordChanges = 0;
    var projectChanges = 0;
    final recordSubscription = container.listen<int>(
      dataDomainVersionProvider(DataDomain.records),
      (_, _) => recordChanges += 1,
    );
    final projectSubscription = container.listen<int>(
      dataDomainVersionProvider(DataDomain.projects),
      (_, _) => projectChanges += 1,
    );
    addTearDown(recordSubscription.close);
    addTearDown(projectSubscription.close);

    final notifier = container.read(dataVersionProvider.notifier);
    notifier.increment(domains: {DataDomain.projects});

    expect(container.read(dataDomainVersionProvider(DataDomain.records)), 0);
    expect(container.read(dataDomainVersionProvider(DataDomain.projects)), 1);
    expect(recordChanges, 0);
    expect(projectChanges, 1);

    notifier.increment(domains: {DataDomain.records});

    expect(container.read(dataDomainVersionProvider(DataDomain.records)), 1);
    expect(recordChanges, 1);
    expect(projectChanges, 1);
  });
}
