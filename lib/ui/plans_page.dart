import 'package:flutter/material.dart';

import '../core/content.dart';
import '../core/reference.dart';
import 'common.dart';
import 'theme.dart';

class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reading plans')),
      body: ListenableBuilder(
        listenable: Listenable.merge([services.store, services.settings]),
        builder: (context, _) {
          final active = services.settings.activePlans;
          return ReadableWidth(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: ReadingPlan.all.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text('Progress is kept on this device. Read at your own pace — each plan picks up where you left off.',
                      style: TextStyle(color: context.muted, height: 1.45));
                }
                final p = ReadingPlan.all[i - 1];
                final on = active.contains(p.id);
                return Card(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlanDetailPage(plan: p))),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(p.title, style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                          if (on)
                            Chip(
                              label: const Text('Active'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: context.colors.primaryContainer,
                            ),
                        ]),
                        const SizedBox(height: 4),
                        Text(p.description, style: TextStyle(color: context.muted)),
                        const SizedBox(height: 10),
                        FutureBuilder<Set<int>>(
                          future: services.store.planDaysDone(p.id),
                          builder: (context, snap) {
                            final done = snap.data?.length ?? 0;
                            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(value: done / p.days, minHeight: 6),
                              ),
                              const SizedBox(height: 6),
                              Text('$done of ${p.days} days', style: context.text.labelSmall?.copyWith(color: context.muted)),
                            ]);
                          },
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class PlanDetailPage extends StatelessWidget {
  final ReadingPlan plan;
  const PlanDetailPage({super.key, required this.plan});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([services.store, services.settings]),
      builder: (context, _) {
        final active = services.settings.activePlans.contains(plan.id);
        return Scaffold(
          appBar: AppBar(
            title: Text(plan.title),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (v) async {
                  if (v == 'reset') {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Reset progress?'),
                        content: Text('All checked days in “${plan.title}” will be cleared.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
                        ],
                      ),
                    );
                    if (ok == true) await services.store.resetPlan(plan.id);
                  }
                },
                itemBuilder: (_) => [const PopupMenuItem(value: 'reset', child: Text('Reset progress'))],
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              final list = [...services.settings.activePlans];
              active ? list.remove(plan.id) : list.add(plan.id);
              services.settings.activePlans = list;
            },
            icon: Icon(active ? Icons.home_outlined : Icons.add_task),
            label: Text(active ? 'Remove from Home' : 'Show on Home'),
          ),
          body: FutureBuilder<Set<int>>(
            future: services.store.planDaysDone(plan.id),
            builder: (context, snap) {
              final done = snap.data ?? const <int>{};
              return ReadableWidth(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: plan.days,
                  itemBuilder: (context, d) {
                    final chapters = plan.chaptersForDay(d);
                    final isDone = done.contains(d);
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      leading: Checkbox(
                        value: isDone,
                        semanticLabel: 'Day ${d + 1} complete',
                        onChanged: (v) => services.store.setPlanDay(plan.id, d, v ?? false),
                      ),
                      title: Text('Day ${d + 1}', style: TextStyle(fontWeight: FontWeight.w600, color: isDone ? context.muted : null)),
                      subtitle: Text(describeChapters(chapters)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final first = chapters.first;
                        await openReader(context, Reference(first ~/ 1000, first % 1000));
                        if (!isDone && context.mounted) {
                          final mark = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Day ${d + 1}'),
                              content: Text('Mark ${describeChapters(chapters)} as read?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Mark as read')),
                              ],
                            ),
                          );
                          if (mark == true) await services.store.setPlanDay(plan.id, d, true);
                        }
                      },
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }
}
