//
// Common array type deduction
// https://d.puremagic.com/issues/show_bug.cgi?id=5498
//
//
import std.stdio;
import std.range;
import std.traits;
import std.conv;

public class Animal { }
public class Dog : Animal { }
public class Cat : Animal { }

//
// IFTI Constructors
// https://d.puremagic.com/issues/show_bug.cgi?id=6082
//



template ElementTypeWrapper(T)
{
  alias ElementTypeWrapper = ElementType!T;
}

void main()
{
  //Animal[] animals = [new Dog(), new Cat()];
}
