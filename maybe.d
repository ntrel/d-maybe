/* Written in the D programming language.
 * Copyright Nick Treleaven 2012.
 * Distributed under the Boost Software License, Version 1.0.
 * (See accompanying file LICENSE_1_0.txt or copy at
 * http://www.boost.org/LICENSE_1_0.txt)
 * 
 * Maintained at: http://github.com/ntrel/d-maybe
 * Tested with dmd 2.060.
 */
import std.stdio;
import std.typecons;
import std.traits;

struct None {}

/// Invalid value used for assignment/comparison with a Maybe instance.
None none;

private template hasNullInit(T)
{
    // is T.init an invalid value?
    enum hasNullInit =
        is(typeof(T.init == null)) || is(typeof(T.init == T.nan)) ||
            isSomeChar!T || isDynamicArray!T;
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
// similar to Haskell's Maybe or Scala's Option but without monads or OOP.
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
        
    void opAssign(None)
    {
        val.nullify();
    }
    
    /** Tests whether the Maybe value is valid and equal to v.
     * ---
     * assert(maybe(5) == 5);
     * assert(maybe(5) != 6);
     * ---
     */
    bool opEquals(T v)
    {
        Maybe!T m = v;
        return this == m;
    }
    
    /** Tests whether the Maybe value is valid, m is valid, and both values are equal.
     * ---
     * assert(maybe(5) == maybe(5));
     * assert(maybe(5) != maybe(6));
     * ---
     */
    bool opEquals(Maybe!T m)
    {
        if (m == none && this == none)
            return !is(typeof(T.init == T.nan)); // preserve nan != nan
        return (m != none && this != none && m.val == this.val);
    }
    
    unittest
    {
        // if this fails, remove opEquals workaround below
        assert(!Nullable!(float, float.nan)().isNull);
    }
    
    /** Tests whether the Maybe value is invalid.
     * ---
     * assert(Maybe!int() == none);
     * assert(maybe(5) != none);
     * ---
     */
    bool opEquals(None)
    {
        // workaround as Nullable.isNull doesn't use 'is' for nan
        static if (hasNullInit!T)
            return val.isNull || val.get is T.init;
        else
            return val.isNull;
    }
    
    /* We should probably use delegate(scope T) everywhere to prevent
     * escaping, but that doesn't compile with dmd 2.060 */
    /** Returns a copy of the Maybe struct if pred returns true, or
     * an invalid Maybe struct if pred returns false. */
    Maybe!T filter(scope bool delegate(T) pred)
    {
        Maybe!T m;
        if (this != none && pred(val.get))
            m = this;
        return m;
    }
    
    /** Converts the Maybe value into a T, returning invalidValue if invalid.
     * invalidValue can be null, but at least this is explicit:
     * ---
     * Maybe!Object m = ...;
     * Object w = m.valueOr(alternativeObject);
     * Object v = m.valueOr(null);
     * ---
     * Params: invalidValue = Value to return if the Maybe value is invalid.
     * Note: It's safer to avoid using valueOr if possible.
     */
    // Possible names: valueOrElse, getOrElse
    T valueOr(T invalidValue)
    {
        return this == none ? invalidValue : val.get;
    }
    
    static if (is(ForeachType!T FT))
        alias FT ElementType;

    int opApply()(scope int delegate(ref ElementType) dg)
        if (is(ElementType))
    {
        return opApply((ref i, ref e)=>dg(e));
    }

    // foreach inference doesn't work and size_t seems to need ref with dmd 2.060
    int opApply()(scope int delegate(ref size_t, ref ElementType) dg)
        if (is(ElementType))
    {
        if (this == none)
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

unittest
{
    auto s = Maybe!string();
    assert(s == none);
    assert(s == null);
    s = "hi";
    assert(s == "hi");
    assert(s != none);
    assert(s != null);
    s = null;
    assert(s == null);
    assert(s == none);
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

// code for match
private template applyCode(Args...)
{
    string argString()
    {
        string s;
        foreach (i, Arg; Args)
        {
            if (!s.empty)
                s ~= ", ";
            s ~= "args[" ~ to!string(i) ~ "]";
            
            static if (isMaybe!(Arg))
                s ~= ".val.get";
        }
        return s;
    }

    enum applyCode = "validFun(" ~ argString() ~ ");";
}

private bool allValid(Args...)(Args args)
{
    foreach (arg; args)
    {
        static if (isMaybe!(typeof(arg)))
            if (arg == none)
                return false;
    }
    return true;
}

/* don't include template functions otherwise we can't distinguish
 * when validFun is e.g. writeln or text */
private template isInvalidFun(alias fun)
{
    enum isInvalidFun = __traits(compiles, {fun();}) &&
        isSomeFunction!fun;
        // doesn't work, 2.060
        //~ && variadicFunctionStyle!fun == Variadic.no;
}

/// Eponymous template.
template match(alias validFun, alias invalidFun)
    if (isInvalidFun!invalidFun)
{
    /** Attempts to call validFun(args), but with any Maybe instances in args unwrapped.
     * If any Maybe instance in args is invalid, calls invalidFun() instead.
     * invalidFun may return either void or the same type as validFun.
     * Returns: The result of validFun/invalidFun, if any, wrapped in a Maybe.
     * Examples:
     * ---
     * assert(match!(to!string, ()=>"<invalid>")(maybe(2)) == "2");
     * assert(match!(to!string, ()=>"<invalid>")(Maybe!int()) == "<invalid>");
     * assert(match!(to!string, {})(maybe(2)) == "2");
     * assert(match!(to!string, {})(Maybe!int()) == none);
     * assert(match!((x, y)=>text(x, y), {})(maybe(2), maybe(34)) == "234");
     * assert(match!((x, y)=>text(x, y), {})(Maybe!int(), maybe(34)) == none);
     * ---
     * Arguments to match don't have to be Maybe instances:
     * ---
     * assert(match!(text, {})(1, maybe(2), 3) == "123");
     * ---
     * The order of validFun and invalidFun can be reversed:
     * ---
     * assert(match!({}, text)(maybe('m')) == "m");
     * assert(match!({}, text)(Maybe!char()) == none);
     * ---
     */
    auto match(Args...)(Args args)
        if (is(typeof({mixin(applyCode!Args);})))
    {
        // remove semicolon from applyCode so lambda can return a value
        alias typeof((()=>mixin(applyCode!Args[0..$-1]))()) Ret;
        static if (is(Ret == void))
        {
            if (allValid(args))
                mixin(applyCode!Args);
            else
                invalidFun();
        }
        else
        {
            Maybe!Ret result;
            if (allValid(args))
                mixin("result = " ~ applyCode!Args);
            else
            {
                static if (is(typeof((()=>invalidFun())()) == void))
                    invalidFun();
                else
                    result = invalidFun();
            }
            return result;
        }
    }
}

unittest
{
    assert(match!(text, {})(1, maybe(2), 3) == "123");
    assert(match!(to!string, ()=>"<invalid>")(maybe(2)) == "2");
    assert(match!(to!string, ()=>"<invalid>")(Maybe!int()) == "<invalid>");
    assert(match!(to!string, ()=>"<invalid>")(Maybe!int()) != none);
    assert(match!(to!string, ()=>null)(maybe(2)) == "2");
    assert(match!(to!string, ()=>null)(Maybe!int()) == none);
    assert(match!(to!string, {})(maybe(2)) == "2");
    assert(match!(to!string, {})(Maybe!int()) == none);
    assert(match!((x, y)=>text(x, y), {})(maybe(2), maybe(34)) == "234");
    assert(match!((x, y)=>text(x, y), {})(Maybe!int(), maybe(34)) == none);
    assert(match!((x, y)=>text(x, y), ()=>"none")(Maybe!int(), maybe(34)) == "none");
    
    static assert(!__traits(compiles, match!({}, {})(maybe(2))));
    static assert(__traits(compiles, match!(x=>x, ()=>0.0F)(1.0F)));
    static assert(__traits(compiles, match!(x=>x, ()=>0.0F)(maybe(1.0F))));
    static assert(!is(typeof(match!(to!string, null)(0))));
    static assert(!is(typeof(match!({}, {})(0))));
    static assert(!is(typeof(match!(to!string, to!char)(0))));
}

/// ditto
template match(alias invalidFun, alias validFun)
    if (isInvalidFun!invalidFun)
{
    alias match!(validFun, invalidFun) match;
}

unittest
{
    assert(match!({}, text)(maybe('m')) == "m");
    assert(match!({}, text)(Maybe!char()) == none);
    assert(match!(()=>-1, x=>x)(maybe(2)) == 2);
    assert(match!(()=>-1, x=>x)(Maybe!int()) == -1);
    assert(match!({}, x=>x)(maybe(2)) == 2);
    assert(match!({}, x=>x)(Maybe!int()) == none);
    assert(match!({}, x=>x)(maybe('m')) == 'm');
}

// based on an idea by Simen Kjaeraas
/// Eponymous template.
template matchVal(alias validFun, alias invalidFun)
    if (isInvalidFun!invalidFun)
{
    /** Attempts to call validFun(args), but with any Maybe instances in args unwrapped.
     * If any Maybe instance in args is invalid, calls invalidFun() instead.
     * invalidFun has to return the same type as validFun.
     * The return type is not allowed to be a 'nullable' type like Object or float,
     * which is why the result is not wrapped in a Maybe.
     * Returns: The actual result of validFun/invalidFun.
     * Example:
     * ---
     * assert(matchVal!(x=>2*x, ()=>-1)(maybe(4)) is 8);
     * assert(matchVal!(x=>2*x, ()=>-1)(Maybe!int()) is -1);
     * assert(matchVal!(()=>-1, x=>2*x)(maybe(4)) is 8);
     * ---
     */
    auto matchVal(Args...)(Args args)
        if (is(typeof(match!(validFun, invalidFun)(args))))
    {
        auto m = match!(validFun, invalidFun)(args);
        static assert(is(m.Type == ReturnType!invalidFun));
        static assert(!hasNullInit!(m.Type));
        return m.val;
    }
}

/// ditto
template matchVal(alias invalidFun, alias validFun)
    if (isInvalidFun!invalidFun)
{
    alias matchVal!(validFun, invalidFun) matchVal;
}

unittest
{
    assert(matchVal!(()=>-1, x=>2*x)(maybe(4)) is 8);
    assert(matchVal!(x=>2*x, ()=>-1)(maybe(4)) is 8);
    assert(matchVal!(x=>2*x, ()=>-1)(Maybe!int()) is -1);
    static assert(!__traits(compiles, matchVal!(x=>x, {})(maybe(2))));
    static assert(!__traits(compiles, matchVal!(x=>x, ()=>0.0F)(maybe(1.0F))));
    static assert(!__traits(compiles, matchVal!(x=>x, ()=>null)(maybe("string"))));
}

/// Eponymous template.
template attempt(alias fun)
{
    /** Attempts to call fun(args), but with any Maybe instances in args unwrapped.
     * Does nothing if any Maybe instance in args is invalid.
     * Equivalent to <tt>match!(fun, {})(args)</tt>.
     * Returns: The result of fun, if any, wrapped in a Maybe.
     * Example:
     * ---
     * assert(attempt!(x => 2*x)(maybe(5)) == 10);
     * assert(attempt!text(maybe("hi"), 5) == "hi5");
     * assert(attempt!text(6, Maybe!string()) == none);
     * ---
     */
    alias match!(fun, {}) attempt;
}

unittest
{
    assert(attempt!(x => 2*x)(maybe(5)) == 10);
    assert(attempt!text(maybe("hi"), 5) == "hi5");
    assert(attempt!text(6, Maybe!string()) == none);
    assert(attempt!text(maybe(7)) == "7");
    assert(attempt!text(maybe(7), '!') == "7!");
    assert(attempt!text(Maybe!int(), '!') == none);
}

private:

// test match
void show(T)(Maybe!T m)
{
    match!(writeln, ()=>writeln("No value"))(m);
    // dmd 2.060: match!(lambda, {}, Maybe!double).match is a nested function
    // and cannot be accessed from show!(double).show
    //~ match!(v => writeln(v), {})(m);
    //~ match!(v => writeln(v), ()=>writeln("No value"))(m);
}

void writeTimes(int i, char c)
{
    foreach (n; 0..i)
        write(c);
    writeln();
}

void main(string[] args)
{
    attempt!writeTimes(maybe(5), 'x');
    attempt!writeTimes(4, maybe('f'));
    attempt!writeTimes(maybe(2), maybe('c'));
    attempt!writeTimes(1, 'e');
    // template function
    attempt!writeln(maybe("maybe "), "sentence");
    
    // test with int, filter, valueOr
    Maybe!int m;
    assert(m == none);
    m = 7;
    assert(m == 7);
    m.show();
    m.filter(x => x != 7).show();
    m = none;
    assert(m == none);
    assert(m.valueOr(-1) == -1);
    m = maybe(6);
    assert(m.valueOr(-1) == 6);
    m.filter(x => x != 0).show();

    // test attempt
    auto m2 = m.attempt!(i => i * 2)();
    assert(m2 == 12);
    auto j = maybe(7).attempt!(i => i * 0.5)();
    assert(is(typeof(j) == Maybe!double));
    assert(j != none);
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
    r.match!(v => assert(v is args), {assert(0);})();
    assert(r.valueOr(null) is args);
    r = none;
    assert(r == none);
    r.show();
    r.valueOr(null).writeln();
    
    // test with Object and opEquals
    Maybe!Object o;
    assert(o == none);
    o = new Object();
    assert(o != none);
    o = o.filter(x => true);
    assert(o != none);
    auto o2 = o;
    assert(o == o2);
    o2 = new Object();
    assert(o != o2);
    o2 = none;
    assert(o != o2);
    o = none;
    assert(o == none);
    assert(o == o2);
    
    writeln("Testing floating point:");
    assert(maybe(2.0).attempt!(x => x/3)() == 2.0/3);
    double d;
    maybe(d).show();
    //~ assert(d is double.nan); // fails for some reason
    assert(d is double.init);
    assert(maybe(d) == none);
    // nan != nan
    assert(maybe(d) != maybe(d));
    assert(Maybe!double() != Maybe!double());
    d = 2.5;
    assert(maybe(d) != none);
    assert(maybe(d) == maybe(d));
    assert(maybe(d) == maybe(2.5));
    
    assert(maybe('c') == 'c');
    assert(maybe('c') != none);
    assert(Maybe!char() == none);
    assert(Maybe!dchar() == none);
}
