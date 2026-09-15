part of '../renderer.dart';

typedef _FrameDrawResult = ({int drawCount, int renderPassCount});

/// Owns pass recording and attachments shared by every stratum in one replay.
final class _GpuFrameReplay {
  _GpuFrameReplay(gpu.ShaderLibrary shaders) {
    _passes.initialize(shaders);
  }

  final _passes = FramePassExecutor();
  gpu.Texture? _mainDepthStencilTexture;
  var _mainDepthStencilWidth = 0;
  var _mainDepthStencilHeight = 0;
  var _sharedDepthStencilInitialized = false;
  final List<RenderPassPlan> _renderPassPlans = [];
  final List<RenderPassPlan> _renderPassPlanPool = [];

  /// Whether the backend has rejected depth and stencil attachments.
  ///
  /// Once rejected, later frames use the fallback without attempting another
  /// attachment.
  static var _depthStencilUnsupported = false;

  /// Selects the process-wide fallback after the backend rejects a render pass
  /// that uses the prepared depth and stencil texture.
  void disableDepthStencil(Object error) {
    _depthStencilUnsupported = true;
    _mainDepthStencilTexture = null;
    _mainDepthStencilWidth = 0;
    _mainDepthStencilHeight = 0;
    _sharedDepthStencilInitialized = false;
    debugPrint(
      '[GpuRenderer] depth/stencil attachment unavailable, '
      'falling back to unclipped depth-less rendering: $error',
    );
  }

  /// Returns the shared depth/stencil texture attached to the frame's first
  /// render pass.
  ///
  /// Attaching it from the first pass keeps the framebuffer complete on
  /// backends that reuse one framebuffer for the color texture.
  gpu.Texture? prepareDepthStencilTexture(gpu.Texture colorTexture) {
    if (_depthStencilUnsupported) return null;
    final cached = _mainDepthStencilTexture;
    if (cached != null &&
        _mainDepthStencilWidth == colorTexture.width &&
        _mainDepthStencilHeight == colorTexture.height) {
      return cached;
    }
    try {
      final depth = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        colorTexture.width,
        colorTexture.height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        enableRenderTargetUsage: true,
      );
      _mainDepthStencilTexture = depth;
      _mainDepthStencilWidth = colorTexture.width;
      _mainDepthStencilHeight = colorTexture.height;
      _sharedDepthStencilInitialized = false;

      return depth;
    } catch (e) {
      disableDepthStencil(e);

      return null;
    }
  }

  /// Creates an overlay pass with the same attachment semantics as map passes.
  gpu.RenderPass createOverlayRenderPass(
    gpu.CommandBuffer commandBuffer,
    gpu.RenderTarget target,
  ) => _passes.createRenderPass(
    commandBuffer,
    target,
    hasDepthStencilAttachment: target.depthStencilAttachment != null,
  );

  int render({
    required int frameSequence,
    required GpuPreparedFrame preparedFrame,
    required int stratumIndex,
    required gpu.CommandBuffer commandBuffer,
    required gpu.Texture texture,
    required vector_math.Vector4 frameClearColor,
    required bool submitEachRenderPass,
    gpu.Texture? initialDepthStencilTexture,
    MapLibreGpuRenderCallback? gpuMapRenderCallback,
    MapLibreGpuMapTransform? mapTransform,
  }) {
    if (stratumIndex < 0 || stratumIndex >= preparedFrame.layerRanges.length) {
      throw RangeError.index(
        stratumIndex,
        preparedFrame.layerRanges,
        'stratumIndex',
      );
    }
    final partition = preparedFrame._graphState.graph.partitions[stratumIndex];
    final range = partition.range;
    final effectiveMapCallback =
        gpuMapRenderCallback != null &&
            threeDimensionalCallbackInLayerRange(
              preparedFrame.lastFillExtrusionLayerIndex,
              minimumLayerIndex: range.minimumLayerIndex,
              maximumLayerIndex: range.maximumLayerIndex,
            )
        ? gpuMapRenderCallback
        : null;
    final key = preparedFrame._key;
    final entries = partition.entries;
    if (entries.isEmpty) {
      final clearDepthStencil =
          initialDepthStencilTexture != null && !_sharedDepthStencilInitialized;
      _recordCustomMapPass(
        commandBuffer,
        texture,
        initialDepthStencilTexture,
        frameClearColor: frameClearColor,
        clearColor: true,
        clearDepthStencil: clearDepthStencil,
        frameSequence: frameSequence,
        callback: effectiveMapCallback,
        logicalWidth: key.logicalWidth,
        logicalHeight: key.logicalHeight,
        devicePixelRatio: key.devicePixelRatio,
        mapTransform: mapTransform,
      );
      if (effectiveMapCallback == null) {
        _passes.clearFramePass(
          commandBuffer,
          texture,
          frameClearColor,
          depthStencilTexture: initialDepthStencilTexture,
          clearDepthStencil: clearDepthStencil,
        );
      }
      if (initialDepthStencilTexture != null) {
        _sharedDepthStencilInitialized = true;
      }
      if (submitEachRenderPass) commandBuffer.submit();

      return 0;
    }
    final drawResult = _recordTexturePasses(
      commandBuffer,
      texture,
      preparedFrame.binder!,
      frameSequence: frameSequence,
      entries: entries,
      submitEachRenderPass: submitEachRenderPass,
      frameClearColor: frameClearColor,
      uniformData: preparedFrame.uniformData,
      initialDepthStencilTexture: initialDepthStencilTexture,
      needsMainDepthStencil: partition.needsMainDepthStencil,
      customMapCallback: effectiveMapCallback,
      logicalWidth: key.logicalWidth,
      logicalHeight: key.logicalHeight,
      devicePixelRatio: key.devicePixelRatio,
      mapTransform: mapTransform,
    );
    preparedFrame.drawCount += drawResult.drawCount;
    preparedFrame.renderPassCount += drawResult.renderPassCount;

    return drawResult.drawCount;
  }

  /// Replays the frame onto [texture] in logical render passes.
  ///
  /// Adjacent pipeline runs keep MapLibre's emission order, but compatible runs
  /// share a logical pass. Stencil clears, custom callbacks, and depth-write
  /// changes remain logical pass barriers. Android records these passes inside
  /// one native render pass.
  _FrameDrawResult _recordTexturePasses(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture texture,
    FrameBinder binder, {
    required int frameSequence,
    required List<DrawEntry> entries,
    required bool submitEachRenderPass,
    required vector_math.Vector4 frameClearColor,
    required ByteData uniformData,
    required gpu.Texture? initialDepthStencilTexture,
    required bool needsMainDepthStencil,
    required MapLibreGpuRenderCallback? customMapCallback,
    required double? logicalWidth,
    required double? logicalHeight,
    required double devicePixelRatio,
    required MapLibreGpuMapTransform? mapTransform,
  }) {
    var drawCount = 0;
    var renderPassCount = 0;

    // Keep the combined attachment even when a run does not use depth or
    // stencil. Android shares one framebuffer across the surface's passes.
    final mainDepthStencilTexture =
        initialDepthStencilTexture ??
        (needsMainDepthStencil || customMapCallback != null
            ? prepareDepthStencilTexture(texture)
            : null);

    var colorInitialized = false;
    var attachmentInitialized = _sharedDepthStencilInitialized;
    var currentCommandBuffer = commandBuffer;
    var hasRecordedPass = false;
    gpu.RenderPass? activePass;
    bool? activeDepthWrite;
    gpu.CommandBuffer nextPassCommandBuffer() {
      if (submitEachRenderPass && hasRecordedPass) {
        currentCommandBuffer.submit();
        currentCommandBuffer = gpu.gpuContext.createCommandBuffer();
      }
      hasRecordedPass = true;

      return currentCommandBuffer;
    }

    final passPlans = planRenderPasses(
      entries,
      hasDepthStencilAttachment: mainDepthStencilTexture != null,
      attachmentInitiallyInitialized: attachmentInitialized,
      output: _renderPassPlans,
      pool: _renderPassPlanPool,
    );
    final customMapInsertionIndex = threeDimensionalRenderInsertionIndex(
      passPlans,
      entries,
    );
    for (var planIndex = 0; planIndex < passPlans.length; planIndex++) {
      final plan = passPlans[planIndex];
      final first = entries[plan.start];
      if (plan.kind == .stencilClear) {
        activePass = null;
        activeDepthWrite = null;
        if (mainDepthStencilTexture != null) {
          _passes.clearStencilPass(
            nextPassCommandBuffer(),
            texture,
            frameClearColor,
            mainDepthStencilTexture,
            clearColor: !colorInitialized,
            attachmentInitialized: !plan.clearDepth,
            clearValue: first.stencilReference,
          );
          renderPassCount++;
          colorInitialized = true;
          attachmentInitialized = true;
        }
      } else {
        final isDepthPrepass = plan.kind == .fillExtrusionDepth;
        final pipeline = isDepthPrepass
            ? binder.depthPipelineFor(first)
            : binder.pipelineFor(first);
        if (activePass == null || activeDepthWrite != plan.depthWrite) {
          final initializeDepthStencil =
              mainDepthStencilTexture != null && !attachmentInitialized;
          activePass = _passes.beginOverlayPass(
            nextPassCommandBuffer(),
            texture,
            frameClearColor,
            clearColor: !colorInitialized,
            depthStencilTexture: mainDepthStencilTexture,
            clearDepth: initializeDepthStencil,
            clearStencil: initializeDepthStencil,
            depthWrite: plan.depthWrite,
          );
          activeDepthWrite = plan.depthWrite;
          renderPassCount++;
          colorInitialized = true;
          if (mainDepthStencilTexture != null) attachmentInitialized = true;
        }
        drawCount += _passes.drawRun(
          activePass,
          pipeline,
          entries,
          plan.start,
          plan.end,
          binder,
          hasDepthStencilAttachment: mainDepthStencilTexture != null,
          propsAreRunConstant: _runHasConstantProps(
            entries,
            plan.start,
            plan.end,
            uniformData,
          ),
          setPrimitive: plan.setPrimitive,
          depthTest: plan.depthTest,
          stencilMode: plan.stencilMode,
          cullBackFaces: plan.cullBackFaces,
        );
      }
      if (planIndex + 1 == customMapInsertionIndex &&
          customMapCallback != null) {
        _recordCustomMapPass(
          nextPassCommandBuffer(),
          texture,
          mainDepthStencilTexture,
          frameClearColor: frameClearColor,
          clearColor: !colorInitialized,
          clearDepthStencil:
              mainDepthStencilTexture != null && !attachmentInitialized,
          frameSequence: frameSequence,
          callback: customMapCallback,
          logicalWidth: logicalWidth,
          logicalHeight: logicalHeight,
          devicePixelRatio: devicePixelRatio,
          mapTransform: mapTransform,
        );
        renderPassCount++;
        colorInitialized = true;
        if (mainDepthStencilTexture != null) attachmentInitialized = true;
        activePass = null;
        activeDepthWrite = null;
      }
    }
    if (passPlans.isEmpty && customMapCallback != null) {
      _recordCustomMapPass(
        nextPassCommandBuffer(),
        texture,
        mainDepthStencilTexture,
        frameClearColor: frameClearColor,
        clearColor: true,
        clearDepthStencil: mainDepthStencilTexture != null,
        frameSequence: frameSequence,
        callback: customMapCallback,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
        devicePixelRatio: devicePixelRatio,
        mapTransform: mapTransform,
      );
      renderPassCount++;
      colorInitialized = true;
      if (mainDepthStencilTexture != null) attachmentInitialized = true;
    }
    if (!colorInitialized) {
      _passes.clearFramePass(
        nextPassCommandBuffer(),
        texture,
        frameClearColor,
        depthStencilTexture: mainDepthStencilTexture,
        clearDepthStencil:
            mainDepthStencilTexture != null && !attachmentInitialized,
      );
      renderPassCount++;
      if (mainDepthStencilTexture != null) attachmentInitialized = true;
    }
    if (submitEachRenderPass && hasRecordedPass) currentCommandBuffer.submit();
    if (mainDepthStencilTexture != null && attachmentInitialized) {
      _sharedDepthStencilInitialized = true;
    }
    return (drawCount: drawCount, renderPassCount: renderPassCount);
  }

  static bool _runHasConstantProps(
    List<DrawEntry> entries,
    int start,
    int end,
    ByteData uniformData,
  ) {
    if (end - start < 2) return true;
    final first = entries[start];
    final length = first.propsUniformLength;
    if (length == 0) return true;
    final firstOffset = first.propsUniformOffset;
    for (var index = start + 1; index < end; index++) {
      final entry = entries[index];
      if (entry.propsUniformLength != length) return false;
      final offset = entry.propsUniformOffset;
      var byte = 0;
      for (; byte + 8 <= length; byte += 8) {
        if (uniformData.getUint64(firstOffset + byte) !=
            uniformData.getUint64(offset + byte)) {
          return false;
        }
      }
      for (; byte < length; byte++) {
        if (uniformData.getUint8(firstOffset + byte) !=
            uniformData.getUint8(offset + byte)) {
          return false;
        }
      }
    }
    return true;
  }

  void _recordCustomMapPass(
    gpu.CommandBuffer commandBuffer,
    gpu.Texture texture,
    gpu.Texture? depthStencilTexture, {
    required vector_math.Vector4 frameClearColor,
    required bool clearColor,
    required bool clearDepthStencil,
    required int frameSequence,
    required MapLibreGpuRenderCallback? callback,
    required double? logicalWidth,
    required double? logicalHeight,
    required double devicePixelRatio,
    required MapLibreGpuMapTransform? mapTransform,
  }) {
    if (callback == null) return;
    final renderTarget = _passes.renderTarget(
      texture,
      frameClearColor,
      clearColor: clearColor,
      depthStencilTexture: depthStencilTexture,
      clearDepth: clearDepthStencil,
      clearStencil: clearDepthStencil,
    );
    final renderPass = _passes.createRenderPass(
      commandBuffer,
      renderTarget,
      hasDepthStencilAttachment: depthStencilTexture != null,
    );
    try {
      callback(
        .new(
          gpuContext: gpu.gpuContext,
          renderPass: renderPass,
          logicalSize: Size(
            logicalWidth ?? texture.width / devicePixelRatio,
            logicalHeight ?? texture.height / devicePixelRatio,
          ),
          physicalSize: Size(
            texture.width.toDouble(),
            texture.height.toDouble(),
          ),
          devicePixelRatio: devicePixelRatio,
          frameSequence: frameSequence,
          mapTransform: mapTransform,
          hasDepthStencilAttachment: depthStencilTexture != null,
          depthMode: .shared,
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[GpuRenderer] gpuMapRenderCallback error: $error\n$stackTrace',
      );
    }
  }

  void beginFrame() {
    _passes.beginFrame();
    _sharedDepthStencilInitialized = false;
  }

  void dispose() {
    _mainDepthStencilTexture = null;
    _mainDepthStencilWidth = 0;
    _mainDepthStencilHeight = 0;
    _sharedDepthStencilInitialized = false;
    _renderPassPlans.clear();
    _renderPassPlanPool.clear();
    _passes.releaseResources();
  }
}
