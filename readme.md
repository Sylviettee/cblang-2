# CBLang-2

CBLang-2 is an implementation of [CBLang](https://github.com/Ceebox/cbLang) except for Lua.
I used Lua since [Cadderbox](https://www.youtube.com/c/Chadderbox) *dislikes* Lua.

CBLang-2 transpiles the input code (which is mostly similar to CBLang-2 except for Python v Lua) into Lua.

The *biggest* difference between CBLang and CBLang-2 is that CBLang-2 is held together with *magic* while
CBLang is held together with hopes and dreams.

Plenty of bugs still exist although all the examples work so good enough. When the language becomes bootstrapped,
this may change from plenty of bugs to some bugs.

CBLang-2 is relies on a single dependencies, [LPegRex](https://github.com/edubart/lpegrex) which is used for
parsing the input (if CBLang can use string manipulation, I can use a PEG library).

## Commands

CBLang-2 currently supports 2 commands, `build`, and `run`. "Compiling" (aka bundling) will come soon.

To build code, use `./cb build input.cb [output.cb]`.
To run code, use `./cb run input.cb`

## Hello World

```c#
class Main()
{
   function Main() {
      // Here is a comment!
      print("Hello World");
   }
}
```

If this hello world looks familiar, it's since it's the exact same as the one from CBLang.
This is ran by running `./cb run examples/hello.cb`.

Currently CBLang-2 is not bootstrapped although that is going to change soon.

More examples can be found within the examples directory.

## Differences

Many differences exist between CBLang and CBLang-2 would be that CBLang aims to
be like Python while CBLang-2 aims to be like Lua. This means that a lot of Python 
exclusive syntax is mission out of CBLang-2.

Another difference is CBLang simply manipulates the input string while CBLang-2 creates
a parser and recursively transpiles the input. This means that better error checking exists
within CBLang-2 as invalid outputs are more difficult (or even impossible) to get.
