/// Fixed-capacity FIFO buffer for recent audio-analysis frames. Fail-closed
/// on a misconfigured (zero or negative) capacity: it silently accepts and
/// discards pushes rather than throwing, since a capacity bug should not be
/// able to crash a live audio-processing session.
class TransientBuffer<T> {
  TransientBuffer({required int capacity}) : capacity = capacity < 0 ? 0 : capacity;

  final int capacity;
  final _items = <T>[];

  List<T> get items => List.unmodifiable(_items);

  int get length => _items.length;

  void push(T item) {
    if (capacity == 0) return;
    _items.add(item);
    while (_items.length > capacity) {
      _items.removeAt(0);
    }
  }
}
