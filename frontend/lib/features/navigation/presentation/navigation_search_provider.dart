import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/repositories/navigation_repository.dart';
import '../../navigation/data/repositories/navigation_repository_impl.dart';

class NavigationSearchState {
  final String query;
  final List<String> suggestions;
  final bool isLoading;
  final String? selectedDestination;

  NavigationSearchState({
    this.query = '',
    this.suggestions = const [],
    this.isLoading = false,
    this.selectedDestination,
  });

  NavigationSearchState copyWith({
    String? query,
    List<String>? suggestions,
    bool? isLoading,
    String? selectedDestination,
  }) {
    return NavigationSearchState(
      query: query ?? this.query,
      suggestions: suggestions ?? this.suggestions,
      isLoading: isLoading ?? this.isLoading,
      selectedDestination: selectedDestination ?? this.selectedDestination,
    );
  }
}

class NavigationSearchNotifier extends StateNotifier<NavigationSearchState> {
  final NavigationRepository _repository;

  NavigationSearchNotifier(this._repository) : super(NavigationSearchState());

  Future<void> updateQuery(String query) async {
    state = state.copyWith(query: query, isLoading: query.isNotEmpty);
    if (query.isEmpty) {
      state = state.copyWith(suggestions: [], isLoading: false);
      return;
    }
    
    try {
      final results = await _repository.searchPlaces(query);
      state = state.copyWith(suggestions: results, isLoading: false);
    } catch (e) {
      state = state.copyWith(suggestions: [], isLoading: false);
    }
  }

  void selectDestination(String destination) {
    state = state.copyWith(
      selectedDestination: destination,
      query: destination,
      suggestions: [],
    );
  }

  void clearSearch() {
    state = NavigationSearchState();
  }
}

final navigationSearchProvider = StateNotifierProvider<NavigationSearchNotifier, NavigationSearchState>((ref) {
  final repo = ref.watch(navigationRepositoryProvider);
  return NavigationSearchNotifier(repo);
});
