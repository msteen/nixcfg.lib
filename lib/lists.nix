{
  self,
  lib,
}: {
  maximum = compare: list:
    lib.foldl' (a: b:
      if a == null || compare a b <= 0
      then b
      else a)
    null
    list;

  sort' = list: lib.sort (a: b: a <= b) list;
}
