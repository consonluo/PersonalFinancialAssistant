import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/utils/ocr_parser.dart';

/// OCR 识别状态
final ocrResultProvider =
    StateNotifierProvider<OcrResultNotifier, OcrState>((ref) {
  return OcrResultNotifier();
});

class OcrState {
  final bool isProcessing;
  final List<ParsedHolding> results;
  final String? errorMessage;

  const OcrState({
    this.isProcessing = false,
    this.results = const [],
    this.errorMessage,
  });

  OcrState copyWith({
    bool? isProcessing,
    List<ParsedHolding>? results,
    String? errorMessage,
  }) {
    return OcrState(
      isProcessing: isProcessing ?? this.isProcessing,
      results: results ?? this.results,
      errorMessage: errorMessage,
    );
  }
}

class OcrResultNotifier extends StateNotifier<OcrState> {
  OcrResultNotifier() : super(const OcrState());

  void setProcessing() {
    state = state.copyWith(isProcessing: true, errorMessage: null);
  }

  void setResults(List<ParsedHolding> results) {
    state = OcrState(results: results);
  }

  void setError(String message) {
    state = OcrState(errorMessage: message);
  }

  void updateResult(int index, ParsedHolding updated) {
    final newResults = List<ParsedHolding>.from(state.results);
    newResults[index] = updated;
    state = state.copyWith(results: newResults);
  }

  void removeResult(int index) {
    final newResults = List<ParsedHolding>.from(state.results);
    newResults.removeAt(index);
    state = state.copyWith(results: newResults);
  }

  void clear() {
    state = const OcrState();
  }
}
