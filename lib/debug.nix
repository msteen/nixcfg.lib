{
  self,
  lib,
}: {
  traceJSON = x: y: lib.trace (lib.toJSON x) y;
  traceJSONValFn = f: x: self.traceJSON (f x) x;
  traceJSONVal = self.traceJSONValFn lib.id;

  fails = expr: !(builtins.tryEval (builtins.deepSeq expr expr)).success;
}
