/// A compiled WebAssembly module, bound to [id] inside the owning
/// engine/adapter until unloaded.
class InappwebviewModule {
  final String id;
  final int byteLength;

  const InappwebviewModule({required this.id, required this.byteLength});
}
