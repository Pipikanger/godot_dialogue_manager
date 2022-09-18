---
name: Bug report
about: Create a report to help us improve
title: 'Crashes when clicking outside options for a branch dialogue'
labels: bug
assignees: nathanhoad

---

**Describe the bug**
For a branch dialogue with options, it crashes when clicking anywhere outside of the options (or press any key when the text is still running).
I'm still pretty new to Godot and could not figure out the fix myself.
Godot Engine Version: Godot v4.0.Beta1
Dialogue Manager Version: v2.1.1

**To Reproduce**
Steps to reproduce the behavior:

1. Open the portraits_scene from the provided test_scenes, skip to the branch dialogue.
2. Click anywhere outside of the options, or press any key while the text is still running.
3. Crashes with error: Invalid get index 'type' (on base: 'Dictionary')

**Expected behavior**
Should just pass, or while the text is still running, clicking and pressing key allows you to skip to display the full text immediately.

**Screenshots**
If applicable, add screenshots to help explain your problem.
