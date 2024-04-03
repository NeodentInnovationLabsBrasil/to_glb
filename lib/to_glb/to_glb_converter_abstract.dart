abstract class ToGlbConverterAbstractClass {
  ToGlbConverterAbstractClass({required this.inputExtension});
  final String inputExtension;

  ///Supported InputFiles to 'inputFilePath' param: ['.ply', '.stl']
  ///Ex: your_document_directory/fileName.plyOrStl.
  ///
  ///For glbOutPutPath param, provide where you want to write file.
  ///
  ///Also returns you the path of file if needed.

  Future<String?> startConvertion(
      {required String inputFilePath, required String glbOutPutPath});
}
