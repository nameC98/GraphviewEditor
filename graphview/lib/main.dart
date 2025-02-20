import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const FamilyTreeApp());
}

/// Enum for Gender.
enum Gender { male, female }

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
  String name;
  Gender gender;
  final List<FamilyMember> spouses;
  final List<FamilyMember> children;
  // NEW: List of parents for added spouses.
  final List<FamilyMember> parents;

  FamilyMember({
    required this.id,
    required this.name,
    this.gender = Gender.male,
    List<FamilyMember>? spouses,
    List<FamilyMember>? children,
    List<FamilyMember>? parents,
  })  : spouses = spouses ?? [],
        children = children ?? [],
        parents = parents ?? [];

  // Convert gender to string.
  String get genderAsString => gender == Gender.male ? "male" : "female";

  // JSON serialization.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gender': genderAsString,
      'spouses': spouses.map((s) => s.toJson()).toList(),
      'children': children.map((c) => c.toJson()).toList(),
      'parents': parents.map((p) => p.toJson()).toList(),
    };
  }

  // JSON deserialization.
  static FamilyMember fromJson(Map<String, dynamic> json) {
    return FamilyMember(
      id: json['id'],
      name: json['name'],
      gender: json['gender'] == 'male' ? Gender.male : Gender.female,
      spouses: (json['spouses'] as List<dynamic>)
          .map((s) => FamilyMember.fromJson(s))
          .toList(),
      children: (json['children'] as List<dynamic>)
          .map((c) => FamilyMember.fromJson(c))
          .toList(),
      parents: json.containsKey('parents')
          ? (json['parents'] as List<dynamic>)
              .map((p) => FamilyMember.fromJson(p))
              .toList()
          : [],
    );
  }

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
  final double baseSpacing = 100.0; // fallback spacing for leaves
  final double verticalSpacing = 120.0;
  final double branchGap = 10.0;

  // TransformationController for InteractiveViewer.
  final TransformationController _transformationController =
      TransformationController();

  // GlobalKey for our InteractiveViewer child.
  final GlobalKey _childKey = GlobalKey();

  // Avatar images.
  ui.Image? maleAvatar;
  ui.Image? femaleAvatar;

  @override
  void initState() {
    super.initState();
    // Start with a single node.
    root = FamilyMember(id: '1', name: 'Root');
    selectedMember = root;
    _loadAvatars();
    _loadTreeFromStorage();
  }

  /// Loads avatar images from assets.
  Future<void> _loadAvatars() async {
    final maleData = await rootBundle.load('assets/man.jpg');
    final femaleData = await rootBundle.load('assets/women.jpg');
    final maleImg = await decodeImageFromList(maleData.buffer.asUint8List());
    final femaleImg =
        await decodeImageFromList(femaleData.buffer.asUint8List());
    setState(() {
      maleAvatar = maleImg;
      femaleAvatar = femaleImg;
    });
  }

  /// Computes the required width for the subtree rooted at [member].
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
  /// The root is positioned at (screenWidth/2, 60).
  void computeLayout(FamilyMember member, double centerX, double y) {
    positions[member] = Offset(centerX, y);
    if (member.spouses.isNotEmpty) {
      for (int i = 0; i < member.spouses.length; i++) {
        FamilyMember spouse = member.spouses[i];
        double spouseX = centerX + (i + 1) * baseSpacing;
        computeLayout(spouse, spouseX, y);
      }
    }
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

  /// Returns true if [member] is a main node (i.e. not added as a spouse).
  bool isMainNode(FamilyMember member) {
    if (member == root) return true;
    return !_searchInSpouseLists(root, member);
  }

  bool _searchInSpouseLists(FamilyMember node, FamilyMember target) {
    if (node.spouses.contains(target)) return true;
    for (var child in node.children) {
      if (_searchInSpouseLists(child, target)) return true;
    }
    return false;
  }

  /// Recursively finds the parent for which [target] is a spouse.
  FamilyMember? getParentForSpouse(FamilyMember target, FamilyMember current) {
    if (current.spouses.contains(target)) return current;
    for (var child in current.children) {
      var res = getParentForSpouse(target, child);
      if (res != null) return res;
    }
    return null;
  }

  /// Recursively finds a member by [id].
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

  /// Modified addChild: if the selected node is not a main node and is the first spouse,
  /// add the child to the parent's children list (shared between main node and first spouse).
  void addChild(String parentId, FamilyMember child) {
    final FamilyMember? node = findMember(root, parentId);
    if (node != null) {
      if (!isMainNode(node)) {
        FamilyMember? mainParent = getParentForSpouse(node, root);
        if (mainParent != null &&
            mainParent.spouses.isNotEmpty &&
            mainParent.spouses[0] == node) {
          setState(() {
            mainParent.children.add(child);
          });
          return;
        }
      }
      setState(() {
        node.children.add(child);
      });
    }
  }

  /// Adds a spouse only to main nodes.
  void addSpouse(String memberId, FamilyMember spouse) {
    final member = findMember(root, memberId);
    if (member != null) {
      if (isMainNode(member)) {
        setState(() {
          member.spouses.add(spouse);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Only main nodes can add spouses.")),
        );
      }
    }
  }

  /// NEW: Adds a parent to a node (only allowed for non‑main nodes).
  void addParent(String memberId, FamilyMember parent) {
    final member = findMember(root, memberId);
    if (member != null) {
      if (!isMainNode(member)) {
        setState(() {
          member.parents.add(parent);
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cannot add parent to a main node.")),
        );
      }
    }
  }

  /// --- JSON Serialization and Local Storage ---
  String serializeTree() {
    return jsonEncode(root.toJson());
  }

  void loadTree(String jsonString) {
    Map<String, dynamic> map = jsonDecode(jsonString);
    setState(() {
      root = FamilyMember.fromJson(map);
      selectedMember = root;
    });
  }

  Future<void> _saveTree() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('family_tree', serializeTree());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Family tree saved locally.")),
    );
  }

  Future<void> _loadTreeFromStorage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? jsonString = prefs.getString('family_tree');
    if (jsonString != null) {
      loadTree(jsonString);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Family tree loaded from local storage.")),
      );
    }
  }

  /// Helper method to determine if a given node is a parent node.
  bool isParentNode(FamilyMember target) {
    bool found = false;
    void search(FamilyMember member) {
      if (member.parents.contains(target)) {
        found = true;
        return;
      }
      for (var spouse in member.spouses) {
        search(spouse);
        if (found) return;
      }
      for (var child in member.children) {
        search(child);
        if (found) return;
      }
    }

    search(root);
    return found;
  }

  /// Hit testing based on computed positions.
  FamilyMember? _hitTest(Offset point) {
    for (var member in positions.keys.toList().reversed) {
      final pos = positions[member];
      if (pos != null && (pos - point).distance <= nodeRadius) {
        return member;
      }
    }
    return null;
  }

  /// Returns a drawing order for hit testing.
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

  /// Shows a popup for a tapped node.
  void _showNodePopup(FamilyMember node) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(node.name),
          content: const Text("Choose an action:"),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            if (!isParentNode(node))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showAddChildDialog(node);
                },
                child: const Text("Add Child"),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showAddSpouseDialog(node);
              },
              child: const Text("Add Spouse"),
            ),
            if (!isMainNode(node))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showAddParentDialog(node);
                },
                child: const Text("Add Parents"),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showEditDialog(node);
              },
              child: const Text("Edit Node"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  void _showAddChildDialog(FamilyMember parent) {
    Gender selectedGender = Gender.male;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text("Add Child to ${parent.name}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Select Gender for new Child:"),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<Gender>(
                        title: const Text("Male"),
                        value: Gender.male,
                        groupValue: selectedGender,
                        onChanged: (value) {
                          setState(() {
                            selectedGender = value!;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<Gender>(
                        title: const Text("Female"),
                        value: Gender.female,
                        groupValue: selectedGender,
                        onChanged: (value) {
                          setState(() {
                            selectedGender = value!;
                          });
                        },
                      ),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final newId =
                      DateTime.now().millisecondsSinceEpoch.toString();
                  addChild(
                      parent.id,
                      FamilyMember(
                          id: newId, name: 'Child', gender: selectedGender));
                  Navigator.of(context).pop();
                },
                child: const Text("Add Child"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Cancel"),
              ),
            ],
          );
        });
      },
    );
  }

  void _showAddSpouseDialog(FamilyMember member) {
    if (!isMainNode(member)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Only main nodes can add spouses.")),
      );
      return;
    }
    Gender selectedGender = Gender.female;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: Text("Add Spouse to ${member.name}"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Select Gender for new Spouse:"),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<Gender>(
                        title: const Text("Male"),
                        value: Gender.male,
                        groupValue: selectedGender,
                        onChanged: (value) {
                          setState(() {
                            selectedGender = value!;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<Gender>(
                        title: const Text("Female"),
                        value: Gender.female,
                        groupValue: selectedGender,
                        onChanged: (value) {
                          setState(() {
                            selectedGender = value!;
                          });
                        },
                      ),
                    ),
                  ],
                )
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  final newId =
                      DateTime.now().millisecondsSinceEpoch.toString();
                  addSpouse(
                      member.id,
                      FamilyMember(
                          id: newId, name: 'Spouse', gender: selectedGender));
                  Navigator.of(context).pop();
                },
                child: const Text("Add Spouse"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Cancel"),
              ),
            ],
          );
        });
      },
    );
  }

  // NEW: Dialog to add Parents (a male and a female) to a non‑main (spouse) node.
  void _showAddParentDialog(FamilyMember node) {
    final TextEditingController maleController =
        TextEditingController(text: 'Male Parent');
    final TextEditingController femaleController =
        TextEditingController(text: 'Female Parent');
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Add Parents to ${node.name}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: maleController,
                decoration:
                    const InputDecoration(labelText: "Male Parent Name"),
              ),
              TextField(
                controller: femaleController,
                decoration:
                    const InputDecoration(labelText: "Female Parent Name"),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                final newIdMale =
                    DateTime.now().millisecondsSinceEpoch.toString() + "m";
                final newIdFemale =
                    DateTime.now().millisecondsSinceEpoch.toString() + "f";
                addParent(
                    node.id,
                    FamilyMember(
                        id: newIdMale,
                        name: maleController.text,
                        gender: Gender.male));
                addParent(
                    node.id,
                    FamilyMember(
                        id: newIdFemale,
                        name: femaleController.text,
                        gender: Gender.female));
                Navigator.of(context).pop();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  setState(() {});
                });
              },
              child: const Text("Add Parents"),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text("Cancel"),
            ),
          ],
        );
      },
    );
  }

  void _showEditDialog(FamilyMember node) {
    final TextEditingController nameController =
        TextEditingController(text: node.name);
    Gender selectedGender = node.gender;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            title: const Text("Edit Node"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Name"),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: const Text("Male"),
                        leading: Radio<Gender>(
                          value: Gender.male,
                          groupValue: selectedGender,
                          onChanged: (value) {
                            setState(() {
                              selectedGender = value!;
                            });
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListTile(
                        title: const Text("Female"),
                        leading: Radio<Gender>(
                          value: Gender.female,
                          groupValue: selectedGender,
                          onChanged: (value) {
                            setState(() {
                              selectedGender = value!;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() {
                    node.name = nameController.text;
                    node.gender = selectedGender;
                  });
                  Navigator.of(context).pop();
                  setState(() {}); // Refresh tree.
                },
                child: const Text("Save"),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text("Cancel"),
              ),
            ],
          );
        });
      },
    );
  }

  /// getZoomedNodes returns a pair [mainParent, selectedSpouse] if the selected node is non‑main.
  List<FamilyMember>? getZoomedNodes() {
    if (selectedMember != null && !isMainNode(selectedMember!)) {
      FamilyMember? mainParent = getParentForSpouse(selectedMember!, root);
      if (mainParent != null) {
        return [mainParent, selectedMember!];
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
    // Compute layout with root at (screenWidth/2, 60)
    computeLayout(root, screenWidth / 2, 60);

    // Zoom mode: if an added spouse is selected, use zoom mode.
    List<FamilyMember>? zoomedNodes = getZoomedNodes();
    if (zoomedNodes != null) {
      FamilyMember zoomSpouse = zoomedNodes[1];
      if (zoomSpouse.parents.length == 2 && positions.containsKey(zoomSpouse)) {
        Offset spousePos = positions[zoomSpouse]!;
        double parentY = spousePos.dy - 100; // increased vertical gap
        double spacing = 120; // increased horizontal spacing between parents
        Offset leftParentPos = Offset(spousePos.dx - spacing / 2, parentY);
        Offset rightParentPos = Offset(spousePos.dx + spacing / 2, parentY);
        // Draw avatars for both parents
        positions[zoomSpouse.parents[0]] = leftParentPos;
        positions[zoomSpouse.parents[1]] = rightParentPos;
      } else if (zoomSpouse.parents.isNotEmpty &&
          positions.containsKey(zoomSpouse)) {
        Offset spousePos = positions[zoomSpouse]!;
        double parentY = spousePos.dy - 60;
        int count = zoomSpouse.parents.length;
        double spacing = 40;
        double totalWidth = (count - 1) * spacing;
        double startX = spousePos.dx - totalWidth / 2;
        for (int i = 0; i < count; i++) {
          positions[zoomSpouse.parents[i]] =
              Offset(startX + i * spacing, parentY);
        }
      }
    }

    double minX = double.infinity, minY = double.infinity;
    double maxX = -double.infinity, maxY = -double.infinity;
    for (var pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx > maxX) maxX = pos.dx;
      if (pos.dy > maxY) maxY = pos.dy;
    }
    const double safeMargin = 100.0;
    final canvasWidth = (maxX - minX) + safeMargin * 2;
    final canvasHeight = (maxY - minY) + safeMargin * 2;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Dynamic Family Tree"),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTree,
            tooltip: "Save Tree",
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _loadTreeFromStorage,
            tooltip: "Load Tree",
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFF5F3E5),
        child: Stack(
          children: [
            InteractiveViewer(
              constrained: false,
              transformationController: _transformationController,
              boundaryMargin: const EdgeInsets.all(3000),
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
                    maleAvatar: maleAvatar,
                    femaleAvatar: femaleAvatar,
                    zoomedNodes: zoomedNodes,
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
                    _showNodePopup(tappedMember);
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
                _showAddChildDialog(selectedMember!);
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
                _showAddSpouseDialog(selectedMember!);
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
  final ui.Image? maleAvatar;
  final ui.Image? femaleAvatar;
  final List<FamilyMember>? zoomedNodes;

  FamilyTreePainter({
    required this.root,
    required this.positions,
    required this.effectiveRanges,
    required this.nodeRadius,
    this.selectedMember,
    this.maleAvatar,
    this.femaleAvatar,
    this.zoomedNodes,
  });

  final Paint linePaint = Paint()
    ..color = Colors.grey
    ..strokeWidth = 2
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (zoomedNodes != null) {
      _drawZoomMode(canvas, zoomedNodes![0], zoomedNodes![1]);
    } else {
      _drawConnectors(canvas, root);
      _drawNodes(canvas, root, <FamilyMember>{});
    }
  }

  void _drawZoomMode(
      Canvas canvas, FamilyMember zoomMain, FamilyMember zoomSpouse) {
    _drawAvatar(canvas, positions[zoomMain]!, zoomMain.name,
        zoomMain == selectedMember, zoomMain.gender);
    if (zoomMain.spouses.contains(zoomSpouse)) {
      Offset spousePos = positions[zoomSpouse]!;
      double offsetY = 4.0 * zoomMain.spouses.indexOf(zoomSpouse);
      final Offset start = Offset(positions[zoomMain]!.dx + nodeRadius,
          positions[zoomMain]!.dy - offsetY);
      final Offset end =
          Offset(spousePos.dx - nodeRadius, spousePos.dy - offsetY);
      canvas.drawLine(start, end, linePaint);
      Offset linkIcon =
          Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
      _drawLinkIcon(canvas, linkIcon, linePaint.color);
      _drawAvatar(canvas, spousePos, zoomSpouse.name,
          zoomSpouse == selectedMember, zoomSpouse.gender);
      if (zoomSpouse.parents.length == 2) {
        // New drawing logic for paired parents with increased horizontal spacing
        double parentY = spousePos.dy - 100; // increased vertical gap
        double spacing = 120; // increased horizontal spacing between parents
        Offset leftParentPos = Offset(spousePos.dx - spacing / 2, parentY);
        Offset rightParentPos = Offset(spousePos.dx + spacing / 2, parentY);
        // Draw avatars for both parents
        _drawAvatar(canvas, leftParentPos, zoomSpouse.parents[0].name, false,
            zoomSpouse.parents[0].gender);
        _drawAvatar(canvas, rightParentPos, zoomSpouse.parents[1].name, false,
            zoomSpouse.parents[1].gender);
        // Draw horizontal line connecting the two parent's avatars
        Offset leftEdge =
            Offset(leftParentPos.dx + nodeRadius, leftParentPos.dy);
        Offset rightEdge =
            Offset(rightParentPos.dx - nodeRadius, rightParentPos.dy);
        canvas.drawLine(leftEdge, rightEdge, linePaint);
        // Draw link icon at the midpoint of the horizontal line
        Offset midPoint = Offset((leftEdge.dx + rightEdge.dx) / 2, leftEdge.dy);
        _drawLinkIcon(canvas, midPoint, linePaint.color);
        // Draw vertical line from the midpoint to the spouse's top
        Offset spouseTop = Offset(spousePos.dx, spousePos.dy - nodeRadius);
        canvas.drawLine(midPoint, spouseTop, linePaint);
      } else if (zoomSpouse.parents.isNotEmpty) {
        double parentY = spousePos.dy - 60;
        int count = zoomSpouse.parents.length;
        double spacing = 40;
        double totalWidth = (count - 1) * spacing;
        double startX = spousePos.dx - totalWidth / 2;
        for (int i = 0; i < count; i++) {
          Offset parentPos = Offset(startX + i * spacing, parentY);
          _drawAvatar(canvas, parentPos, zoomSpouse.parents[i].name, false,
              zoomSpouse.parents[i].gender);
          final Offset parentBottom =
              Offset(parentPos.dx, parentPos.dy + nodeRadius);
          final Offset spouseTop =
              Offset(spousePos.dx, spousePos.dy - nodeRadius);
          canvas.drawLine(parentBottom, spouseTop, linePaint);
        }
      }
      if (zoomMain.children.isNotEmpty) {
        _drawChildrenConnectors(canvas, zoomMain,
            baseConnectorOverride: linkIcon);
        for (var child in zoomMain.children) {
          _drawConnectors(canvas, child);
          _drawNodes(canvas, child, <FamilyMember>{});
        }
      }
    }
  }

  void _drawChildrenConnectors(Canvas canvas, FamilyMember member,
      {Offset? baseConnectorOverride}) {
    final Offset baseConnector = baseConnectorOverride ?? positions[member]!;
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
    double joinX = baseConnector.dx;
    if (joinX < leftX)
      joinX = leftX;
    else if (joinX > rightX) joinX = rightX;
    Offset joinPoint = Offset(joinX, childConnectorY);
    if (baseConnector.dx == joinX) {
      canvas.drawLine(baseConnector, joinPoint, linePaint);
    } else {
      double midY = childConnectorY - stubLength;
      canvas.drawLine(baseConnector, Offset(baseConnector.dx, midY), linePaint);
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

  void _drawConnectors(Canvas canvas, FamilyMember member,
      {Offset? connectorOrigin}) {
    final Offset nodeOrigin = connectorOrigin ?? positions[member]!;
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
          late Offset spouseConnectorOrigin;
          if (i == 0) {
            spouseConnectorOrigin =
                Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
            _drawLinkIcon(canvas, spouseConnectorOrigin, linePaint.color);
          } else {
            spouseConnectorOrigin =
                Offset(spousePos.dx - nodeRadius - 30, spousePos.dy - offsetY);
            _drawLinkIcon(canvas, spouseConnectorOrigin, linePaint.color);
          }
          _drawConnectors(canvas, spouse,
              connectorOrigin: spouseConnectorOrigin);
        }
      }
    }
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
      double leftX, rightX;
      if (effectiveRanges.containsKey(member)) {
        final range = effectiveRanges[member]!;
        leftX = range.left;
        rightX = range.right;
      } else {
        leftX = positions[member.children.first]!.dx;
        rightX = positions[member.children.last]!.dx;
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
    for (var child in member.children) {
      _drawConnectors(canvas, child);
    }
  }

  void _drawNodes(
      Canvas canvas, FamilyMember member, Set<FamilyMember> visited) {
    if (visited.contains(member)) return;
    visited.add(member);
    final Offset? pos = positions[member];
    if (pos == null) return;
    _drawAvatar(
        canvas, pos, member.name, member == selectedMember, member.gender);
    for (var spouse in member.spouses) {
      _drawNodes(canvas, spouse, visited);
    }
    for (var child in member.children) {
      _drawNodes(canvas, child, visited);
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

  void _drawAvatar(Canvas canvas, Offset center, String label, bool isSelected,
      Gender gender) {
    final Paint bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(center, nodeRadius, bgPaint);
    if (isSelected) {
      final Paint borderPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, nodeRadius + 2, borderPaint);
    }
    ui.Image? avatarImage;
    if (gender == Gender.male && maleAvatar != null) {
      avatarImage = maleAvatar;
    } else if (gender == Gender.female && femaleAvatar != null) {
      avatarImage = femaleAvatar;
    }
    if (avatarImage != null) {
      final Rect dstRect = Rect.fromCenter(
          center: center, width: nodeRadius * 2, height: nodeRadius * 2);
      canvas.save();
      canvas.clipPath(Path()..addOval(dstRect));
      final Rect srcRect = Rect.fromLTWH(
          0, 0, avatarImage.width.toDouble(), avatarImage.height.toDouble());
      canvas.drawImageRect(avatarImage, srcRect, dstRect, Paint());
      canvas.restore();
    } else {
      IconData iconData;
      Color iconColor;
      if (gender == Gender.male) {
        iconData = Icons.male;
        iconColor = Colors.blue;
      } else {
        iconData = Icons.female;
        iconColor = Colors.pink;
      }
      final TextSpan iconSpan = TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          fontSize: 20,
          color: iconColor,
        ),
      );
      final TextPainter iconPainter = TextPainter(
        text: iconSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      iconPainter.layout();
      final Offset iconOffset = Offset(center.dx - iconPainter.width / 2,
          center.dy - iconPainter.height / 2);
      iconPainter.paint(canvas, iconOffset);
    }
    final TextSpan labelSpan = TextSpan(
      text: label,
      style: const TextStyle(color: Colors.black, fontSize: 8),
    );
    final TextPainter labelPainter = TextPainter(
      text: labelSpan,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    labelPainter.layout();
    final Offset labelOffset =
        Offset(center.dx - labelPainter.width / 2, center.dy + nodeRadius + 2);
    labelPainter.paint(canvas, labelOffset);
  }

  @override
  bool shouldRepaint(covariant FamilyTreePainter oldDelegate) {
    // Always repaint so that changes in the mutable maps are visible immediately.
    return true;
  }
}
