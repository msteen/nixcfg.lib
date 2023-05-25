{
  self,
  lib,
}: {
  traceJSON = x: y: lib.trace (lib.toJSON x) y;
  traceJSONValFn = f: x: self.traceJSON (f x) x;
  traceJSONVal = self.traceJSONValFn lib.id;

  fails = expr: !(lib.tryEval (lib.deepSeq expr expr)).success;

  evalTests = tests:
    self.concatMapAttrsToList (name: test:
      lib.trace name (lib.optional ((
          if tests ? tests
          then lib.elem name tests.tests
          else lib.hasPrefix "test" name
        )
        && test.expr != test.expected) {
        inherit name;
        inherit (test) expected;
        result = test.expr;
      }))
    tests;
}
