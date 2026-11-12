unit Atlas.Common.Dfm.ComponentRename;

// Ereignis-Handler beim Umbenennen einer Komponente mitziehen (#45):
// Die IDE benennt Handler nach der Komponente (Button1 → Button1Click). Wird
// Button1 zu btnSpeichern, sollen solche Handler btnSpeichernClick heißen.
// Handler mit eigenem Namen (z. B. SpeichernAusfuehren) bleiben unverändert.

interface

uses
  System.SysUtils;

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
  Atlas.Common.Dfm.Contract,
  Atlas.Common.Dfm.Parser;

function FindObject(AObject: TDfmObject; const AName: string): TDfmObject;
var
  mChild: TDfmObject;
begin
  Result := nil;
  if AObject = nil then
  begin
    Exit;
  end;
  if SameText(AObject.Name, AName) then
  begin
    Exit(AObject);
  end;
  for mChild in AObject.Children do
  begin
    Result := FindObject(mChild, AName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
end;

procedure Collect(AObject: TDfmObject; const AOldName, ANewName: string; var AResult: TArray<THandlerRename>);
var
  mItem: TDfmProperty;
  mChild: TDfmObject;
  mRename: THandlerRename;
  mKnown: THandlerRename;
  mSeen: Boolean;
begin
  for mItem in AObject.Properties do
  begin
    // Nur "<Komponente><Ereignis>", nicht der Komponentenname allein.
    if not mItem.IsEvent or (Length(mItem.Value) <= Length(AOldName)) or
      not SameText(Copy(mItem.Value, 1, Length(AOldName)), AOldName) then
    begin
      Continue;
    end;
    mSeen := False;
    for mKnown in AResult do
    begin
      if SameText(mKnown.OldName, mItem.Value) then
      begin
        mSeen := True;
      end;
    end;
    if mSeen then
    begin
      Continue;
    end;
    mRename.OldName := mItem.Value;
    mRename.NewName := ANewName + Copy(mItem.Value, Length(AOldName) + 1, MaxInt);
    AResult := AResult + [mRename];
  end;
  for mChild in AObject.Children do
  begin
    Collect(mChild, AOldName, ANewName, AResult);
  end;
end;

class function TDfmComponentRename.Handlers(const ADfmText, AOldName, ANewName: string): TArray<THandlerRename>;
var
  mDocument: TDfmDocument;
begin
  Result := nil;
  if (AOldName = '') or SameText(AOldName, ANewName) then
  begin
    Exit;
  end;
  mDocument := TDfmParser.Parse(ADfmText);
  try
    // Das Formular selbst ist keine Komponente; sein Name ist die Klasse ohne T.
    if (mDocument.Root = nil) or (FindObject(mDocument.Root, AOldName) = nil) or
      SameText(mDocument.Root.Name, AOldName) then
    begin
      Exit;
    end;
    Collect(mDocument.Root, AOldName, ANewName, Result);
  finally
    mDocument.Free;
  end;
end;

end.
