import 'package:flutter/material.dart';

class WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();

    
    path.moveTo(0, size.height * 0.4);
   
    path.quadraticBezierTo(
      size.width * 0.25, // Control point x
      size.height * 0.1, // Control point y (puncak gelombang)
      size.width * 0.5, // End point x
      size.height * 0.35, // End point y
    );
    
    path.quadraticBezierTo(
      size.width * 0.75, // Control point x
      size.height * 0.6, // Control point y (lembah gelombang)
      size.width, // End point x
      size.height * 0.2, // End point y
    );
    
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
