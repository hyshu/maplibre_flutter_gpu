import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu/render_pass_recorder.dart';
import 'package:maplibre_flutter_gpu/src/gpu/shaders.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('logical passes preserve color, depth, and stencil on Android', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox.shrink());
    final shaders = await loadMapShaderLibrary();
    final recorder = SingleRenderPassRecorder(shaders);
    addTearDown(recorder.dispose);
    final context = gpu.gpuContext;
    final texture = context.createTexture(
      .devicePrivate,
      16,
      16,
      format: .r8g8b8a8UNormInt,
      enableRenderTargetUsage: true,
      enableShaderReadUsage: true,
    );
    final color = gpu.ColorAttachment(texture: texture);
    final depth = gpu.DepthStencilAttachment(
      texture: context.createTexture(
        .devicePrivate,
        16,
        16,
        format: context.defaultDepthStencilFormat,
        enableRenderTargetUsage: true,
      ),
      depthClearValue: 1,
      depthStoreAction: .store,
      stencilStoreAction: .store,
    );
    final target = gpu.RenderTarget(
      colorAttachments: [color],
      depthStencilAttachment: depth,
    );
    final fragment = shaders['AttachmentClearFragment']!;
    final pipeline = context.createRenderPipeline(
      shaders['AttachmentClearVertex']!,
      fragment,
    );
    final slot = fragment.getUniformSlot('ClearColor');
    final uniforms = context.createHostBuffer();

    void draw(
      gpu.RenderPass pass,
      List<double> rgba, {
      double z = 0.5,
      bool writeDepth = false,
      gpu.CompareFunction depthCompare = .always,
      int? writeStencil,
      int? testStencil,
      int x = 0,
      int width = 16,
    }) {
      final vertices = Float32List.fromList([-1, -1, z, 3, -1, z, -1, 3, z]);
      final buffer = context.createDeviceBufferWithCopy(
        ByteData.sublistView(vertices),
      );
      pass.bindPipeline(pipeline);
      pass.bindVertexBuffer(
        gpu.BufferView(buffer, offsetInBytes: 0, lengthInBytes: 36),
      );
      pass.bindUniform(
        slot,
        uniforms.emplace(ByteData.sublistView(Float32List.fromList(rgba))),
      );
      pass.setDepthCompareOperation(depthCompare);
      pass.setDepthWriteEnable(writeDepth);
      pass.setStencilReference(writeStencil ?? testStencil ?? 0);
      pass.setStencilConfig(
        gpu.StencilConfig(
          compareFunction: testStencil == null ? .always : .equal,
          depthStencilPassOperation: writeStencil == null
              ? .keep
              : .setToReferenceValue,
          readMask: 0xff,
          writeMask: writeStencil == null ? 0 : 0xff,
        ),
      );
      pass.setScissor(gpu.Scissor(x: x, width: width, height: 16));
      pass.draw(3);
    }

    Future<ByteData> submitAndRead(gpu.CommandBuffer commands) async {
      final completed = Completer<bool>();
      commands.submit(completionCallback: completed.complete);
      expect(await completed.future.timeout(const Duration(seconds: 10)), true);
      final image = texture.asImage();
      try {
        return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      } finally {
        image.dispose();
      }
    }

    void expectPixel(ByteData pixels, int x, List<int> rgba) {
      final offset = (8 * 16 + x) * 4;
      expect(
        List.generate(4, (channel) => pixels.getUint8(offset + channel)),
        rgba,
        reason: 'pixel at ($x, 8)',
      );
    }

    recorder.beginFrame();
    var commands = context.createCommandBuffer();
    var pass = recorder.createRenderPass(commands, target);
    draw(pass, [1, 0, 0, 1], z: 0.25, writeDepth: true, writeStencil: 5);

    color.loadAction = .load;
    depth
      ..depthLoadAction = .load
      ..stencilClearValue = 7;
    pass = recorder.createRenderPass(commands, target);
    // A stencil clear must preserve both red color and the nearer depth.
    draw(pass, [0, 0, 1, 1], depthCompare: .less);

    depth.stencilLoadAction = .load;
    pass = recorder.createRenderPass(commands, target);
    draw(pass, [0, 1, 0, 1], testStencil: 7, x: 4, width: 4);

    // A depth clear must cover pixels outside the previous draw's scissor.
    depth.depthLoadAction = .clear;
    pass = recorder.createRenderPass(commands, target);
    draw(
      pass,
      [0, 0, 1, 1],
      depthCompare: .less,
      testStencil: 7,
      x: 8,
      width: 4,
    );
    var pixels = await submitAndRead(commands);
    expectPixel(pixels, 2, [255, 0, 0, 255]);
    expectPixel(pixels, 6, [0, 255, 0, 255]);
    expectPixel(pixels, 10, [0, 0, 255, 255]);
    expectPixel(pixels, 14, [255, 0, 0, 255]);

    // Reusing the framebuffer must still apply this frame's clear values.
    recorder.beginFrame();
    commands = context.createCommandBuffer();
    color.loadAction = .clear;
    color.clearValue.setValues(1, 1, 0, 1);
    depth
      ..depthLoadAction = .clear
      ..depthClearValue = 0.25
      ..stencilLoadAction = .clear
      ..stencilClearValue = 5;
    recorder.createRenderPass(commands, target);
    pixels = await submitAndRead(commands);
    expectPixel(pixels, 2, [255, 255, 0, 255]);
    expectPixel(pixels, 14, [255, 255, 0, 255]);

    recorder.beginFrame();
    commands = context.createCommandBuffer();
    recorder.createRenderPass(commands, target);
    color.clearValue.setValues(0, 1, 1, 1);
    depth
      ..depthLoadAction = .load
      ..stencilLoadAction = .load;
    pass = recorder.createRenderPass(commands, target);
    // A color clear must preserve the nearer depth and stencil reference.
    draw(pass, [0, 0, 1, 1], depthCompare: .less);
    draw(pass, [0, 1, 0, 1], testStencil: 5, width: 4);
    pixels = await submitAndRead(commands);
    expectPixel(pixels, 2, [0, 255, 0, 255]);
    expectPixel(pixels, 14, [0, 255, 255, 255]);
  }, skip: defaultTargetPlatform != TargetPlatform.android);
}
