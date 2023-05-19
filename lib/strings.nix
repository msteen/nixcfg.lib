{
  self,
  lib,
}: {
  concatStringsEnglish = sep: list: let
    listLength = lib.length list;
    lastIndex = listLength - 1;
  in
    if listLength == 0
    then ""
    else if listLength == 1
    then lib.head list
    else if listLength == 2
    then "${lib.head list} ${sep} ${lib.elemAt list 1}"
    else lib.concatStringsSep ", " (lib.sublist 0 lastIndex list ++ [ "${sep} ${lib.elemAt list lastIndex}" ]);
  concatStringsAnd = self.concatStringsEnglish "and";
  concatNames = list: self.concatStringsAnd (map (name: "'${name}'") list);
}
