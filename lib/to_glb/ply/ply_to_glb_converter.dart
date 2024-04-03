import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:to_glb/to_glb/to_glb_converter_abstract.dart';
import 'package:vector_math/vector_math.dart';

class PlyToGlbConverter extends ToGlbConverterAbstractClass {
  PlyToGlbConverter() : super(inputExtension: ".ply");

  String _generateGltf2Template(
      int outBinBytelength,
      int indicesBytelength,
      int verticesBytelength,
      int colorsBytelength,
      int outNumberIndices,
      int maxIndex,
      int outNumberVertices,
      double minx,
      double miny,
      double minz,
      double maxx,
      double maxy,
      double maxz) {
    return '''
{
  "scenes": [{"nodes": [0]}],
  "nodes": [{"mesh": 0}],
  "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "COLOR_0": 1},"indices": 2}]}],
  "buffers": [{"byteLength": $outBinBytelength}],
  "bufferViews": [
    {"buffer": 0, "byteOffset": 0, "byteLength": $verticesBytelength, "target": 34962},
    {"buffer": 0, "byteOffset": $verticesBytelength, "byteLength": $colorsBytelength, "target": 34962},
    {"buffer": 0, "byteOffset": ${verticesBytelength + colorsBytelength}, "byteLength": $indicesBytelength, "target": 34963}
  ],
  "accessors": [
    {"bufferView": 0, "byteOffset": 0, "componentType": 5126, "count": $outNumberVertices, "type": "VEC3", "min": [$minx, $miny, $minz], "max": [$maxx, $maxy, $maxz]},
    {"bufferView": 1, "byteOffset": 0, "componentType": 5126, "count": $outNumberVertices, "type": "VEC3"},
    {"bufferView": 2, "byteOffset": 0, "componentType": 5125, "count": $outNumberIndices, "type": "SCALAR", "max": [$maxIndex], "min": [0]}
  ],
  "asset": {"version": "2.0"}
}''';
  }

  ByteBuffer createGlbBuffer(
      String gltf2,
      List<Vector3> vertices,
      List<Vector3> colors,
      List<int> indices,
      int verticesAndColorsBytelength,
      int indicesBytelength,
      int outBinBytelength) {
    ByteData glbOut = ByteData(
        12 + 8 + gltf2.length + 8 + outBinBytelength); // Allocate byte buffer

    // 12-byte header
    glbOut.setUint32(0, 0x46546C67, Endian.little); // magic number for glTF
    glbOut.setUint32(4, 2, Endian.little); // version
    glbOut.setUint32(8, glbOut.lengthInBytes, Endian.little); // total length

    // Chunk 0 (JSON)
    int paddedSceneLen = (gltf2.length + 3) & ~3; // Calculate padded length
    glbOut.setUint32(12, paddedSceneLen,
        Endian.little); // chunk length, padded to nearest multiple of 4
    glbOut.setUint32(16, 0x4E4F534A,
        Endian.little); // magic number for JSON ('JSON' in ASCII)

    List<int> sceneBytes = utf8.encode(gltf2); // Encode JSON as UTF-8
    for (int i = 0; i < sceneBytes.length; i++) {
      glbOut.setUint8(20 + i, sceneBytes[i]); // Write JSON bytes
    }
    int bodyOffset = 20 + paddedSceneLen; // Calculate body offset

    // Padding for JSON chunk
    for (int i = sceneBytes.length; i < paddedSceneLen; i++) {
      glbOut.setUint8(
          20 + i, 0x20); // Fill with space character to pad to multiple of 4
    }

    // Chunk 1 (BIN)
    glbOut.setUint32(
        bodyOffset, outBinBytelength, Endian.little); // chunk length
    glbOut.setUint32(
        bodyOffset + 4, 0x004E4942, Endian.little); // magic number for BIN
    int binStart = bodyOffset + 8; // Calculate bin start offset

    // Write vertices and colors
    for (int i = 0; i < vertices.length; i++) {
      Vector3 vertex = vertices[i];
      int offset = binStart + i * 12;
      glbOut.setFloat32(offset, vertex.x, Endian.little);
      glbOut.setFloat32(offset + 4, vertex.y, Endian.little);
      glbOut.setFloat32(offset + 8, vertex.z, Endian.little);
    }
    for (int i = 0; i < colors.length; i++) {
      Vector3 color = colors[i];
      int offset = binStart + verticesAndColorsBytelength + i * 12;
      glbOut.setFloat32(offset, color.x, Endian.little);
      glbOut.setFloat32(offset + 4, color.y, Endian.little);
      glbOut.setFloat32(offset + 8, color.z, Endian.little);
    }

    // Write indices
    for (int i = 0; i < indices.length; i++) {
      glbOut.setUint32(binStart + verticesAndColorsBytelength + i * 4,
          indices[i], Endian.little);
    }

    return glbOut.buffer;
  }

  @override
  Future<String> startConvertion(
      {required String inputFilePath, required String glbOutPutPath}) async {
    File plyFile = File(inputFilePath);
    Uint8List plyBytes = await plyFile.readAsBytes();

    List<Vector3> vertices = [];
    List<Vector3> colors = [];
    List<int> indices = [];

    // Parse the ply bytes and extract vertices, colors, and indices
    int currentIndex = 0;
    while (currentIndex < plyBytes.length) {
      String line = _readLine(plyBytes, currentIndex);
      currentIndex += line.length + 1; // Move to next line

      // Parse vertices, colors, and indices
      if (line.startsWith('vertex')) {
        List<String> parts = line.split(' ');
        double x = double.parse(parts[1]);
        double y = double.parse(parts[2]);
        double z = double.parse(parts[3]);
        vertices.add(Vector3(x, y, z));

        // Extract colors, if available
        if (parts.length >= 7) {
          // If there are color information
          double r = double.parse(parts[4]) / 255.0; // Normalized RGB values
          double g = double.parse(parts[5]) / 255.0;
          double b = double.parse(parts[6]) / 255.0;
          colors.add(Vector3(r, g, b));
        }
      } else if (line.startsWith('face')) {
        List<String> parts = line.split(' ');
        int idx1 = int.parse(parts[1]);
        int idx2 = int.parse(parts[2]);
        int idx3 = int.parse(parts[3]);
        indices.addAll([idx1, idx2, idx3]);
      }
    }

    double minx = double.infinity,
        maxx = double.negativeInfinity,
        miny = double.infinity,
        maxy = double.negativeInfinity,
        minz = double.infinity,
        maxz = double.negativeInfinity;

    for (Vector3 vertex in vertices) {
      double x = vertex.x;
      double y = vertex.y;
      double z = vertex.z;

      if (x < minx) minx = x;
      if (x > maxx) maxx = x;
      if (y < miny) miny = y;
      if (y > maxy) maxy = y;
      if (z < minz) minz = z;
      if (z > maxz) maxz = z;
    }

    int numberVertices = vertices.length;
    int verticesBytelength = numberVertices * 12; // 3 floats per vertex
    int colorsBytelength = colors.length * 12; // 3 floats per color
    int indicesBytelength = indices.length * 4; // 1 uint per index
    int verticesAndColorsBytelength = verticesBytelength + colorsBytelength;
    int outBinBytelength = verticesAndColorsBytelength + indicesBytelength;

    String gltf2 = _generateGltf2Template(
        outBinBytelength,
        indicesBytelength,
        verticesBytelength,
        colorsBytelength,
        indices.length,
        numberVertices - 1,
        numberVertices,
        minx,
        miny,
        minz,
        maxx,
        maxy,
        maxz);

    ByteBuffer glbOut = createGlbBuffer(
        gltf2,
        vertices,
        colors,
        indices,
        verticesBytelength + colorsBytelength,
        indicesBytelength,
        outBinBytelength);

    File(glbOutPutPath)
        .writeAsBytesSync(glbOut.asUint8List(0, outBinBytelength));
    return glbOutPutPath;
  }

  String _readLine(Uint8List bytes, int currentIndex) {
    StringBuffer buffer = StringBuffer();
    int byte;
    while ((byte = bytes[currentIndex]) != 10) {
      buffer.writeCharCode(byte);
      currentIndex++;
      if (currentIndex >= bytes.length) break; // Prevent index out of bounds
    }
    return buffer.toString();
  }
}
