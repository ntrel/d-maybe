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
import std.traits;

private template hasNullInit(T)
{
    enum hasNullInit =
        is(typeof(T.init == null)) || is(typeof(T.init == T.nan));
}

private template MaybeValue(T)
{
    /* Are there any other invalid values?
     * What about user defined types? */
    static if (hasNullInit!T)
        alias Nullable!(T, T.init) MaybeValue;
    else
        alias Nullable!T MaybeValue;
}

/** Contains either a value or nothing, guaranteeing the value is not accessible if invalid.
 * Note: The abstraction can be circumvented using e.g. Maybe.valueOr(null), but at least
 * this is explicit. */
// similar to Haskell's Maybe or Scala's Option but without OOP or monads.
struct Maybe(T)
{
    alias T Type;
    
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
    
    bool opEquals(T v)
    {
        Maybe!T m = v;
        return this == m;
    }
    
    bool opEquals(Maybe!T m)
    {
        if (m == null && this == null)
            return !is(typeof(T.init == T.nan)); // preserve nan != nan
        return (m != null && this != null && m.val == this.val);
    }
    
    unittest
    {
        // if this fails, remove opEquals workaround
        assert(!Nullable!(float, float.nan)().isNull);
    }
    
    bool opEquals(typeof(null))
    {
        // workaround as Nullable.isNull doesn't use 'is' for nan
        static if (hasNullInit!T)
            return val.isNull || val.get is T.init;
        else
            return val.isNull;
    }
    
    /* We should probably use delegate(scope T) everywhere to prevent
     * escaping, but that doesn't compile with dmd 2.059 */
    /** Calls fun if the Maybe value is valid.
     * Returns: Whether fun was called or not. */
    bool attempt(scope void delegate(T) fun)
    {
        if (this == null)
            return false;
        fun(val.get);
        return true;
    }

    /** Attempts to call fun, wrapping the result as a Maybe. */
    Maybe!U map(U)(scope U delegate(T) fun)
    {
        Maybe!U m;
        if (this != null)
            m = fun(val.get);
        return m;
    }
    
    /** Returns a copy of the Maybe struct if pred returns true, or
     * an invalid Maybe struct if pred returns false. */
    Maybe!T filter(scope bool delegate(T) pred)
    {
        Maybe!T m;
        if (this != null && pred(val.get))
            m = this;
        return m;
    }
    
    /** Converts the Maybe value into a T, returning invalid_value if invalid.
     * The argument can be null, but at least the user is reminded of it:
     * ---
     * Maybe!Object m = ...;
     * Object w = m.valueOr(alternativeObject);
     * Object v = m.valueOr(null);
     * ---
     * Params: invalid_value = Value to return if the Maybe value is invalid.
     * Note: It's safer to avoid using valueOr if possible.
     */
    // Note: this is called Option::getOrElse in Scala
    T valueOr(T invalid_value)
    {
        return this == null ? invalid_value : val.get;
    }
    
    static if (is(ForeachType!T FT))
        alias FT ElementType;

    int opApply()(scope int delegate(ref ElementType) dg)
        if (is(ElementType))
    {
        return opApply((ref i, ref e)=>dg(e));
    }

    // foreach inference doesn't work and size_t seems to need ref with dmd 2.059
    int opApply()(scope int delegate(ref size_t, ref ElementType) dg)
        if (is(ElementType))
    {
        if (this == null)
            return 0;
        int res;
        size_t i;
        foreach(e; val)
        {
            res = dg(i, e);
            if (res)
                break;
            i++;
        }
        return res;
    }
}

auto maybe(T)(T val)
{
    return Maybe!T(val);
}

template isMaybe(M)
{
    static if (is(M.Type))
        enum isMaybe = is(M == Maybe!(M.Type));
    else
        enum isMaybe = false;
}

import std.range;
import std.conv;

private string argString(Args...)()
{
    string s;
    foreach (i, Arg; Args)
    {
        if (!s.empty)
            s ~= ", ";
        s ~= "args[" ~ to!string(i) ~ "]";
        
        static if (isMaybe!(Arg))
            s ~= ".val";
    }
    return s;
}

private bool allValid(Args...)(Args args)
{
    foreach (arg; args)
    {
        static if (isMaybe!(typeof(arg)))
            if (arg == null)
                return false;
    }
    return true;
}

private template applyCode(Args...)
{
    enum applyCode = "fun(" ~ argString!Args() ~ ");";
}

/** Calls fun if all Maybe instances in args are valid.
 * Returns: The result of fun, if any, wrapped in a Maybe. */
auto apply(alias fun, Args...)(Args args)
    if (is(typeof({mixin(applyCode!Args);})))
{
    // remove semicolon from applyCode so lambda can return a value
    alias typeof((()=>mixin(applyCode!Args[0..$-1]))()) Ret;
    static if (is(Ret == void))
    {
        if (allValid(args))
            mixin(applyCode!Args);
    }
    else
    {
        Maybe!Ret result;
        if (allValid(args))
            mixin("result = " ~ applyCode!Args);
        return result;
    }
}

unittest
{
    assert(apply!((int x) => 2*x)(maybe(5)) == 10);
    assert(apply!text(maybe("hi"), 5) == "hi5");
    assert(apply!text(6, Maybe!string()) == null);
    assert(text(7, '!') == "7!");
    //~ assert(apply!text(maybe(7), '!') == "7!"); // error with dmd 2.059
    //~ assert(apply!text(Maybe!int(), '!') == null);
}

// test attempt
void show(T)(Maybe!T m)
{
    if (!m.attempt(v => writeln(v)))
        writeln("No value");
}

void writeTimes(int i, char c)
{
    foreach (n; 0..i)
        write(c);
    writeln();
}

void main(string[] args)
{
    apply!writeTimes(maybe(5), 'x');
    apply!writeTimes(4, maybe('f'));
    apply!writeTimes(maybe(2), maybe('c'));
    apply!writeTimes(1, 'e');
    // template function
    apply!writeln(maybe("maybe "), "sentence");
    
    // test with int, filter, valueOr
    Maybe!int m;
    assert(m == null);
    m = 7;
    assert(m == 7);
    m.show();
    m.filter(x => x != 7).show();
    m = null;
    assert(m == null);
    assert(m.valueOr(-1) == -1);
    m = maybe(6);
    assert(m.valueOr(-1) == 6);
    m.filter(x => x != 0).show();

    // test map
    // Note: map type inference for both T and U causes dmd 2.059 to abort
    //~ auto m2 = m.map(i => i * 2);
    auto m2 = m.map((int i) => i * 2);
    assert(m2 == m.map!int(i => i * 2));
    assert(m2 == 12);
    auto j = maybe(7).map((int i) => i * 0.5);
    assert(is(typeof(j) == Maybe!double));
    assert(j != null);
    assert(j == 3.5);
    j.show();
    j = 0.2;
    assert(j == 0.2);
    
    auto s = "hi there";
    foreach (size_t i, typeof(s[0]) e; maybe(s))
    {
        assert(s[i++] == e);
        write(e);
    }

    auto r = maybe(args);
    foreach (string s; r)
        writeln(s);
    r.attempt(v => assert(v is args));
    assert(r.valueOr(null) is args);
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
    
    writeln("Testing floating point:");
    assert(maybe(2.0).map((double x) => x/3) == 2.0/3);
    double d;
    maybe(d).show();
    //~ assert(d is double.nan); // fails for some reason
    assert(d is double.init);
    assert(maybe(d) == null);
    // nan != nan
    assert(maybe(d) != maybe(d));
    assert(Maybe!double() != Maybe!double());
    d = 2.5;
    assert(maybe(d) != null);
    assert(maybe(d) == maybe(d));
    assert(maybe(d) == maybe(2.5));
}
