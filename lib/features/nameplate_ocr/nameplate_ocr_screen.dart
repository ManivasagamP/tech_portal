import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/ocr/nameplate_reader.dart';
import '../../theme/fe_colors.dart';
import '../../widgets/app_text.dart';
import '../../widgets/fe_header.dart';

/// FR-1.5 — point at the nameplate, get manufacturer/model/serial pre-filled
/// as **editable** fields. Nothing here is ever submitted on its own: OCR
/// fills the boxes, the technician confirms or corrects them. A machine
/// reading the same plate the register was built from proves nothing about
/// whether the physical asset actually matches — only the technician's own
/// look at the thing does.
class NameplateOcrScreen extends StatefulWidget {
  const NameplateOcrScreen({super.key});

  @override
  State<NameplateOcrScreen> createState() => _NameplateOcrScreenState();
}

class _NameplateOcrScreenState extends State<NameplateOcrScreen> {
  final _reader = NameplateReader();
  final _manufacturer = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();

  File? _photo;
  var _processing = false;
  var _recognizedNothing = false;

  @override
  void dispose() {
    _reader.dispose();
    _manufacturer.dispose();
    _model.dispose();
    _serial.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (shot == null) return;

    setState(() {
      _photo = File(shot.path);
      _processing = true;
      _recognizedNothing = false;
    });

    try {
      final fields = await _reader.read(shot.path);
      if (!mounted) return;
      setState(() {
        _manufacturer.text = fields.manufacturer ?? '';
        _model.text = fields.model ?? '';
        _serial.text = fields.serial ?? '';
        _recognizedNothing = fields.isEmpty;
        _processing = false;
      });
    } catch (_) {
      // A failed recognizer is not a dead end — the fields are still there
      // for the technician to fill in by hand.
      if (mounted) {
        setState(() {
          _recognizedNothing = true;
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;

    return Scaffold(
      backgroundColor: FeColors.page,
      appBar: FeHeader(
        showBack: true,
        title: 'nameplate.title'.getString(context),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (photo == null)
              _CapturePrompt(onCapture: _capture)
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(photo, height: 200, width: double.infinity, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _processing ? null : _capture,
                icon: const Icon(LucideIcons.rotateCcw, size: 16),
                label: AppText('nameplate.retake'.getString(context)),
              ),
              const SizedBox(height: 20),
              if (_processing)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_recognizedNothing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppText.caption(
                      'nameplate.nothing_recognized'.getString(context),
                      color: FeColors.warning,
                    ),
                  ),
                AppText.caption(
                  'nameplate.confirm_hint'.getString(context),
                  color: FeColors.ink2,
                ),
                const SizedBox(height: 12),
                _Field(
                  label: 'nameplate.manufacturer'.getString(context),
                  controller: _manufacturer,
                ),
                const SizedBox(height: 12),
                _Field(label: 'nameplate.model'.getString(context), controller: _model),
                const SizedBox(height: 12),
                _Field(label: 'nameplate.serial'.getString(context), controller: _serial),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _CapturePrompt extends StatelessWidget {
  const _CapturePrompt({required this.onCapture});

  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 40),
      Icon(LucideIcons.scanLine, size: 48, color: FeColors.ink2),
      const SizedBox(height: 16),
      AppText(
        'nameplate.prompt'.getString(context),
        align: TextAlign.center,
        style: TextStyle(color: FeColors.ink2),
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 52,
        child: FilledButton.icon(
          onPressed: onCapture,
          style: FilledButton.styleFrom(backgroundColor: FeColors.primary),
          icon: const Icon(LucideIcons.camera, size: 18),
          label: AppText('nameplate.capture'.getString(context)),
        ),
      ),
    ],
  );
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller});

  final String label;
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
    ),
  );
}
