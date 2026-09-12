import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Color;

import '../labels/label_data.dart';
import 'abi_generated.dart';

part 'labels/blob_decoder.dart';
part 'labels/placement_decoder.dart';
part 'labels/record_decoder.dart';
part 'labels/static_decoder.dart';

const _textPlacedFlag = 1 << 0;
const _iconPlacedFlag = 1 << 1;
const _textAlongLineFlag = 1 << 2;
const _iconAlongLineFlag = 1 << 3;

const _verticalFlag = 1 << 0;
const _iconSdfFlag = 1 << 1;
const _textPitchMapFlag = 1 << 2;
const _textRotationMapFlag = 1 << 3;
const _iconPitchMapFlag = 1 << 4;
const _iconRotationMapFlag = 1 << 5;
const _textKeepUprightFlag = 1 << 6;
const _iconKeepUprightFlag = 1 << 7;
const _textRtlFlag = 1 << 8;

const _sectionColorFlag = 1 << 0;
const _sectionImageFlag = 1 << 1;
