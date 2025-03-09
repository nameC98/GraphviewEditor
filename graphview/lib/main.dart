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
  FamilyMember? parent; // Optional parent property
  // Indicates if this member has been added as a separate tree root.
  final bool detachedRoot;

  FamilyMember({
    required this.id,
    required this.name,
    List<FamilyMember>? spouses,
    List<FamilyMember>? children,
    this.parent,
    this.detachedRoot = false,
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

/// Helper class to record the horizontal range for children groups.
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
  // Instead of a single root, we now allow multiple roots.
  List<FamilyMember> roots = [];
  // The currently selected node.
  FamilyMember? selectedMember;

  /// Map to hold computed positions for each node.
  final Map<FamilyMember, Offset> positions = {};

  /// Map to hold computed horizontal ranges for children groups.
  final Map<FamilyMember, EffectiveRange> effectiveRanges = {};

  // Layout constants.
  final double nodeRadius = 25.0;
  final double baseSpacing = 100.0; // fallback spacing for leaves
  final double verticalSpacing = 120.0;
  final double branchGap = 10.0;

  // Gap for detached parent spouses (if needed).
  final double detachedParentGap = 10.0;

  // TransformationController for InteractiveViewer.
  final TransformationController _transformationController =
      TransformationController();

  // GlobalKey for our InteractiveViewer child.
  final GlobalKey _childKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Start with a single root.
    FamilyMember mainRoot = FamilyMember(id: '1', name: 'Root');
    roots.add(mainRoot);
    selectedMember = mainRoot;
  }

  /// Computes the required width for the subtree rooted at [member].
  /// For leaves, returns [baseSpacing] as a minimum width.
  double subtreeWidth(FamilyMember member,
      {bool overrideSpouseLayout = false}) {
    if (member.children.isEmpty) return baseSpacing;
    double gap = branchGap;
    List<double> slotWidths = [];
    for (var child in member.children) {
      slotWidths.add(subtreeWidth(child));
      for (var spouse in child.spouses) {
        slotWidths.add(subtreeWidth(spouse));
      }
    }
    double total = slotWidths.fold(0.0, (prev, e) => prev + e) +
        gap * (slotWidths.length - 1);
    return total;
  }

  /// Recursively computes positions for each node.
  void computeLayout(FamilyMember member, double centerX, double y) {
    positions[member] = Offset(centerX, y);
    // Process spouse nodes.
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
        slots.add(EffectiveSlot(member: child, isSpouse: false));
        slotWidths.add(subtreeWidth(child));
        for (int i = 0; i < child.spouses.length; i++) {
          slots.add(
              EffectiveSlot(member: child, isSpouse: true, spouseIndex: i));
          slotWidths.add(subtreeWidth(child.spouses[i]));
        }
      }
      int slotCount = slots.length;
      double gap = branchGap;
      double totalWidth =
          slotWidths.fold(0.0, (prev, e) => prev + e) + gap * (slotCount - 1);
      double connectorX = centerX;
      if (member.spouses.isNotEmpty &&
          positions.containsKey(member.spouses.first)) {
        final firstSpousePos = positions[member.spouses.first]!;
        connectorX = (centerX + firstSpousePos.dx) / 2;
      }
      double startX = connectorX - totalWidth / 2;
      List<double> slotPositions = [];
      double currentX = startX;
      for (int i = 0; i < slotCount; i++) {
        double slotCenter = currentX + slotWidths[i] / 2;
        slotPositions.add(slotCenter);
        currentX += slotWidths[i] + gap;
      }

      effectiveRanges[member] =
          EffectiveRange(slotPositions.first, slotPositions.last);
      for (int i = 0; i < slotCount; i++) {
        EffectiveSlot slot = slots[i];
        double xPos = slotPositions[i];
        if (!slot.isSpouse) {
          computeLayout(slot.member, xPos, childY);
        } else {
          var spouse = slot.member.spouses[slot.spouseIndex];
          computeLayout(spouse, xPos, childY);
        }
      }
    }
  }

  /// Recursively finds a member by [id] starting from [member].
  FamilyMember? findMember(FamilyMember member, String id) {
    if (member.id == id) return member;
    for (var spouse in member.spouses) {
      var found = findMember(spouse, id);
      if (found != null) return found;
    }
    for (var child in member.children) {
      var found = findMember(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Searches for a member by [id] across all trees.
  FamilyMember? findMemberInTrees(String id) {
    for (var root in roots) {
      var found = findMember(root, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Adds a child to the member with [parentId].
  void addChild(String parentId, FamilyMember child) {
    final parent = findMemberInTrees(parentId);
    if (parent != null) {
      setState(() {
        parent.children.add(child);
      });
    }
  }

  /// Adds a spouse to the member with [memberId].
  /// If not found, falls back to the selected node.
  void addSpouse(String memberId, FamilyMember spouse) {
    FamilyMember? member = findMemberInTrees(memberId);
    member ??= selectedMember;
    if (member != null) {
      setState(() {
        member!.spouses.add(spouse);
      });
    }
  }

  /// Checks whether the [target] member is added as a spouse in any family tree.
  bool isSpouse(FamilyMember target) {
    bool found = false;
    for (FamilyMember root in roots) {
      if (_searchForSpouse(root, target)) {
        found = true;
        break;
      }
    }
    return found;
  }

  bool _searchForSpouse(FamilyMember member, FamilyMember target) {
    if (member.spouses.contains(target)) {
      return true;
    }
    // Search within this member's spouses.
    for (var spouse in member.spouses) {
      if (_searchForSpouse(spouse, target)) return true;
    }
    // Search within children.
    for (var child in member.children) {
      if (_searchForSpouse(child, target)) return true;
    }
    return false;
  }

  /// Dynamically adds a parent to the selected node.
  /// Now only spouse nodes can add a parent.
  void addParent() {
    if (selectedMember != null) {
      // Only allow adding a parent if the selected node is a spouse.
      if (!isSpouse(selectedMember!)) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Only spouse nodes can add a parent")));
        return;
      }
      if (selectedMember!.parent != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("This node already has a parent")));
      } else {
        setState(() {
          final parentId = DateTime.now().millisecondsSinceEpoch.toString();
          FamilyMember newParent = FamilyMember(
            id: parentId,
            name: 'Parent',
            detachedRoot: true,
          );
          selectedMember!.parent = newParent;
          // Add the new parent as a separate root.
          roots.add(newParent);
        });
      }
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("No node selected")));
    }
  }

  /// Returns all nodes in drawing order for a tree starting from [member].
  List<FamilyMember> getDrawingOrder(FamilyMember member) {
    List<FamilyMember> order = [member];
    for (var spouse in member.spouses) {
      order.add(spouse);
    }
    for (var spouse in member.spouses) {
      order.addAll(getDrawingOrderForChildren(spouse));
    }
    order.addAll(getDrawingOrderForChildren(member));
    return order;
  }

  List<FamilyMember> getDrawingOrderForChildren(FamilyMember member) {
    List<FamilyMember> order = [];
    for (var child in member.children) {
      order.addAll(getDrawingOrder(child));
    }
    return order;
  }

  /// Helper to get all nodes in a tree starting from [root] (following children and spouses).
  List<FamilyMember> getTreeNodes(FamilyMember root) {
    List<FamilyMember> nodes = [];
    void traverse(FamilyMember member) {
      if (!nodes.contains(member)) {
        nodes.add(member);
        for (var spouse in member.spouses) {
          traverse(spouse);
        }
        for (var child in member.children) {
          traverse(child);
        }
      }
    }

    traverse(root);
    return nodes;
  }

  /// Hit testing: returns the node whose drawn position is within nodeRadius.
  FamilyMember? _hitTest(Offset point) {
    for (var member in positions.keys) {
      final pos = positions[member];
      if (pos != null && (pos - point).distance <= nodeRadius) {
        return member;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    positions.clear();
    effectiveRanges.clear();
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    // Compute each tree’s layout separately and stack them vertically.
    double currentOffsetY = 60;
    for (var root in roots) {
      computeLayout(root, screenWidth / 2, currentOffsetY);
      List<FamilyMember> treeNodes = getTreeNodes(root);
      double treeMaxY = treeNodes.map((n) => positions[n]!.dy).reduce(math.max);
      double treeMinY = treeNodes.map((n) => positions[n]!.dy).reduce(math.min);
      double treeHeight = treeMaxY - treeMinY;
      currentOffsetY += treeHeight + 150; // margin between trees
    }

    // Note: removed the separate post-layout adjustment for detached parents.

    // Compute overall bounding box.
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
        EffectiveRange(range.left + shift.dx, range.right + shift.dy));
    final computedWidth = (maxX - minX) + safeMargin * 2;
    final computedHeight = (maxY - minY) + safeMargin * 2;
    final canvasWidth = math.max(computedWidth, screenWidth);
    final canvasHeight = math.max(computedHeight, screenHeight);
    final extraShift = Offset(
        (canvasWidth - computedWidth) / 2, (canvasHeight - computedHeight) / 2);
    positions.updateAll((member, pos) => pos + extraShift);
    effectiveRanges.updateAll((member, range) => EffectiveRange(
        range.left + extraShift.dx, range.right + extraShift.dy));

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
                    roots: roots,
                    positions: positions,
                    effectiveRanges: effectiveRanges,
                    nodeRadius: nodeRadius,
                    selectedMember: selectedMember,
                    baseSpacing: baseSpacing,
                  ),
                ),
              ),
            ),
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
          // Add Child Button
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
          // Add Spouse Button
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
          const SizedBox(height: 10),
          // Add Parent Button
          FloatingActionButton(
            heroTag: "parent",
            onPressed: addParent,
            tooltip: 'Add Parent to Selected Node (only spouse nodes allowed)',
            child: const Icon(Icons.account_tree),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that draws the family trees.
class FamilyTreePainter extends CustomPainter {
  final List<FamilyMember> roots;
  final Map<FamilyMember, Offset> positions;
  final Map<FamilyMember, EffectiveRange> effectiveRanges;
  final double nodeRadius;
  final FamilyMember? selectedMember;
  final double baseSpacing;
  // Gap used when drawing a non-detached parent above its child.
  final double parentGap = 60.0;

  FamilyTreePainter({
    required this.roots,
    required this.positions,
    required this.effectiveRanges,
    required this.nodeRadius,
    this.selectedMember,
    required this.baseSpacing,
  });

  final Paint linePaint = Paint()
    ..color = Colors.grey
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw each tree.
    for (var root in roots) {
      _drawConnectors(canvas, root);
      _drawNodes(canvas, root);
    }
    // Draw connector lines for nodes whose parent is detached.
    positions.forEach((member, pos) {
      if (member.parent != null && member.parent!.detachedRoot) {
        Offset parentPos = positions[member.parent] ?? pos;
        canvas.drawLine(Offset(pos.dx, pos.dy - nodeRadius),
            Offset(parentPos.dx, parentPos.dy + nodeRadius), linePaint);
      }
    });
  }

  /// Draws connectors for spouses and children.
  void _drawConnectors(Canvas canvas, FamilyMember member,
      {Offset? connectorOrigin}) {
    final Offset nodeOrigin = connectorOrigin ?? positions[member]!;
    // Draw spouse connectors.
    if (member.spouses.isNotEmpty) {
      for (int i = 0; i < member.spouses.length; i++) {
        final spouse = member.spouses[i];
        final spousePos = positions[spouse];
        if (spousePos != null) {
          double offsetY = 4.0 * i;
          final Offset start =
              Offset(nodeOrigin.dx + nodeRadius, nodeOrigin.dy - offsetY);
          final Offset end =
              Offset(spousePos.dx - nodeRadius, spousePos.dy - offsetY);
          canvas.drawLine(start, end, linePaint);
          final Offset linkCenter =
              Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
          _drawLinkIcon(canvas, linkCenter, linePaint.color);
          _drawConnectors(canvas, spouse, connectorOrigin: linkCenter);
        }
      }
    }
    // Draw connectors for children.
    if (member.children.isNotEmpty) {
      final Offset baseConnector;
      if (connectorOrigin == null &&
          member.spouses.isNotEmpty &&
          positions.containsKey(member.spouses.first)) {
        final firstSpousePos = positions[member.spouses.first]!;
        baseConnector = Offset((positions[member]!.dx + firstSpousePos.dx) / 2,
            (positions[member]!.dy + firstSpousePos.dy) / 2);
      } else {
        baseConnector = nodeOrigin;
      }
      const double stubLength = 12;
      double childCenterY = positions[member.children.first]!.dy;
      double childConnectorY = childCenterY - nodeRadius - stubLength;

      // Calculate leftmost and rightmost x from children positions.
      double leftX = double.infinity;
      double rightX = double.negativeInfinity;
      for (var child in member.children) {
        final childPos = positions[child]!;
        if (childPos.dx < leftX) leftX = childPos.dx;
        if (childPos.dx > rightX) rightX = childPos.dx;
      }

      double joinX = baseConnector.dx;
      if (joinX < leftX)
        joinX = leftX;
      else if (joinX > rightX) joinX = rightX;
      Offset joinPoint = Offset(joinX, childConnectorY);
      if (baseConnector.dx == joinX) {
        canvas.drawLine(baseConnector, joinPoint, linePaint);
      } else {
        double midY = childConnectorY - stubLength;
        canvas.drawLine(
            baseConnector, Offset(baseConnector.dx, midY), linePaint);
        canvas.drawLine(
            Offset(baseConnector.dx, midY), Offset(joinX, midY), linePaint);
        canvas.drawLine(Offset(joinX, midY), joinPoint, linePaint);
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
    // Recursively process children.
    for (var child in member.children) {
      _drawConnectors(canvas, child);
    }
  }

  void _drawNodes(Canvas canvas, FamilyMember member) {
    final Offset? pos = positions[member];
    if (pos == null) return;
    // Draw this node's avatar.
    _drawAvatar(canvas, pos, member.name, member == selectedMember);
    // Always draw the parent if available.
    if (member.parent != null) {
      _drawParent(canvas, member.parent!, pos);
    }
    // Process spouses.
    if (member.spouses.isNotEmpty) {
      for (var spouse in member.spouses) {
        if (spouse.children.isNotEmpty) {
          _drawNodes(canvas, spouse);
        } else {
          final spousePos = positions[spouse];
          if (spousePos != null) {
            _drawAvatar(
                canvas, spousePos, spouse.name, spouse == selectedMember);
            if (spouse.parent != null) {
              _drawParent(canvas, spouse.parent!, spousePos);
            }
          }
        }
      }
    }
    // Process children.
    for (var child in member.children) {
      _drawNodes(canvas, child);
    }
  }

  /// Helper to draw a parent node above a child.
  void _drawParent(Canvas canvas, FamilyMember parent, Offset childPos) {
    // Use a different gap if the parent is detached.
    final double gap = parent.detachedRoot ? (nodeRadius + 40) : parentGap;
    final Offset parentPos = Offset(childPos.dx, childPos.dy - gap);
    positions[parent] = parentPos;
    // Draw connectors for parent's spouses.
    if (parent.spouses.isNotEmpty) {
      for (int i = 0; i < parent.spouses.length; i++) {
        final parentSpouse = parent.spouses[i];
        double offsetY = 4.0 * i;
        final Offset parentSpousePos = Offset(
            parentPos.dx + (i + 1) * baseSpacing, parentPos.dy - offsetY);
        positions[parentSpouse] = parentSpousePos;
        canvas.drawLine(
          Offset(parentPos.dx + nodeRadius, parentPos.dy - offsetY),
          Offset(parentSpousePos.dx - nodeRadius, parentSpousePos.dy),
          linePaint,
        );
        _drawLinkIcon(
            canvas,
            Offset((parentPos.dx + parentSpousePos.dx) / 2,
                parentPos.dy - offsetY),
            linePaint.color);
      }
    }
    // Draw parent's avatar.
    _drawAvatar(canvas, parentPos, parent.name, parent == selectedMember);
    // Draw the connector line from parent's bottom to child's top.
    canvas.drawLine(Offset(childPos.dx, parentPos.dy + nodeRadius),
        Offset(childPos.dx, childPos.dy - nodeRadius), linePaint);
    // Draw parent's spouse avatars.
    if (parent.spouses.isNotEmpty) {
      for (int i = 0; i < parent.spouses.length; i++) {
        final parentSpouse = parent.spouses[i];
        double offsetY = 4.0 * i;
        final Offset parentSpousePos = Offset(
            parentPos.dx + (i + 1) * baseSpacing, parentPos.dy - offsetY);
        positions[parentSpouse] = parentSpousePos;
        _drawAvatar(canvas, parentSpousePos, parentSpouse.name,
            parentSpouse == selectedMember);
      }
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
