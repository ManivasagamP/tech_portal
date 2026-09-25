import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:vibration/vibration.dart';

import '../../app/router.dart';
import '../../core/capture/capture_services.dart';
import '../../core/network/api_exception.dart';
import '../../core/snag/snag_rules.dart';
import '../../data/snag_repository.dart';
import '../../domain/snag.dart';
import '../../state/snag_controller.dart';
import '../../theme/fe_colors.dart';
import '../../widgets/app_text.dart';
import '../../widgets/tech_popup.dart';
import '../../widgets/voice_waveform.dart';
import '../field_verification/photo_annotation_screen.dart';
import 'widgets/snag_sheets.dart';
import 'widgets/snag_visuals.dart';

/// UC-1 — walk mode. The camera stays live for the whole walk; a snag is a
/// shutter press, a trade chip and a severity pill, then straight back to the
/// viewfinder. Location is picked once per room and sticks until "Room done".
///
/// Why a live [CameraController] instead of `image_picker`: `image_picker`
/// hands off to the OS camera app and back for every photo — two full
/// screen transitions per snag, which on a 150-snag takeover survey is the
/// difference between a morning and a day. Same reasoning, and the same
/// lifecycle handling, as `camera_capture_screen.dart`.
class SnagWalkScreen extends ConsumerStatefulWidget {
  const SnagWalkScreen({super.key, required this.surveyId});

  final String surveyId;

  @override
  ConsumerState<SnagWalkScreen> createState() => _SnagWalkScreenState();
}

class _SnagWalkScreenState extends ConsumerState<SnagWalkScreen> with WidgetsBindingObserver {
  CameraController? _camera;
  String? _cameraError;
  var _torch = false;
  var _shooting = false;

  SnagSurvey? _survey;
  SnagLocationTree? _tree;
  SnagFloor? _floor;
  SnagSpace? _space;
  var _pickerShown = false;

  // Compose state — non-null [_photo] means the compose card is up.
  CapturedPhoto? _photo;
  String _trade = kSnagTrades.first;
  SnagPriority _priority = SnagPriority.minor;
  String _issueType = 'defect';
  final _title = TextEditingController();
  String? _description;
  VoiceRecording? _voice;
  SnagSuggestion? _suggestion;
  var _assisting = false;
  var _saving = false;

  final _voiceCapture = VoiceCapture();
  var _recording = false;
  Stream<Amplitude>? _amplitude;

  /// Most recent first — the next snag in a room is usually the same trade.
  final _recentTrades = <String>[];
  double? _lat;
  double? _lng;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _load();
    // Evidence geo without blocking the walk on a fresh fix: the last known
    // position is instant and good enough to say which site a photo is from.
    Geolocator.getLastKnownPosition().then((p) {
      _lat = p?.latitude;
      _lng = p?.longitude;
    }).catchError((Object _) => null);
  }

  Future<void> _load() async {
    final repo = ref.read(snagRepositoryProvider);
    final survey = await repo.surveyById(widget.surveyId);
    if (!mounted) return;
    setState(() => _survey = survey);
    final buildingId = survey?.buildingId;
    if (buildingId == null) return;
    try {
      final tree = await ref.read(snagTreeProvider(buildingId).future);
      if (!mounted) return;
      setState(() => _tree = tree);
      if (!_pickerShown) {
        _pickerShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _pickRoom());
      }
    } catch (_) {
      // No tree cached and no signal: the walk still works at building level.
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _cameraError = 'no camera');
        return;
      }
      final rear = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(rear, ResolutionPreset.high, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) setState(() => _cameraError = e.toString());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _camera;
    if (state == AppLifecycleState.inactive) {
      if (controller != null && controller.value.isInitialized) {
        controller.dispose();
        setState(() {
          _camera = null;
          _torch = false;
        });
      }
    } else if (state == AppLifecycleState.resumed && _camera == null) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    if (_recording) _voiceCapture.cancel();
    _voiceCapture.dispose();
    _title.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Location
  // -------------------------------------------------------------------------

  String? get _locationLabel {
    final parts = [?_survey?.buildingName, ?_floor?.name, ?_space?.name];
    return parts.isEmpty ? null : parts.join(' › ');
  }

  Future<void> _pickRoom() async {
    final tree = _tree;
    if (tree == null) return;
    final picked = await showRoomPicker(
      context,
      tree: tree,
      survey: _survey,
      initialFloorId: _floor?.id,
      allowFloorOnly: true,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _floor = picked.floor;
      _space = picked.space;
    });
  }

  List<Snag> _roomSnags(List<Snag> all) => all
      .where((s) =>
          s.surveyId == widget.surveyId &&
          (_space == null ? s.floorId == _floor?.id && s.spaceId == null : s.spaceId == _space!.id))
      .toList()
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// UC-2 — records the room as inspected, then asks for the next one.
  Future<void> _roomDone(int count) async {
    final survey = _survey;
    final floor = _floor;
    final space = _space;
    final actor = ref.read(snagActorProvider);
    if (survey == null || floor == null || space == null || actor == null) {
      await _pickRoom();
      return;
    }
    final next = await ref
        .read(snagRepositoryProvider)
        .sweep(survey, floor: floor, space: space, snagCount: count, actor: actor);
    if (!mounted) return;
    bumpSnags(ref);
    setState(() => _survey = next);
    showTechPopup(
      context,
      message: count == 0
          ? snagTr(context, 'snags.room_marked_clear', [space.name])
          : snagTr(context, 'snags.room_marked_done', [space.name, count]),
    );
    await _pickRoom();
  }

  // -------------------------------------------------------------------------
  // Capture + compose
  // -------------------------------------------------------------------------

  Future<void> _toggleTorch() async {
    final c = _camera;
    if (c == null) return;
    try {
      await c.setFlashMode(_torch ? FlashMode.off : FlashMode.torch);
      if (mounted) setState(() => _torch = !_torch);
    } catch (_) {
      // No flash unit on this lens — nothing to toggle.
    }
  }

  Future<void> _shoot() async {
    final c = _camera;
    if (c == null || _shooting || _photo != null) return;
    setState(() => _shooting = true);
    try {
      final file = await c.takePicture();
      final raw = await file.readAsBytes();
      final bytes = await compute(downscaleJpeg, raw);
      if (!mounted) return;
      setState(() {
        _photo = CapturedPhoto(bytes: bytes, fileName: 'snag.jpg');
        _shooting = false;
        if (_recentTrades.isNotEmpty) _trade = _recentTrades.first;
      });
    } catch (_) {
      if (mounted) setState(() => _shooting = false);
    }
  }

  void _resetCompose() {
    _title.clear();
    _photo = null;
    _description = null;
    _voice = null;
    _suggestion = null;
    _issueType = 'defect';
  }

  Future<void> _annotate() async {
    final photo = _photo;
    if (photo == null) return;
    final marked = await Navigator.of(context).push<CapturedPhoto>(
      MaterialPageRoute(builder: (_) => PhotoAnnotationScreen(photo: photo)),
    );
    if (marked != null && mounted) setState(() => _photo = marked);
  }

  Future<void> _toggleVoice() async {
    if (_recording) {
      final clip = await _voiceCapture.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _amplitude = null;
        _voice = clip ?? _voice;
      });
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      await _voiceCapture.start(dir.path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _amplitude = _voiceCapture.amplitudeStream();
      });
    } on CaptureFailure catch (e) {
      if (mounted) showTechPopup(context, message: e.message, isError: true);
    }
  }

  /// UC-11 — a proposal, never a write. Anything missing from the answer
  /// leaves what the inspector already chose.
  Future<void> _assist() async {
    final photo = _photo;
    if (photo == null || _assisting) return;
    setState(() => _assisting = true);
    final s = await ref.read(snagRepositoryProvider).assist(
      photo,
      voice: _voice,
      hint: _title.text.trim().isEmpty ? null : _title.text.trim(),
      context: _survey?.context ?? SnagContext.operations,
    );
    if (!mounted) return;
    setState(() {
      _assisting = false;
      _suggestion = s;
      if (s == null) return;
      if (s.trade != null) _trade = s.trade!;
      if (s.priority != null) _priority = s.priority!;
      if (s.issueType != null) _issueType = s.issueType!;
      if (s.title != null && _title.text.trim().isEmpty) _title.text = s.title!;
      _description = s.description ?? _description;
    });
    if (s == null) showTechPopup(context, message: 'snags.assist_unavailable'.getString(context));
  }

  Future<void> _save() async {
    final photo = _photo;
    final survey = _survey;
    final actor = ref.read(snagActorProvider);
    if (photo == null || survey == null || actor == null || _saving) return;
    if (_recording) await _toggleVoice();
    setState(() => _saving = true);
    final repo = ref.read(snagRepositoryProvider);
    final draft = SnagDraft(
      id: repo.newId(),
      context: survey.context,
      trade: _trade,
      priority: _priority,
      issueType: _issueType,
      title: _title.text.trim().isEmpty ? null : _title.text.trim(),
      description: _description,
      buildingId: survey.buildingId,
      floorId: _floor?.id,
      spaceId: _space?.id,
      locationLabel: _locationLabel,
      surveyId: survey.id,
      photos: [photo],
      voice: _voice,
      lat: _lat,
      lng: _lng,
    );
    try {
      // UC-3 — the duplicate guard runs against everything this device
      // knows about the building, offline included.
      final pool = await repo.local(buildingId: survey.buildingId);
      final candidates = SnagDuplicateFinder.find(draft.signature(raisedBy: actor.id), pool);
      var decision = const DuplicateDecision(DuplicateChoice.different);
      if (candidates.isNotEmpty && mounted) {
        decision = await showDuplicateSheet(
          context,
          candidates: candidates,
          draftPhoto: Image.memory(photo.bytes, fit: BoxFit.cover),
        );
      }
      final String message;
      if (decision.choice == DuplicateChoice.sameIssue && decision.snag != null) {
        final r = await repo.addEvidence(decision.snag!, actor, photos: [photo], duplicateReport: true);
        if (!mounted) return;
        message = snagTr(context, 'snags.added_to', [r.snag.displayRef]);
      } else {
        final r = await repo.raise(draft, actor);
        if (!mounted) return;
        message = r.synced
            ? snagTr(context, 'snags.saved_ref', [r.snag.displayRef])
            : 'snags.saved_on_device'.getString(context);
      }
      _recentTrades
        ..remove(_trade)
        ..insert(0, _trade);
      if (!mounted) return;
      bumpSnags(ref);
      setState(() {
        _resetCompose();
        _saving = false;
      });
      unawaited(Vibration.vibrate(duration: 40));
      showTechPopup(context, message: message);
    } on ApiFailure catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTechPopup(context, message: e.message, isError: true);
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final buildingId = _survey?.buildingId;
    final all = buildingId == null
        ? const <Snag>[]
        : (ref.watch(snagsProvider(buildingId)).valueOrNull ?? const <Snag>[]);
    final walkCount = all.where((s) => s.surveyId == widget.surveyId).length;
    final room = _roomSnags(all);

    return PopScope(
      canPop: _photo == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _photo != null) setState(_resetCompose);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _preview(),
            if (_photo != null) Image.memory(_photo!.bytes, fit: BoxFit.cover, gaplessPlayback: true),
            // Scrim so the white overlay text stays legible on a bright wall.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent, Colors.transparent, Colors.black87],
                    stops: [0, 0.22, 0.6, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(walkCount, room.length),
                  const Spacer(),
                  if (_photo == null) _bottomBar(room) else _composeCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview() {
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppText(
            'fieldVerify.camera_unavailable'.getString(context),
            align: TextAlign.center,
            color: Colors.white,
          ),
        ),
      );
    }
    final c = _camera;
    if (c == null || !c.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: c.value.previewSize?.height ?? 1080,
        height: c.value.previewSize?.width ?? 1920,
        child: CameraPreview(c),
      ),
    );
  }

  Widget _topBar(int walkCount, int roomCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(LucideIcons.x, color: Colors.white),
                tooltip: 'snags.finish_walk'.getString(context),
                onPressed: () => _photo != null ? setState(_resetCompose) : context.pop(),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _photo == null ? _pickRoom : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.mapPin, color: Colors.white, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _space?.name ?? _floor?.name ?? 'snags.pick_room'.getString(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                          ),
                        ),
                        if (_space != null && _floor != null)
                          Text(
                            _floor!.name,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        const SizedBox(width: 4),
                        const Icon(LucideIcons.chevronDown, color: Colors.white70, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _torch ? LucideIcons.flashlight : LucideIcons.flashlightOff,
                  color: _torch ? FeColors.warning : Colors.white,
                ),
                onPressed: _toggleTorch,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Counter(icon: LucideIcons.doorOpen, label: snagTr(context, 'snags.count_room', [roomCount])),
              const SizedBox(width: 8),
              _Counter(icon: LucideIcons.footprints, label: snagTr(context, 'snags.count_walk', [walkCount])),
              if (_survey != null) ...[
                const SizedBox(width: 8),
                _Counter(
                  icon: LucideIcons.check,
                  label: snagTr(context, 'snags.count_rooms_checked', [_survey!.inspectedSpaces.length]),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _bottomBar(List<Snag> room) {
    final count = room.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (room.isNotEmpty)
          SizedBox(
            height: 64,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: room.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = room[i];
                return GestureDetector(
                  onTap: () => context.push(Routes.snagDetail(s.id)),
                  child: Container(
                    width: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SnagVisuals.priorityColor(s.priority), width: 2),
                    ),
                    child: SnagPhoto(evidence: s.coverPhoto, radius: 10, dark: true),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Row(
            children: [
              Expanded(
                child: _GhostButton(
                  icon: count == 0 ? LucideIcons.circleCheck : LucideIcons.listChecks,
                  label: _space == null
                      ? 'snags.pick_room'.getString(context)
                      : (count == 0
                            ? 'snags.room_clear_btn'.getString(context)
                            : snagTr(context, 'snags.room_done_btn', [count])),
                  onTap: () => _space == null ? _pickRoom() : _roomDone(count),
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: _shoot,
                child: Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  padding: const EdgeInsets.all(5),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _shooting ? Colors.white54 : Colors.white,
                    ),
                    child: _shooting
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(strokeWidth: 2, color: FeColors.primary),
                          )
                        : const Icon(LucideIcons.plus, color: FeColors.ink, size: 28),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _GhostButton(
                  icon: LucideIcons.flag,
                  label: 'snags.finish_walk'.getString(context),
                  onTap: () => context.pushReplacement(Routes.snagSurvey(widget.surveyId)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _composeCard() {
    final s = _suggestion;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: FeColors.ink.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white12),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _ToolButton(icon: LucideIcons.pencilLine, label: 'snags.mark_up'.getString(context), onTap: _annotate),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: _recording ? LucideIcons.square : LucideIcons.mic,
                  label: _recording
                      ? 'snags.stop'.getString(context)
                      : (_voice != null ? 'snags.voice_added'.getString(context) : 'snags.voice'.getString(context)),
                  active: _recording || _voice != null,
                  danger: _recording,
                  onTap: _toggleVoice,
                ),
                const SizedBox(width: 8),
                _ToolButton(
                  icon: LucideIcons.sparkles,
                  label: 'snags.suggest'.getString(context),
                  busy: _assisting,
                  active: s != null,
                  onTap: _assist,
                ),
              ],
            ),
            if (_recording && _amplitude != null) ...[
              const SizedBox(height: 8),
              SizedBox(height: 28, child: VoiceWaveform(amplitudeStream: _amplitude!, color: FeColors.danger)),
            ],
            if (s?.transcript != null) ...[
              const SizedBox(height: 8),
              Text('“${s!.transcript}”', style: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 12),
            TradeChipRail(
              value: _trade,
              dark: true,
              suggested: s?.trade,
              ordered: [..._recentTrades, ...kSnagTrades.where((t) => !_recentTrades.contains(t))],
              onChanged: (t) => setState(() => _trade = t),
            ),
            const SizedBox(height: 10),
            SeveritySelector(
              value: _priority,
              dark: true,
              suggested: s?.priority,
              onChanged: (p) => setState(() => _priority = p),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: kSnagIssueTypes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final t = kSnagIssueTypes[i];
                  final sel = t == _issueType;
                  return GestureDetector(
                    onTap: () => setState(() => _issueType = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sel ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white30),
                      ),
                      child: Text(
                        SnagVisuals.issueLabel(context, t),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: sel ? FeColors.ink : Colors.white,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _title,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'snags.title_hint'.getString(context),
                hintStyle: const TextStyle(color: Colors.white54),
                isDense: true,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.08),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            if (_description != null) ...[
              const SizedBox(height: 6),
              Text(_description!, style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(
                  onPressed: _saving ? null : () => setState(_resetCompose),
                  child: Text('snags.discard'.getString(context), style: const TextStyle(color: Colors.white70)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: FeColors.primaryLight,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(LucideIcons.check, size: 18),
                    label: Text(
                      'snags.save_next'.getString(context),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: Colors.white70),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _GhostButton extends StatelessWidget {
  const _GhostButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final color = danger ? FeColors.danger : (active ? FeColors.primaryLight : Colors.white);
    return Expanded(
      child: GestureDetector(
        onTap: busy ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (busy)
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: color))
              else
                Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
