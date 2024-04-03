mixin TakeExtensionMixin {
  String takeExtension({required String inputFilePath}) {
    return ".${inputFilePath.split('.').last}".toLowerCase();
  }
}
