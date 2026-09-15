part of '../map_controls.dart';

/// Builds the default dialog from attribution declared by the active style.
///
/// Source attribution links call the configured handler when one is available.
Widget buildDefaultAttributionDialog(BuildContext context) =>
    _DefaultAttributionDialog(
      controller: _AttributionControllerScope.maybeControllerOf(context),
      onLinkTap: _AttributionControllerScope.maybeOnLinkTapOf(context),
    );

class const _AttributionControllerScope({
  required final MapLibreMapController? controller,
  required final AttributionLinkCallback? onLinkTap,
  required super.child,
}) extends InheritedWidget {
  static MapLibreMapController? maybeControllerOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AttributionControllerScope>()
          ?.controller;

  static AttributionLinkCallback? maybeOnLinkTapOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AttributionControllerScope>()
          ?.onLinkTap;

  @override
  bool updateShouldNotify(_AttributionControllerScope oldWidget) =>
      controller != oldWidget.controller || onLinkTap != oldWidget.onLinkTap;
}

class const _DefaultAttributionDialog({
  required final MapLibreMapController? controller,
  required final AttributionLinkCallback? onLinkTap,
}) extends StatefulWidget {
  @override
  State<_DefaultAttributionDialog> createState() =>
      _DefaultAttributionDialogState();
}

class _DefaultAttributionDialogState extends State<_DefaultAttributionDialog> {
  late final Future<List<({String label, String? url})>> _attributions =
      _loadAttributions();

  Future<List<({String label, String? url})>> _loadAttributions() async {
    final values = await widget.controller?.getSourceAttributions();

    return values == null ? const [] : parseStyleAttributions(values);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Map attribution'),
    content: FutureBuilder<List<({String label, String? url})>>(
      future: _attributions,
      builder: (context, snapshot) {
        if (snapshot.connectionState != .done) {
          return const SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return const Text('Attribution is unavailable.');
        }
        final entries = snapshot.data ?? const [];
        if (entries.isEmpty) {
          return const Text('No attribution was provided by the active style.');
        }

        return SizedBox(
          width: 360,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final uri = entry.url == null ? null : Uri.tryParse(entry.url!);
              final canOpen =
                  uri != null && uri.hasScheme && widget.onLinkTap != null;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(entry.label),
                subtitle: entry.url == null ? null : SelectableText(entry.url!),
                trailing: canOpen ? const Icon(Icons.open_in_new) : null,
                onTap: canOpen ? () => widget.onLinkTap!(uri) : null,
              );
            },
          ),
        );
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
    ],
  );
}
