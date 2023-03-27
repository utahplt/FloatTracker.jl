using Core: StackTrace
using Base.StackTraces
using Base.Iterators

struct FunctionRef
  name::Symbol
  file::Symbol
end

"""
Struct describing parameters for injecting NaNs

## Fields

 - `active::Boolean` inject only if true

 - `ninject::Int` maximum number of NaNs to inject; gets decremented every time
   a NaN gets injected

 - `odds::Int` inject a NaN with 1:odds probability—higher value → rarer to
   inject

 - `functions:Array{FunctionRef}` if given, only inject NaNs when within these
   functions; default is to not discriminate on functions

 - `libraries:Array{String}` if given, only inject NaNs when within this library.

`functions` and `libraries` work together as a union: i.e. the set of possible NaN
injection points is a union of the places matched by `functions` and `libraries`.

"""
mutable struct Injector
  active::Bool
  odds::Int
  ninject::Int
  functions::Array{FunctionRef}
  libraries::Array{String}
end

"""
    should_inject(i::Injector)

Return whether or not we should inject a `NaN`.

Decision process:

 - Checks whether or not the given injector is active.

 - Checks that there are some NaNs remaining to inject.

 - Checks that we're inside the scope of a function in `Injector.functions`.
   (Vacuously true if no functions given.)

 - Rolls an `Injector.odds`-sided die; if 1, inject a NaN, otherwise, don't do
   anything.
"""
function should_inject(i::Injector)::Bool
  if i.active && i.ninject > 0
    roll = rand(1:i.odds)

    if roll != 1
      return false
    end

    in_right_fn::Bool = if isempty(i.functions)
      true
    else
      in_functions = function (frame::StackTraces.StackFrame)
        file = Symbol(split(String(frame.file), ['/', '\\'])[end])
        fr = FunctionRef(frame.func, file)
        fr in i.functions
      end
      # TODO: check the head of the stacktrace to make sure it's all our files or standard library files
      # in_functions(stacktrace()[1])
      any(in_functions, stacktrace())
    end

    return roll == 1 && injectable_region(i, stacktrace())
  end

  return false
end

function decrement_injections(i::Injector)
  i.ninject = i.ninject - 1
end

"""
    injectable_region(i::Injector, frames::StackTrace)::Bool

Returns whether or not the current point in the code (indicated by the
StackTrace) is a valid point to inject a NaN.
"""
function injectable_region(i::Injector, raw_frames::StackTraces.StackTrace)::Bool
  # Drop FloatTracker frames
  frames = filter((frame -> frame_library(frame) != "FloatTracker"), raw_frames)

  # If neither functions nor libraries are specified, inject as long as we're
  # not inside the standard library.
  if isempty(i.functions) && isempty(i.libraries) && frame_library(frames[1]) !== nothing
    return true
  end

  # First check the functions set: the head of the stack trace should all be in
  # the file in question; somewhere in that set should be function specified.
  interested_files = map((refs -> refs.file), i.functions)
  in_file_frame_head = Iterators.takewhile((frame -> frame_file(frame) in interested_files), frames)
end

function frame_file(frame)::Symbol
  return Symbol(split(String(frame.file), ['/', '\\'])[end])
end

"""
    frame_library(frame::StackTraces.StackFrame)::Symbol

Return the name of the library that the current stack frame references.

Returns `nothing` if unable to find library.
"""
function frame_library(frame::StackTraces.StackFrame)::Symbol
  # FIXME: this doesn't work with packages that are checked out locally
  lib = match(r".julia[\\/](packages|dev)[\\/]([a-zA-Z][a-zA-Z0-9_.-]*)[\\/]", frame.file)

  if lib === nothing
    return nothing
  else
    return Symbol(lib.captures[2])
  end
end
