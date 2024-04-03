import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:to_glb/to_glb/to_glb_converter_abstract.dart';
import 'package:vector_math/vector_math.dart';

class StlToGlbConverter extends ToGlbConverterAbstractClass {
  StlToGlbConverter() : super(inputExtension: ".stl");

  String _generateGltf2Template(
      int outBinBytelength,
      int indicesBytelength,
      int verticesBytelength,
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
  "meshes": [{"primitives": [{"attributes": {"POSITION": 1},"indices": 0}]}],
  "buffers": [{"byteLength": $outBinBytelength}],
  "bufferViews": [
    {"buffer": 0, "byteOffset": 0, "byteLength": $indicesBytelength, "target": 34963},
    {"buffer": 0, "byteOffset": $indicesBytelength, "byteLength": $verticesBytelength, "target": 34962}
  ],
  "accessors": [
    {"bufferView": 0, "byteOffset": 0, "componentType": 5125, "count": $outNumberIndices, "type": "SCALAR", "max": [$maxIndex], "min": [0]},
    {"bufferView": 1, "byteOffset": 0, "componentType": 5126, "count": $outNumberVertices, "type": "VEC3", "min": [$minx, $miny, $minz], "max": [$maxx, $maxy, $maxz]}
  ],
  "asset": {"version": "2.0"}
}''';
  }

  ByteBuffer createGlbBuffer(
      String gltf2,
      List<int> indices,
      Map<Vector3, int> vertices,
      int indicesBytelength,
      int unpaddedIndicesBytelength,
      int outBinBytelength) {
    ByteData glbOut = ByteData(12 + 8 + gltf2.length + 8 + outBinBytelength);

    // 12-byte header
    glbOut.setUint32(0, 0x46546C67, Endian.little); // magic number for glTF
    glbOut.setUint32(4, 2, Endian.little); // version
    glbOut.setUint32(8, glbOut.lengthInBytes, Endian.little); // total length

    // Chunk 0 (JSON)
    int paddedSceneLen = (gltf2.length + 3) & ~3;
    glbOut.setUint32(12, paddedSceneLen, Endian.little); // chunk length
    glbOut.setUint32(16, 0x4E4F534A, Endian.little); // magic number for JSON

    List<int> sceneBytes = utf8.encode(gltf2);
    for (int i = 0; i < sceneBytes.length; i++) {
      glbOut.setUint8(20 + i, sceneBytes[i]);
    }
    int bodyOffset = 20 + paddedSceneLen;

    // Padding for JSON chunk
    for (int i = sceneBytes.length; i < paddedSceneLen; i++) {
      glbOut.setUint8(20 + i, 0x20); // space character
    }

    // Chunk 1 (BIN)
    glbOut.setUint32(
        bodyOffset, outBinBytelength, Endian.little); // chunk length
    glbOut.setUint32(
        bodyOffset + 4, 0x004E4942, Endian.little); // magic number for BIN
    int binStart = bodyOffset + 8;

    // Write indices
    for (int i = 0; i < indices.length; i++) {
      glbOut.setUint32(binStart + i * 4, indices[i], Endian.little);
    }

    // Padding for indices
    for (int i = indices.length * 4; i < indicesBytelength; i++) {
      glbOut.setUint8(binStart + i, 0);
    }

    // Write vertices
    List<Vector3> sortedVertices =
        List.generate(vertices.length, (i) => Vector3.zero());
    vertices.forEach((vertex, index) {
      sortedVertices[index] = vertex;
    });

    for (int i = 0; i < sortedVertices.length; i++) {
      Vector3 vertex = sortedVertices[i];
      int offset = binStart + indicesBytelength + i * 12;
      glbOut.setFloat32(offset, vertex.x, Endian.little);
      glbOut.setFloat32(offset + 4, vertex.y, Endian.little);
      glbOut.setFloat32(offset + 8, vertex.z, Endian.little);
    }

    return glbOut.buffer;
  }

  @override
  Future<String> startConvertion(
      {required String inputFilePath, required String glbOutPutPath}) async {
    File stlFile = File(inputFilePath);
    RandomAccessFile stlRaf = stlFile.openSync();
    int headerBytes = 80;
    int unsignedLongIntBytes = 4;
    int floatBytes = 4;
    int vec3Bytes = 4 * 3;
    int spacerBytes = 2;
    int numVerticesInFace = 3;

    Map<Vector3, int> vertices = {};
    List<int> indices = [];

    stlRaf.setPositionSync(headerBytes); // skip 80 bytes header

    int numberFaces = stlRaf
        .readSync(unsignedLongIntBytes)
        .buffer
        .asByteData()
        .getUint32(0, Endian.little);

    int stlAssumeBytes = headerBytes +
        unsignedLongIntBytes +
        numberFaces * (vec3Bytes * 3 + spacerBytes + vec3Bytes);
    assert(stlAssumeBytes == stlFile.lengthSync(),
        "STL is not binary or ill-formatted");

    double minx = double.infinity,
        maxx = double.negativeInfinity,
        miny = double.infinity,
        maxy = double.negativeInfinity,
        minz = double.infinity,
        maxz = double.negativeInfinity;

    int verticesLengthCounter = 0;

    for (int i = 0; i < numberFaces; i++) {
      Float32List faceData =
          stlRaf.readSync(floatBytes * 12).buffer.asFloat32List();
      for (int j = 3; j < 12; j += 3) {
        double x = faceData[j];
        double y = faceData[j + 1];
        double z = faceData[j + 2];

        x = (x * 100000).round() / 100000;
        y = (y * 100000).round() / 100000;
        z = (z * 100000).round() / 100000;

        Vector3 xyz = Vector3(x, y, z);

        if (!vertices.containsKey(xyz)) {
          vertices[xyz] = verticesLengthCounter++;
        }
        indices.add(vertices[xyz]!);

        if (x < minx) minx = x;
        if (x > maxx) maxx = x;
        if (y < miny) miny = y;
        if (y > maxy) maxy = y;
        if (z < minz) minz = z;
        if (z > maxz) maxz = z;
      }

      stlRaf.setPositionSync(
          stlRaf.positionSync() + spacerBytes); // skip the spacer
    }

    stlRaf.closeSync();

    int numberVertices = vertices.length;
    int verticesBytelength = numberVertices *
        vec3Bytes; // each vec3 has 3 floats, each float is 4 bytes
    int unpaddedIndicesBytelength = indices.length * unsignedLongIntBytes;

    int indicesBytelength = (unpaddedIndicesBytelength + 3) & ~3;
    int outBinBytelength = verticesBytelength + indicesBytelength;

    String gltf2 = _generateGltf2Template(
        outBinBytelength,
        indicesBytelength,
        verticesBytelength,
        indices.length,
        numberVertices - 1,
        numberVertices,
        minx,
        miny,
        minz,
        maxx,
        maxy,
        maxz);

    ByteBuffer glbOut = createGlbBuffer(gltf2, indices, vertices,
        indicesBytelength, unpaddedIndicesBytelength, outBinBytelength);

    File(glbOutPutPath).writeAsBytesSync(glbOut.asUint8List());
    // print("Done! Exported to $glbOutPutPath");
    // MainModule.to.navigator.pushNamed(StlPageViewerPage.routeName,
    //     arguments: {"filePath": File(glbOutPutPath).path});
    return glbOutPutPath;
  }
}
