unit Postfix;

// Beispiel zur Karte „Neu in Atlas“ (#756): Postfix-Vorlagen (#188).
// Der Cursor steht in Tue. Hinter einen Ausdruck tippen und die
// Vervollständigung (Strg+Leer) wählen:
//   Liste.for     -> for-in-Schleife über die Liste
//   Liste.notnil  -> if Liste <> nil then
//   TStringList.Create.try -> Variable, try … finally Free
// Die Datei gehört zur Installation; Änderungen hier speichert man besser
// unter einem anderen Namen.

interface

uses
  System.Classes;

procedure Tue(Liste: TStrings);

implementation

procedure Tue(Liste: TStrings);
begin
  
end;

end.
