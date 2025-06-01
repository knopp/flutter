// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

void showRegularWindowEditDialog(
  BuildContext context, {
  double? initialWidth,
  double? initialHeight,
  String? initialTitle,
  Function(double?, double?, String?)? onSave,
}) {
  final TextEditingController widthController =
      TextEditingController(text: initialWidth?.toString() ?? '');
  final TextEditingController heightController =
      TextEditingController(text: initialHeight?.toString() ?? '');
  final TextEditingController titleController = TextEditingController(text: initialTitle ?? '');

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text("Edit Window Properties"),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Width"),
                ),
                TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: "Height"),
                ),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(labelText: "Title"),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              double? width = double.tryParse(widthController.text);
              double? height = double.tryParse(heightController.text);
              String? title = titleController.text.isEmpty ? null : titleController.text;

              onSave?.call(width, height, title);
              Navigator.of(context).pop();
            },
            child: Text("Save"),
          ),
        ],
      );
    },
  );
}
