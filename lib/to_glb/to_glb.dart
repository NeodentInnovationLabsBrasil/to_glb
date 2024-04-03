import 'package:to_glb/take_extension.mixin.dart';
import 'package:to_glb/to_glb/ply/ply_to_glb_converter.dart';
import 'package:to_glb/to_glb/stl/stl_to_glb_converter.dart';

class ToGlb with TakeExtensionMixin {
  Future<String> startConvertion(
      {required String inputFilePath, required String glbOutPutPath}) async {
    String fileExtension = takeExtension(inputFilePath: inputFilePath);
    if (fileExtension.contains("stl")) {
      return await StlToGlbConverter().startConvertion(
          inputFilePath: inputFilePath, glbOutPutPath: glbOutPutPath);
    } else if (fileExtension.contains("ply")) {
      return await PlyToGlbConverter().startConvertion(
          inputFilePath: inputFilePath, glbOutPutPath: glbOutPutPath);
    } else {
      throw Exception("Cant convert $fileExtension");
    }
  }
}
