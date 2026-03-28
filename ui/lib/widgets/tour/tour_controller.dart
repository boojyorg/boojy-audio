import 'package:flutter/foundation.dart';
import 'tour_step.dart';

/// State machine for the guided tour.
/// Controls step progression, skip, and completion.
class TourController extends ChangeNotifier {
  final List<TourStep> steps;
  int _currentIndex = 0;
  bool _isActive = false;

  TourController({required this.steps});

  bool get isActive => _isActive;
  int get currentIndex => _currentIndex;
  TourStep get currentStep => steps[_currentIndex];
  int get totalSteps => steps.length;
  bool get isLastStep => _currentIndex >= steps.length - 1;

  void start() {
    _isActive = true;
    _currentIndex = 0;
    notifyListeners();
  }

  void next() {
    if (_currentIndex < steps.length - 1) {
      _currentIndex++;
      notifyListeners();
    } else {
      complete();
    }
  }

  void skip() {
    _isActive = false;
    notifyListeners();
  }

  void complete() {
    _isActive = false;
    notifyListeners();
  }
}
