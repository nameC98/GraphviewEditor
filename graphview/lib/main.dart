import 'dart:math' as math;
import 'package:flutter/material.dart';

void main() {
  runApp(const FamilyTreeApp());
}

/// The root widget.
class FamilyTreeApp extends StatelessWidget {
  const FamilyTreeApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dynamic Family Tree',
      debugShowCheckedModeBanner: false,
      home: const FamilyTreeWidget(),
    );
  }
}

/// Data model for a family member.
class FamilyMember {
  final String id;
  final String name;
  final List<FamilyMember> spouses;
  final List<FamilyMember> children;

  FamilyMember({
    required this.id,
    required this.name,
    List<FamilyMember>? spouses,
    List<FamilyMember>? children,
  })  : spouses = spouses ?? [],
        children = children ?? [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is FamilyMember && other.id == id);
  @override
  int get hashCode => id.hashCode;
}

/// Helper class for ordering slots for a child group.
class EffectiveSlot {
  final FamilyMember member;
  final bool isSpouse;
  final int spouseIndex;
  EffectiveSlot({
    required this.member,
    required this.isSpouse,
    this.spouseIndex = 0,
  });
}

/// Helper class to record the horizontal range for a parent's children.
class EffectiveRange {
  final double left;
  final double right;
  EffectiveRange(this.left, this.right);
}

/// This widget holds the dynamic family tree.
class FamilyTreeWidget extends StatefulWidget {
  const FamilyTreeWidget({Key? key}) : super(key: key);

  @override
  _FamilyTreeWidgetState createState() => _FamilyTreeWidgetState();
}

class _FamilyTreeWidgetState extends State<FamilyTreeWidget> {
  late FamilyMember root;

  /// Map to hold computed positions for each node.
  final Map<FamilyMember, Offset> positions = {};

  /// Map to hold computed horizontal ranges for children groups.
  final Map<FamilyMember, EffectiveRange> effectiveRanges = {};

  /// The currently selected node.
  FamilyMember? selectedMember;

  // Layout constants.
  final double nodeRadius = 25.0;
  final double baseSpacing = 100.0; // Fixed slot width for an immediate node.
  final double verticalSpacing = 120.0;
  final double branchGap = 50.0;

  // TransformationController for InteractiveViewer (if zooming/panning is desired)
  final TransformationController _transformationController =
      TransformationController();

  // GlobalKey for our InteractiveViewer child.
  final GlobalKey _childKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Start with a single node.
    root = FamilyMember(id: '1', name: 'Root');
    selectedMember = root;
  }

  /// Returns the fixed immediate width for a node (and its spouse slots) on its parent's children row.
  double immediateWidth(FamilyMember member) {
    return baseSpacing;
  }

  /// Recursively computes positions for each node.
  ///
  /// For a given parent, its immediate children (and any spouse slots) are spaced using a fixed width,
  /// so that the parent's children row stays constant even if deeper subtrees grow wider.
  void computeLayout(FamilyMember member, double centerX, double y) {
    // Set this node's position.
    positions[member] = Offset(centerX, y);

    // Process spouse nodes (same y-level).
    if (member.spouses.isNotEmpty) {
      for (int i = 0; i < member.spouses.length; i++) {
        FamilyMember spouse = member.spouses[i];
        double spouseX = centerX + (i + 1) * baseSpacing;
        computeLayout(spouse, spouseX, y);
      }
    }

    // Process children.
    if (member.children.isNotEmpty) {
      double childY = y + verticalSpacing;
      List<EffectiveSlot> slots = [];
      List<double> slotWidths = [];

      for (var child in member.children) {
        // Each child gets one slot.
        slots.add(EffectiveSlot(member: child, isSpouse: false));
        slotWidths.add(immediateWidth(child));
        // And each spouse of that child gets its own slot.
        for (int i = 0; i < child.spouses.length; i++) {
          slots.add(
              EffectiveSlot(member: child, isSpouse: true, spouseIndex: i));
          slotWidths.add(immediateWidth(child));
        }
      }

      int slotCount = slots.length;
      double gap = branchGap;
      double totalWidth =
          slotWidths.fold(0.0, (prev, e) => prev + e) + gap * (slotCount - 1);

      // Use the parent's center or (if available) average with the first spouse.
      double connectorX = centerX;
      if (member.spouses.isNotEmpty &&
          positions.containsKey(member.spouses.first)) {
        connectorX = (centerX + positions[member.spouses.first]!.dx) / 2;
      }
      double startX = connectorX - totalWidth / 2;

      List<double> slotPositions = [];
      double currentX = startX;
      for (int i = 0; i < slotCount; i++) {
        double slotCenter = currentX + slotWidths[i] / 2;
        slotPositions.add(slotCenter);
        currentX += slotWidths[i] + gap;
      }

      // Record the horizontal range for connecting children.
      effectiveRanges[member] =
          EffectiveRange(slotPositions.first, slotPositions.last);

      // Recursively compute layout for each slot.
      for (int i = 0; i < slotCount; i++) {
        double xPos = slotPositions[i];
        EffectiveSlot slot = slots[i];
        if (!slot.isSpouse) {
          computeLayout(slot.member, xPos, childY);
        } else {
          var spouse = slot.member.spouses[slot.spouseIndex];
          computeLayout(spouse, xPos, childY);
        }
      }
    }
  }

  /// Recursively finds a member by [id].
  FamilyMember? findMember(FamilyMember member, String id) {
    if (member.id == id) return member;
    for (var spouse in member.spouses) {
      if (spouse.id == id) return spouse;
    }
    for (var child in member.children) {
      var found = findMember(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Adds a child to the member with [parentId].
  void addChild(String parentId, FamilyMember child) {
    final parent = findMember(root, parentId);
    if (parent != null) {
      setState(() {
        parent.children.add(child);
      });
    }
  }

  /// Adds a spouse to the member with [memberId].
  void addSpouse(String memberId, FamilyMember spouse) {
    final member = findMember(root, memberId);
    if (member != null) {
      setState(() {
        member.spouses.add(spouse);
      });
    }
  }

  /// Returns a list of family members in the same drawing order.
  /// (This order is used so that nodes drawn on top are hit-tested first.)
  List<FamilyMember> getDrawingOrder(FamilyMember member) {
    List<FamilyMember> order = [];
    order.add(member);
    if (member.spouses.isNotEmpty) {
      for (var spouse in member.spouses) {
        if (spouse.children.isNotEmpty) {
          order.addAll(getDrawingOrder(spouse));
        } else {
          order.add(spouse);
        }
      }
    }
    for (var child in member.children) {
      order.addAll(getDrawingOrder(child));
    }
    return order;
  }

  /// Hit testing based on our computed positions.
  FamilyMember? _hitTest(Offset point) {
    List<FamilyMember> order = getDrawingOrder(root);
    for (var member in order.reversed) {
      final pos = positions[member];
      if (pos != null && (pos - point).distance <= nodeRadius) {
        return member;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // Clear previous positions.
    positions.clear();
    effectiveRanges.clear();
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Compute layout starting at the top-center.
    computeLayout(root, screenWidth / 2, 60);

    // --- Compute bounding box for the tree (with safe margin) ---
    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (var pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    const double safeMargin = 100.0;
    final shift = Offset(safeMargin - minX, safeMargin - minY);
    positions.updateAll((member, pos) => pos + shift);
    effectiveRanges.updateAll((member, range) =>
        EffectiveRange(range.left + shift.dx, range.right + shift.dx));

    final computedWidth = (maxX - minX) + safeMargin * 2;
    final computedHeight = (maxY - minY) + safeMargin * 2;

    // Use full available width and height if computed dimensions are smaller.
    final canvasWidth = math.max(computedWidth, screenWidth);
    final canvasHeight = math.max(computedHeight, screenHeight);

    // If extra space is available, center the tree.
    final extraShift = Offset(
        (canvasWidth - computedWidth) / 2, (canvasHeight - computedHeight) / 2);
    positions.updateAll((member, pos) => pos + extraShift);
    effectiveRanges.updateAll((member, range) => EffectiveRange(
        range.left + extraShift.dx, range.right + extraShift.dx));

    return Scaffold(
      appBar: AppBar(title: const Text("Dynamic Family Tree")),
      body: Container(
        color: const Color(0xFFF5F3E5),
        child: Stack(
          children: [
            InteractiveViewer(
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(1000),
              minScale: 0.1,
              maxScale: 5.0,
              child: SizedBox(
                key: _childKey,
                width: canvasWidth,
                height: canvasHeight,
                child: CustomPaint(
                  size: Size(canvasWidth, canvasHeight),
                  painter: FamilyTreePainter(
                    root: root,
                    positions: positions,
                    effectiveRanges: effectiveRanges,
                    nodeRadius: nodeRadius,
                    selectedMember: selectedMember,
                  ),
                ),
              ),
            ),
            // Top-level GestureDetector to convert global taps.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTapDown: (details) {
                  final RenderBox box =
                      _childKey.currentContext!.findRenderObject() as RenderBox;
                  final localPosition =
                      box.globalToLocal(details.globalPosition);
                  final tappedMember = _hitTest(localPosition);
                  if (tappedMember != null) {
                    setState(() {
                      selectedMember = tappedMember;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "child",
            onPressed: () {
              if (selectedMember != null) {
                final newId = DateTime.now().millisecondsSinceEpoch.toString();
                addChild(
                    selectedMember!.id, FamilyMember(id: newId, name: 'Child'));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No node selected")));
              }
            },
            tooltip: 'Add Child to Selected Node',
            child: const Icon(Icons.child_care),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: "spouse",
            onPressed: () {
              if (selectedMember != null) {
                final newId = DateTime.now().millisecondsSinceEpoch.toString();
                addSpouse(selectedMember!.id,
                    FamilyMember(id: newId, name: 'Spouse'));
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("No node selected")));
              }
            },
            tooltip: 'Add Spouse to Selected Node',
            child: const Icon(Icons.favorite),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that draws the family tree.
class FamilyTreePainter extends CustomPainter {
  final FamilyMember root;
  final Map<FamilyMember, Offset> positions;
  final Map<FamilyMember, EffectiveRange> effectiveRanges;
  final double nodeRadius;
  final FamilyMember? selectedMember;

  FamilyTreePainter({
    required this.root,
    required this.positions,
    required this.effectiveRanges,
    required this.nodeRadius,
    this.selectedMember,
  });

  final Paint linePaint = Paint()
    ..color = Colors.grey
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    _drawConnectors(canvas, root);
    _drawNodes(canvas, root);
  }

  void _drawConnectors(Canvas canvas, FamilyMember member) {
    final Offset? pos = positions[member];
    if (pos == null) return;

    // Draw spouse connectors.
    if (member.spouses.isNotEmpty) {
      for (int i = 0; i < member.spouses.length; i++) {
        final spouse = member.spouses[i];
        final spousePos = positions[spouse];
        if (spousePos != null) {
          double offsetY = 4.0 * i;
          final Offset start = Offset(pos.dx + nodeRadius, pos.dy - offsetY);
          final Offset end =
              Offset(spousePos.dx - nodeRadius, spousePos.dy - offsetY);
          canvas.drawLine(start, end, linePaint);
          if (i == 0) {
            final Offset midpoint =
                Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
            _drawLinkIcon(canvas, midpoint, linePaint.color);
          } else {
            final Offset iconPos =
                Offset(spousePos.dx - nodeRadius - 30, spousePos.dy - offsetY);
            _drawLinkIcon(canvas, iconPos, linePaint.color);
          }
        }
      }
    }

    // Draw connectors for children.
    if (member.children.isNotEmpty) {
      Offset connector = pos;
      if (member.spouses.isNotEmpty &&
          positions.containsKey(member.spouses.first)) {
        final firstSpousePos = positions[member.spouses.first]!;
        connector = Offset(
            (pos.dx + firstSpousePos.dx) / 2, (pos.dy + firstSpousePos.dy) / 2);
      }

      const double stubLength = 12;
      double childCenterY = positions[member.children.first]!.dy;
      double childConnectorY = childCenterY - nodeRadius - stubLength;

      double leftX, rightX;
      if (effectiveRanges.containsKey(member)) {
        final range = effectiveRanges[member]!;
        leftX = range.left;
        rightX = range.right;
      } else {
        leftX = positions[member.children.first]!.dx;
        rightX = positions[member.children.last]!.dx;
      }

      double joinX = connector.dx;
      if (joinX < leftX)
        joinX = leftX;
      else if (joinX > rightX) joinX = rightX;
      Offset joinPoint = Offset(joinX, childConnectorY);

      if (connector.dx == joinX) {
        canvas.drawLine(connector, joinPoint, linePaint);
        canvas.drawCircle(joinPoint, 3.0, Paint()..color = linePaint.color);
      } else {
        double midY = childConnectorY - stubLength;
        canvas.drawLine(connector, Offset(connector.dx, midY), linePaint);
        canvas.drawLine(
            Offset(connector.dx, midY), Offset(joinX, midY), linePaint);
        canvas.drawLine(Offset(joinX, midY), joinPoint, linePaint);
        canvas.drawCircle(
            Offset(joinX, midY), 3.0, Paint()..color = linePaint.color);
      }

      canvas.drawLine(Offset(leftX, childConnectorY),
          Offset(rightX, childConnectorY), linePaint);
      for (var child in member.children) {
        final childPos = positions[child]!;
        final Offset avatarTop = Offset(childPos.dx, childPos.dy - nodeRadius);
        canvas.drawLine(
            Offset(childPos.dx, childConnectorY), avatarTop, linePaint);
      }
    }

    for (var child in member.children) {
      _drawConnectors(canvas, child);
    }
    if (member.spouses.isNotEmpty) {
      for (var spouse in member.spouses) {
        if (spouse.children.isNotEmpty) {
          _drawConnectors(canvas, spouse);
        }
      }
    }
  }

  void _drawNodes(Canvas canvas, FamilyMember member) {
    final Offset? pos = positions[member];
    if (pos == null) return;
    _drawAvatar(canvas, pos, member.name, member == selectedMember);

    if (member.spouses.isNotEmpty) {
      for (var spouse in member.spouses) {
        if (spouse.children.isNotEmpty) {
          _drawNodes(canvas, spouse);
        } else {
          final spousePos = positions[spouse];
          if (spousePos != null) {
            _drawAvatar(
                canvas, spousePos, spouse.name, spouse == selectedMember);
          }
        }
      }
    }
    for (var child in member.children) {
      _drawNodes(canvas, child);
    }
  }

  void _drawLinkIcon(Canvas canvas, Offset center, Color backgroundColor) {
    const double iconBgRadius = 12.0;
    final Paint bgPaint = Paint()..color = backgroundColor;
    canvas.drawCircle(center, iconBgRadius, bgPaint);

    final TextSpan textSpan = TextSpan(
      text: String.fromCharCode(Icons.link.codePoint),
      style: TextStyle(
        fontFamily: Icons.link.fontFamily,
        package: Icons.link.fontPackage,
        fontSize: 16,
        color: Colors.white,
      ),
    );
    final TextPainter textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    final Offset iconOffset = Offset(
        center.dx - textPainter.width / 2, center.dy - textPainter.height / 2);
    textPainter.paint(canvas, iconOffset);
  }

  void _drawAvatar(
      Canvas canvas, Offset center, String label, bool isSelected) {
    final Paint circlePaint = Paint()..color = const Color(0xFFCBCBCB);
    canvas.drawCircle(center, nodeRadius, circlePaint);

    if (isSelected) {
      final Paint borderPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, nodeRadius + 2, borderPaint);
    }

    final TextSpan span = TextSpan(
      text: label,
      style: const TextStyle(color: Colors.black, fontSize: 10),
    );
    final TextPainter tp = TextPainter(
      text: span,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout(minWidth: 0, maxWidth: nodeRadius * 2);
    final Offset textOffset =
        Offset(center.dx - tp.width / 2, center.dy - tp.height / 2);
    tp.paint(canvas, textOffset);
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.selectedMember != selectedMember;
  }
}
