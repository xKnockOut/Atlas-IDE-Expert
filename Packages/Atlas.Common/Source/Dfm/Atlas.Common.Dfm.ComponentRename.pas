unit Atlas.Common.Dfm.ComponentRename;

// Ereignis-Handler beim Umbenennen einer Komponente mitziehen (#45):
// Die IDE benennt Handler nach der Komponente (Button1 → Button1Click). Wird
// Button1 zu btnSpeichern, sollen solche Handler btnSpeichernClick heißen.
// Handler mit eigenem Namen (z. B. SpeichernAusfuehren) bleiben unverändert.

interface

uses
  System.SysUtils,
  Atlas.Common.Dfm.Contract;

type
  THandlerRename = record
    OldName: string;
    NewName: string;
  end;

  TDfmComponentRename = class
  public
    /// <summary>Umbenennungen der automatisch benannten Handler, wenn die Formulardatei
    /// eine Komponente AOldName enthält; sonst leer. Jeder Handler kommt einmal vor.</summary>
    class function Handlers(const ADfmText, AOldName, ANewName: string): TArray<THandlerRename>; static;
  end;

implementation

uses
  Atlas.Common.Dfm.Parser;

function FindObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  Child: TDfmObject;
begin
  Result := nil;
  if AObject = nil then
    Exit;
  if SameText(AObject.Name, AName) then
    Exit(AObject);
  for Child in AObject.Children do
  begin
    Result := FindObject(Child, AName);
    if Result <> nil then
      Exit;
  end;
end;

procedure Collect(AObject: TDfmObject; const AOldName, ANewName: string; var AResult: TArray<THandlerRename>);
var
  Item: TDfmProperty;
  Child: TDfmObject;
  Rename: THandlerRename;
  Known: THandlerRename;
  Seen: Boolean;
begin
  for Item in AObject.Properties do
  begin
    // Nur "<Komponente><Ereignis>", nicht der Komponentenname allein.
    if not Item.IsEvent or (Length(Item.Value) <= Length(AOldName)) or
      not SameText(Copy(Item.Value, 1, Length(AOldName)), AOldName) then
      Continue;
    Seen := False;
    for Known in AResult do
      if SameText(Known.OldName, Item.Value) then
        Seen := True;
    if Seen then
      Continue;
    Rename.OldName := Item.Value;
    Rename.NewName := ANewName + Copy(Item.Value, Length(AOldName) + 1, MaxInt);
    AResult := AResult + [Rename];
  end;
  for Child in AObject.Children do
    Collect(Child, AOldName, ANewName, AResult);
end;

class function TDfmComponentRename.Handlers(const ADfmText, AOldName, ANewName: string): TArray<THandlerRename>;
var
  Document: TDfmDocument;
begin
  Result := nil;
  if (AOldName = '') or SameText(AOldName, ANewName) then
    Exit;
  Document := TDfmParser.Parse(ADfmText);
  try
    // Das Formular selbst ist keine Komponente; sein Name ist die Klasse ohne T.
    if (Document.Root = nil) or (FindObject(Document.Root, AOldName) = nil) or
      SameText(Document.Root.Name, AOldName) then
      Exit;
    Collect(Document.Root, AOldName, ANewName, Result);
  finally
    Document.Free;
  end;
end;

end.
