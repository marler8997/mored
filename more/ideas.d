/***

A string iterator

Example:
  auto s = "t{able|ree|uck}"
  foreach(result; generator(s)) {
    // will have "table", then "tree", then "truck"
  }

Note: if '|' and '{' '}' are at the same depth, the curly braces
      are expanded first, and then the '| is evaluated so the following:
      "1|2{3|4}"
        "1"
        "23"
        "24"

*/



//
// Permutation Stuff





  // return false if no more permutations
  bool nextPermutation(ref size_t[] permutation, size_t max) {
    size_t off = permutation.length - 1;
    while(true) {
      if(permutation[off] < max) {
	permutation[off]++;
	return true;
      }
      permutation[off] = 0;
      if(off == 0) return false;
      off--;
    }
  }

  struct Permuter {
    string[] elements;
    size_t[] fullPermutationIndexBuffer;

    private size_t[] currentPermutationBuffer;
    bool isEmpty;

    this(string[] elements, size_t[] fullPermutationIndexBuffer) {
      this.elements = elements;
      this.fullPermutationIndexBuffer = fullPermutationIndexBuffer;

      this.currentPermutationBuffer = fullPermutationIndexBuffer[0..1];
      this.currentPermutationBuffer[] = 0;
    }

    bool empty() { return isEmpty; }
    void putInto(ref WriteBuffer!char buffer) {
      foreach(idx; currentPermutationBuffer) {
	buffer.put(elements[idx]);
      }
    }
    void popFront() {
      bool isNowEmpty = !nextPermutation(this.currentPermutationBuffer, elements.length - 1);
      if(isNowEmpty) {
	if(currentPermutationBuffer.length >= fullPermutationIndexBuffer.length) {
	  this.isEmpty = true;
	} else {
	  currentPermutationBuffer.length++;
	  currentPermutationBuffer[] = 0;
	}
      }
    }
  }
