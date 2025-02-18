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
  Map<FamilyMember, Offset> positions = {};

  // Layout constants (adjust as needed)
  final double nodeRadius = 25.0;
  final double horizontalSpacing = 100.0;
  final double verticalSpacing = 120.0;

  @override
  void initState() {
    super.initState();
    // Start with a single node.
    root = FamilyMember(id: '1', name: 'Root');
  }

  /// Recursively computes positions for each member.
  ///
  /// - [member] is positioned at (centerX, y).
  /// - Any spouses are placed to the right on the same level.
  /// - Children (if any) are centered below a “connector” point.
  void computeLayout(FamilyMember member, double centerX, double y) {
    positions[member] = Offset(centerX, y);

    // Place spouses to the right of the member.
    for (int i = 0; i < member.spouses.length; i++) {
      positions[member.spouses[i]] =
          Offset(centerX + (i + 1) * horizontalSpacing, y);
    }

    // For children: determine a connector X (average of member and first spouse, if any)
    if (member.children.isNotEmpty) {
      double childY = y + verticalSpacing;
      double connectorX = centerX;
      if (member.spouses.isNotEmpty) {
        connectorX = (centerX + positions[member.spouses.first]!.dx) / 2;
      }
      int n = member.children.length;
      double totalWidth = (n - 1) * horizontalSpacing;
      double startX = connectorX - totalWidth / 2;
      for (int i = 0; i < n; i++) {
        computeLayout(
            member.children[i], startX + i * horizontalSpacing, childY);
      }
    }
  }

  /// Searches for a member with a given [id] recursively.
  FamilyMember? findMember(FamilyMember member, String id) {
    if (member.id == id) return member;
    for (var spouse in member.spouses) {
      if (spouse.id == id) return spouse;
    }
    for (var child in member.children) {
      final found = findMember(child, id);
      if (found != null) return found;
    }
    return null;
  }

  /// Adds a new child node to the member with [parentId].
  void addChild(String parentId, FamilyMember child) {
    final parent = findMember(root, parentId);
    if (parent != null) {
      setState(() {
        parent.children.add(child);
      });
    }
  }

  /// Adds a new spouse node to the member with [memberId].
  void addSpouse(String memberId, FamilyMember spouse) {
    final member = findMember(root, memberId);
    if (member != null) {
      setState(() {
        member.spouses.add(spouse);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    positions.clear();
    final screenWidth = MediaQuery.of(context).size.width;
    // Start layout with the root centered at the top.
    computeLayout(root, screenWidth / 2, 60);

    return Scaffold(
      appBar: AppBar(title: const Text("Dynamic Family Tree")),
      body: Container(
        color: const Color(0xFFF5F3E5),
        child: InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(1000),
          minScale: 0.1,
          maxScale: 5.0,
          child: CustomPaint(
            size: MediaQuery.of(context).size,
            painter: FamilyTreePainter(
              root: root,
              positions: positions,
              nodeRadius: nodeRadius,
            ),
          ),
        ),
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // FAB to add a child to the root.
          FloatingActionButton(
            heroTag: 'addChild',
            onPressed: () {
              final newId = DateTime.now().millisecondsSinceEpoch.toString();
              addChild('1', FamilyMember(id: newId, name: 'Child'));
            },
            tooltip: 'Add Child',
            child: const Icon(Icons.child_care),
          ),
          const SizedBox(height: 10),
          // FAB to add a spouse to the root.
          FloatingActionButton(
            heroTag: 'addSpouse',
            onPressed: () {
              final newId = DateTime.now().millisecondsSinceEpoch.toString();
              addSpouse('1', FamilyMember(id: newId, name: 'Spouse'));
            },
            tooltip: 'Add Spouse',
            child: const Icon(Icons.favorite),
          ),
        ],
      ),
    );
  }
}

/// CustomPainter that recursively draws the family tree.
class FamilyTreePainter extends CustomPainter {
  final FamilyMember root;
  final Map<FamilyMember, Offset> positions;
  final double nodeRadius;
  final Paint linePaint = Paint()
    ..color = Colors.grey
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  FamilyTreePainter({
    required this.root,
    required this.positions,
    required this.nodeRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawFamily(canvas, root);
  }

  /// Recursively draws each member, its connectors, and its subtree.
  void _drawFamily(Canvas canvas, FamilyMember member) {
    final pos = positions[member];
    if (pos == null) return;
    // Draw the member's node.
    _drawAvatar(canvas, pos, member.name);

    // Draw spouse connectors and nodes.
    for (var spouse in member.spouses) {
      final spousePos = positions[spouse];
      if (spousePos != null) {
        canvas.drawLine(pos, spousePos, linePaint);
        _drawAvatar(canvas, spousePos, spouse.name);
      }
    }

    // Draw connectors for children if any.
    if (member.children.isNotEmpty) {
      // Determine connector start point.
      final connectorStart = member.spouses.isNotEmpty
          ? Offset((pos.dx + positions[member.spouses.first]!.dx) / 2, pos.dy)
          : pos;
      // Vertical drop from connector.
      final connectorY = positions[member.children.first]!.dy - 20;
      canvas.drawLine(
          connectorStart, Offset(connectorStart.dx, connectorY), linePaint);
      // Horizontal line connecting all children.
      final leftX = positions[member.children.first]!.dx;
      final rightX = positions[member.children.last]!.dx;
      canvas.drawLine(
          Offset(leftX, connectorY), Offset(rightX, connectorY), linePaint);
      // Draw vertical drops to each child.
      for (var child in member.children) {
        final childPos = positions[child]!;
        canvas.drawLine(Offset(childPos.dx, connectorY), childPos, linePaint);
      }
    }

    // Recurse for children.
    for (var child in member.children) {
      _drawFamily(canvas, child);
    }
  }

  /// Draws a circular avatar with centered text.
  void _drawAvatar(Canvas canvas, Offset center, String label) {
    final Paint circlePaint = Paint()..color = const Color(0xFFCBCBCB);
    canvas.drawCircle(center, nodeRadius, circlePaint);

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
    return oldDelegate.positions != positions;
  }
}
