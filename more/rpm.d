import std.stdio;
import std.string : indexOf, lastIndexOf;
import std.algorithm : cmp;
import std.conv : to;

/**
   The rpm filename is name-epoch:version-release.arch.rpm
*/
struct Rpm
{
  const(char)[] filename;
  const(char)[] name;

  const(char)[] evr;
  ushort epoch;
  const(char)[] version_;
  const(char)[] release;

  const(char)[] arch;

  this(const(char)[] filename)
  {
    this.filename = filename;

    //
    // Remove the .rpm
    //
    if(filename[$-4..$] == ".rpm") {
      filename = filename[0..$-4];
    }

    //
    // Get the arch
    //
    {
      auto lastDotIndex = filename.lastIndexOf('.');
      if(lastDotIndex >= 0) {
        this.arch = filename[lastDotIndex+1..$];
        if(isValidArch(this.arch)) {
          filename = filename[0..lastDotIndex];
        } else {
          this.arch = null;
        }
      }
    }

    auto firstDashIndex = filename.indexOf('-');
    if(firstDashIndex < 0) {
      this.name = filename;
    } else {

      this.name = filename[0..firstDashIndex];
      this.evr = filename[firstDashIndex+1..$];

      // Try to get the epoch
      {
        auto colonIndex = evr.indexOf(':');
        if(colonIndex >= 0) {
          this.epoch = to!ushort(evr[0..colonIndex]);
          this.version_ = evr[colonIndex+1..$];
        } else {
          this.version_ = evr;
        }
      }

      // Try to get the release
      {
        auto releaseDashIndex = version_.indexOf('-');
        if(releaseDashIndex >= 0) {
          release = version_[releaseDashIndex+1..$];
          version_ = version_[0..releaseDashIndex];
        }
      }
    }
  }

  // Returns: -1 if this is less than other, 0 if they are equal, 1 if this is greater than other
  int opCmp(ref const Rpm other) const
  {
    if(this.epoch != other.epoch)
      return (this.epoch > other.epoch) ? 1 : -1;

    if(this.version_.length == 0) {
      if(other.version_.length != 0) {
        return -1;
      }
    } else {
      auto result = Rpm.cmp(this.version_, other.version_);
      if(result != 0) return result;
    }

    if(this.release.length == 0) {
      if(other.release.length != 0) {
        return -1;
      }
    } else {
      auto result = Rpm.cmp(this.release, other.release);
      if(result != 0) return result;
    }

    return 0;
  }
  unittest
  {
    auto one = Rpm("rpm-1.0-0.i386.rpm");
    auto two = Rpm("rpm-1.1-0.i386.rpm");
    auto three = Rpm("rpm-1.2-0.i386.rpm");

    assert(one < two);
    assert(one < three);
    assert(two > one);
    assert(two < three);
    assert(three > one);
    assert(three > two);

    auto rpms = [one, two, three];
    rpms.sort;
    assert(rpms[0].evr == "1.0-0");
    assert(rpms[1].evr == "1.1-0");
    assert(rpms[2].evr == "1.2-0");
    rpms = [one, three, two];
    rpms.sort;
    assert(rpms[0].evr == "1.0-0");
    assert(rpms[1].evr == "1.1-0");
    assert(rpms[2].evr == "1.2-0");
    rpms = [two, one, three];
    rpms.sort;
    assert(rpms[0].evr == "1.0-0");
    assert(rpms[1].evr == "1.1-0");
    assert(rpms[2].evr == "1.2-0");
    rpms = [two, three, one];
    rpms.sort;
    assert(rpms[0].evr == "1.0-0");
    assert(rpms[1].evr == "1.1-0");
    assert(rpms[2].evr == "1.2-0");
    rpms = [three, one, two];
    rpms.sort;
    assert(rpms[0].evr == "1.0-0");
    assert(rpms[1].evr == "1.1-0");
    assert(rpms[2].evr == "1.2-0");

    one = Rpm("rpm.rpm");
    two = Rpm("rpm-0.rpm");
    assert(one < two);
    assert(two > one);
  }

  void toString(scope void delegate(const(char)[] msg) sink)
  {
    sink("Rpm(\"");
    sink(name);
    sink("\"");
    if(epoch > 0) {
      sink(", epoch=");
      sink(to!string(epoch));
    }
    if(version_ !is null) {
      sink(", ver=");
      sink(version_);
    }
    if(release !is null) {
      sink(", release=");
      sink(release);
    }
    if(release !is null) {
      sink(", arch=");
      sink(arch);
    }
    sink(")");
  }

  bool isValidArch(const(char)[] arch)
  {
    bool containsLetter = false;
    foreach(i, c; arch) {
      if(c >= 'a') {
        if(c <= 'z') {
          containsLetter = true;
          continue;
        }
        return false;
      }
      if(
         (c <= '9' && c >= '0') ||
         (c == '_')
         ) continue;
      return false;
    }
    return containsLetter;
  }

  /** compare alpha and numeric segments of two versions
      return 1: a is newer than b
      0: a and b are the same version
      -1: b is newer than a */
  static int cmp(const char[] a, const char[] b)
  {
    import std.ascii : isAlphaNum, isDigit, isAlpha;

    // easy comparison to see if versions are identical
    if(a == b) return 0;

    auto one      = a.ptr;
    auto oneLimit = one + a.length;
    auto two      = b.ptr;
    auto twoLimit = two + b.length;
    
    // loop through each version segment of str1 and str2 and compare them
    while(true) {

      // Skip non-alpha-num characters
      while(one < oneLimit && !isAlphaNum(*one))
        one++;
      while(two < twoLimit && !isAlphaNum(*two))
        two++;

      if(one >= oneLimit)
        return (two >= twoLimit) ? 0 : -1;
      if(two >= twoLimit)
        return 1;

      auto str1 = one;
      auto str2 = two;

      // grab first completely alpha or completely numeric segment
      // leave one and two pointing to the start of the alpha or numeric
      // segment and walk str1 and str2 to end of segmen
      if (isDigit(*str1)) {

        if(!isDigit(*str2))
          return 1; // digits are newer than alpha chars

        do { str1++; } while(str1 < oneLimit && isDigit(*str1));
        do { str2++; } while(str2 < twoLimit && isDigit(*str2));

        /* throw away any leading zeros - it's a number, right? */
        while (*one == '0') { one++; if(one >= oneLimit) break;}
        while (*two == '0') { two++; if(two >= twoLimit) break;}

        auto oneLength = str1 - one;
        auto twoLength = str2 - two;

        /* whichever number has more digits wins */
        if (oneLength > twoLength) return 1;
        if (twoLength > oneLength) return -1;

        /* they have the same number of digits */
        while(one < str1) {
          if(*one > *two) return 1;
          if(*two > *one) return -1;
          one++;
          two++;
        }

      } else {

        if(isDigit(*str2))
          return -1; // digits are newer than alpha chars

        do { str1++; } while(str1 < oneLimit && isAlpha(*str1));
        do { str2++; } while(str2 < twoLimit && isAlpha(*str2));

        auto cmpResult = std.algorithm.cmp(one[0..str1-one], two[0..str2-two]);
        if(cmpResult != 0) return -cmpResult;
        one = str1;
        two = str2;
      }

    }
  }
  unittest
  {
    assert(Rpm.cmp(null, null) == 0);
    assert(Rpm.cmp("", "") == 0);

    assert(Rpm.cmp("", "0") < 0);
    assert(Rpm.cmp("0", "") > 0);

    assert(Rpm.cmp("0", "0") == 0);

    assert(Rpm.cmp("0", "a") > 0);
    assert(Rpm.cmp("a", "0") < 0);

    assert(Rpm.cmp("0", "1") < 0);
    assert(Rpm.cmp("1", "0") > 0);

    assert(Rpm.cmp("01", "1") == 0);
    assert(Rpm.cmp("001", "1") == 0);
    assert(Rpm.cmp("1", "01") == 0);
    assert(Rpm.cmp("1", "001") == 0);

    assert(Rpm.cmp("9", "10") < 0);
    assert(Rpm.cmp("10", "9") > 0);

    assert(Rpm.cmp("a", "a") == 0);
    assert(Rpm.cmp("abc", "abc") == 0);
    assert(Rpm.cmp("a", "b") > 0);

    assert(Rpm.cmp("b", "a") < 0);
    assert(Rpm.cmp("aa", "ab") > 0);
    assert(Rpm.cmp("ab", "aa") < 0);

    assert(Rpm.cmp("0.a", "0.a") == 0);
    assert(Rpm.cmp("0.a", "0.b") > 0);
    assert(Rpm.cmp("0.b", "0.a") < 0);

    assert(Rpm.cmp("1.2.3.A", "1.2.3.B") > 0);
    assert(Rpm.cmp("1.2.3.B", "1.2.3.A") < 0);

    assert(Rpm.cmp("abc.def.efg", "abc.def.efg") == 0);
    assert(Rpm.cmp("abc.def.ef1", "abc.def.ef0") > 0);
    assert(Rpm.cmp("abc.def.ef0", "abc.def.ef1") < 0);
  }
}
