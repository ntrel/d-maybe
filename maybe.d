/* Written in the D programming language.
 * Copyright Nick Treleaven 2012.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at
 * http://www.boost.org/LICENSE_1_0.txt)
 * 
 * Maintained at: http://github.com/ntrel/d-maybe
 */
import std.stdio;
import std.typecons;

private template MaybeValue(T)
{
    // are there any other invalid values?
    static if (is(typeof(T.init == null)))
        alias Nullable!(T, null) MaybeValue;
    else
    static if (is(typeof(T.init == T.nan)))
        alias Nullable!(T, T.nan) MaybeValue;
    else
        alias Nullable!T MaybeValue;
}

/** Contains either a value or nothing, guaranteeing the value is not dereferenced if null.
 * Note: The abstraction can be circumvented using e.g. Maybe.valueOr(null), but at least
 * this is explicit. */
// similar to Haskell's Maybe or Scala's Option but without OOP or monads.
struct Maybe(T)
{
    //~ pragma(msg, MaybeValue!T);
    private MaybeValue!T val;
    
    this(T val)
    {
        this.val = val;
    }
    
    void opAssign(T val)
    {
        this.val = val;
    }
        
    // should we allow m to be Maybe!U if is(U:T)?
    void opAssign(Maybe!T m)
    {
        this.val = m.val;
    }
        
    void opAssign(typeof(null))
    {
        val.nullify();
    }
    
    bool opEquals(Maybe!T m)
    {
        if (m == null && this == null)
            return true;
        if (m != null && this != null && m.val == this.val)
            return true;
        return false;
    }
    
    bool opEquals(typeof(null))
    {
        return val.isNull;
    }
    
    // should we use delegate(scope T) to prevent escaping or is that too strict? 
    /** Calls fun if the Maybe value is not null.
     * Returns: Whether fun was called or not. */
    bool attempt(void delegate(T) fun)
    {
        if (val.isNull)
            return false;
        fun(val.get);
        return true;
    }

    /** Calls fun, returning the result as a Maybe value. */
    Maybe!U map(U)(U delegate(T) fun)
    {
        Maybe!U m;
        if (!val.isNull)
            m = fun(val.get);
        return m;
    }
    
    /** Returns a copy of this Maybe object unless pred(value) is false. */
    Maybe!T filter(bool delegate(T) pred)
    {
        Maybe!T m;
        if (this != null && pred(val.get))
            m = this;
        return m;
    }
    
    /** Converts the Maybe value into a T.
     * Params: invalid_value = value to use if this == null.
     * Note: It's safer to use the other methods instead if possible.
     * invalid_value can be null, but at least the user is reminded of it:
     * ---
     * Maybe!Object m = ...;
     * Object w = m.valueOr(alternativeObject);
     * Object v = m.valueOr(null); */
    // Note: this is called Option::getOrElse in Scala
    T valueOr(T invalid_value)
    {
        return val.isNull ? invalid_value : val.get;
    }
}

auto maybe(T)(T val)
{
    return Maybe!T(val);
}

// test attempt
void show(M)(M m)
{
    if (!m.attempt(v => writeln(v)))
        writeln("No value");
}

void main(string[] args)
{
    // test with int, filter, valueOr
    Maybe!int m;
    assert(m == null);
    m = 7;
    assert(m.valueOr(-1) == 7);
    m.show();
    m.filter(x => x != 7).show();
    m = null;
    assert(m == null);
    writeln(m.valueOr(-1));
    m = maybe(6);
    assert(m.valueOr(-1) == 6);
    m.filter(x => x != 0).show();

    // test map
    // map type inference for both T and U causes dmd 2.059 to abort!
    //~ auto m2 = m.map(i => i * 2);
    auto m2 = m.map((int i) => i * 2);
    assert(m2 == m.map!int(i => i * 2));
    assert(m2.valueOr(-1) == 12);
    auto j = maybe(7).map((int i) => i * 0.5);
    assert(is(typeof(j) == Maybe!double));
    assert(j != null);
    assert(j.valueOr(-1) == 3.5);
    j.show();
    j = 0.2;
    assert(j.valueOr(-1) == 0.2);
    
    auto r = maybe(args);
    r.attempt(v => writeln(v[0]));
    r = null;
    assert(r == null);
    r.show();
    r.valueOr(null).writeln();
    
    // test with Object and opEquals
    Maybe!Object o;
    assert(o == null);
    o = new Object();
    assert(o != null);
    o = o.filter(x => true);
    assert(o != null);
    auto o2 = o;
    assert(o == o2);
    o2 = new Object();
    assert(o != o2);
    o2 = null;
    assert(o != o2);
    o = null;
    assert(o == null);
    assert(o == o2);
    
    writeln("Testing floating point null:");
    Nullable!(double, double.nan) n;
    double d = n;
    assert(d is double.nan); //ok
    assert(n.isNull); // fails because nan is compared with '=='
    maybe(d).show();
    assert(maybe(d) == null); // fails due to Nullable with nan
}

